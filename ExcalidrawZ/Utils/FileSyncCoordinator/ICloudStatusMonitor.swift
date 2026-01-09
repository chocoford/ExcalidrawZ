//
//  ICloudStatusMonitor.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/26/25.
//

import Foundation
import Logging

actor ICloudStatusMonitor {
    private let logger = Logger(label: "ICloudStatusMonitor")
    
    private let folderURL: URL
    private let options: FolderSyncOptions
    private let statusChecker = ICloudStatusChecker.shared
    
#if os(macOS)
    @MainActor
    private var query: NSMetadataQuery?
#elseif os(iOS)
    /// Polling tasks for different monitoring levels
    private var activePollingTask: Task<Void, Never>?
    private var visiblePollingTask: Task<Void, Never>?
    private var backgroundPollingTask: Task<Void, Never>?
    
    /// Track monitoring level for each file
    private var fileMonitoringLevels: [URL: FileMonitoringLevel] = [:]
#endif
    
    private var isMonitoring = false
    
    init(folderURL: URL, options: FolderSyncOptions) {
        self.folderURL = folderURL
        self.options = options
    }
    
    func start() async {
        guard !isMonitoring else { return }
        
#if os(macOS)
        await MainActor.run {
            setupMetadataQuery()
        }
#elseif os(iOS)
        startIOSPolling()
#endif
        
        isMonitoring = true
        logger.info("iCloud monitoring started for: \(folderURL.filePath)")
    }
    
    func stop() async {
        guard isMonitoring else { return }
        
#if os(macOS)
        await MainActor.run {
            query?.stop()
            query = nil
            NotificationCenter.default.removeObserver(self)
        }
#elseif os(iOS)
        activePollingTask?.cancel()
        visiblePollingTask?.cancel()
        backgroundPollingTask?.cancel()
        activePollingTask = nil
        visiblePollingTask = nil
        backgroundPollingTask = nil
        fileMonitoringLevels.removeAll()
#endif
        
        isMonitoring = false
        logger.info("iCloud monitoring stopped for: \(folderURL.filePath)")
    }
    
    // MARK: - macOS Implementation (NSMetadataQuery)
    
#if os(macOS)
    @MainActor
    private func setupMetadataQuery() {
        query = NSMetadataQuery()
        guard let query = query else { return }
        
        // Set search scope to this specific folder
        query.searchScopes = [folderURL]
        
        // Build predicate for file extensions
        let predicates: [NSPredicate]
        if options.fileExtensions.isEmpty {
            predicates = []
        } else {
            predicates = options.fileExtensions.map { ext in
                NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*.\(ext)")
            }
        }
        
        query.predicate = predicates.count > 1
        ? NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        : predicates.first
        
        // Register for notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidFinishGathering(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        
        query.start()
    }
    
    @MainActor
    @objc private func metadataQueryDidFinishGathering(_ notification: Notification) {
        self.logger.info("metadataQueryDidFinishGathering...")
        Task {
            guard let query = notification.object as? NSMetadataQuery else { return }
            query.disableUpdates()
            await processMetadataResults(query.results)
            query.enableUpdates()
        }
        
    }
    
    @MainActor
    @objc private func metadataQueryDidUpdate(_ notification: Notification) {
        Task {
            guard let query = notification.object as? NSMetadataQuery else { return }
            query.disableUpdates()
            await processMetadataResults(query.results)
            query.enableUpdates()
        }
    }
    
    private func processMetadataResults(_ results: [Any]) async {
        for item in results {
            guard let metadataItem = item as? NSMetadataItem else { continue }
            await processMetadataItem(metadataItem)
        }
    }
    
    private func processMetadataItem(_ item: NSMetadataItem) async {
        // Extract file URL
        let fileURL: URL?
        
        if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
            fileURL = url
        } else if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
            fileURL = URL(fileURLWithPath: path)
        } else {
            fileURL = nil
        }
        guard let fileURL else { return }
        guard fileURL.filePath.hasPrefix(folderURL.filePath) else { return }
        
        // Use ICloudStatusChecker to get actual iCloud status
        // NSMetadataQuery only tells us the file changed, not its actual status
        let status: ICloudFileStatus
        do {
            status = try await statusChecker.checkStatus(for: fileURL)
            logger.info("Resolved iCloud status for \(fileURL.lastPathComponent): \(String(describing: status))")
        } catch {
            logger.error("Failed to resolve iCloud status for \(fileURL.lastPathComponent): \(error)")
            status = .error(error.localizedDescription)
        }
        
        // Update status registry directly
        await FileSyncCoordinator.shared.updateFileStatus(for: fileURL, status: status)
    }
#endif
    
#if os(iOS)
    /// Set monitoring level for a specific file (iOS only)
    func setFilesMonitoringLevel(_ filesURL: [URL], level: FileMonitoringLevel) async {
        // Update monitoring level
        for fileURL in filesURL {
            let oldLevel = fileMonitoringLevels[fileURL]
            fileMonitoringLevels[fileURL] = level
            
            logger.info(
                "File monitoring level changed: \(fileURL.lastPathComponent) \(String(describing: oldLevel)) -> \(level)"
            )
        }
        // Restart polling tasks if monitoring is active
        if isMonitoring {
            restartIOSPolling()
        }
    }
#endif
    
    // MARK: - iOS Implementation (URLResourceValues Polling)
    
#if os(iOS)
    private func startIOSPolling() {
        // Initialize all files as background level
        let allFiles = getFilesInFolder()
        for fileURL in allFiles {
            if fileMonitoringLevels[fileURL] == nil {
                fileMonitoringLevels[fileURL] = .never
            }
        }
        
        restartIOSPolling()
        logger.info("iOS tiered polling started")
    }
    
    private func restartIOSPolling() {
        // Cancel existing tasks
        activePollingTask?.cancel()
        visiblePollingTask?.cancel()
        backgroundPollingTask?.cancel()

        // Start polling tasks for visible and background only
        // Active files use auto-sync mechanism instead of polling
        activePollingTask = nil
        visiblePollingTask = startPollingTask(for: .visible)
        backgroundPollingTask = startPollingTask(for: .background)
    }
    
    private func startPollingTask(for level: FileMonitoringLevel) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                await pollFilesAtLevel(level)
                
                // Wait for next polling interval
                try? await Task.sleep(for: .seconds(level.pollingInterval))
            }
        }
    }
    
    private func pollFilesAtLevel(_ level: FileMonitoringLevel) async {
        // Get files at this monitoring level
        let files = fileMonitoringLevels.filter { $0.value == level }.map { $0.key }
        
        guard !files.isEmpty else { return }
        
        logger.info("Polling \(files.count) \(level) files")
        
        // Check status for each file
        for fileURL in files {
            guard !Task.isCancelled else { break }
            
            let status: ICloudFileStatus
            do {
                status = try await statusChecker.checkStatus(for: fileURL)
            } catch {
                logger.error("Failed to check status for \(fileURL.lastPathComponent): \(error)")
                status = .error(error.localizedDescription)
            }
            logger.info("  - \(fileURL.lastPathComponent) -- \(status)")
            
            // Update status registry
            await FileSyncCoordinator.shared.updateFileStatus(for: fileURL, status: status)
        }
        logger.info("Polling done.")
    }
    
    private func getFilesInFolder() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            logger.error("Failed to create enumerator for folder: \(folderURL.filePath)")
            return []
        }
        
        var fileURLs: [URL] = []
        
        for case let fileURL as URL in enumerator {
            // Check if it's a regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            // Check file extension filter
            if !options.fileExtensions.isEmpty {
                let matchesExtension = options.fileExtensions.contains { ext in
                    fileURL.pathExtension == ext
                }
                guard matchesExtension else { continue }
            }
            
            fileURLs.append(fileURL)
        }
        
        return fileURLs
    }
#endif
    
}
