//
//  FolderMonitor.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/23/25.
//

import Foundation
import Logging

#if os(macOS)
import FSEventsWrapper
#endif

/// Monitors a folder for file system changes and iCloud status updates.
///
/// This actor provides dual monitoring:
/// 1. File system events (create, modify, delete, rename)
/// 2. iCloud status changes (download, upload, conflicts)
///
/// File system events are reported via the `onFileEvent` callback.
/// iCloud status updates are sent directly to FileSyncCoordinator for processing.
actor FolderMonitor {
    // MARK: - Properties

    private let logger = Logger(label: "FolderMonitor")

    let folderURL: URL
    let options: FolderSyncOptions
    let onFileEvent: (FileEvent) async -> Void

    /// File system monitor (platform-specific)
    private var fileSystemMonitor: FileSystemMonitorProtocol?

    /// iCloud status monitor (NSMetadataQuery-based)
    private var iCloudMonitor: ICloudStatusMonitor?

    /// Whether monitoring is currently active
    private var isMonitoring = false

    // MARK: - Initialization

    init(
        folderURL: URL,
        options: FolderSyncOptions,
        onFileEvent: @escaping (FileEvent) async -> Void
    ) {
        self.folderURL = folderURL
        self.options = options
        self.onFileEvent = onFileEvent
    }

    // MARK: - Control

    /// Start monitoring the folder
    func start() async throws {
        guard !isMonitoring else {
            logger.warning("Folder already being monitored: \(folderURL.lastPathComponent)")
            return
        }

        logger.info("Starting folder monitor for: \(folderURL.lastPathComponent)")

        // Start file system monitoring
        try await startFileSystemMonitoring()

        // Start iCloud monitoring if enabled
        if options.autoCheckICloudStatus {
            await startICloudMonitoring()
        }

        isMonitoring = true
        logger.info("Successfully started monitoring: \(folderURL.lastPathComponent)")
    }

    /// Stop monitoring the folder
    func stop() async {
        guard isMonitoring else { return }

        logger.info("Stopping folder monitor for: \(folderURL.lastPathComponent)")

        // Stop file system monitoring
        await stopFileSystemMonitoring()

        // Stop iCloud monitoring
        await stopICloudMonitoring()

        isMonitoring = false
        logger.info("Successfully stopped monitoring: \(folderURL.lastPathComponent)")
    }

    // MARK: - File System Monitoring

    private func startFileSystemMonitoring() async throws {
        #if os(macOS)
        fileSystemMonitor = try MacOSFileSystemMonitor(
            folderURL: folderURL,
            options: options,
            onEvent: { [weak self] event in
                await self?.onFileEvent(event)
            }
        )
        #elseif os(iOS)
        fileSystemMonitor = await IOSFileSystemMonitor(
            folderURL: folderURL,
            options: options,
            onEvent: { [weak self] event in
                await self?.onFileEvent(event)
            }
        )
        #endif

        try await fileSystemMonitor?.start()
        logger.debug("File system monitoring started")
    }

    private func stopFileSystemMonitoring() async {
        await fileSystemMonitor?.stop()
        fileSystemMonitor = nil
        logger.debug("File system monitoring stopped")
    }

    // MARK: - iCloud Monitoring

    private func startICloudMonitoring() async {
        // Check if folder is in iCloud Drive
        guard isInICloudDrive(url: folderURL) else {
            logger.debug("Folder not in iCloud Drive, skipping iCloud monitoring")
            return
        }

        iCloudMonitor = ICloudStatusMonitor(
            folderURL: folderURL,
            options: options
        )

        await iCloudMonitor?.start()
        logger.debug("iCloud status monitoring started")
    }

    private func stopICloudMonitoring() async {
        await iCloudMonitor?.stop()
        iCloudMonitor = nil
        logger.debug("iCloud status monitoring stopped")
    }

    // MARK: - Helpers

    private func isInICloudDrive(url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            return values.isUbiquitousItem == true
        } catch {
            return false
        }
    }
}

// MARK: - File System Monitor Protocol

/// Protocol for platform-specific file system monitors
protocol FileSystemMonitorProtocol: Actor {
    func start() async throws
    func stop() async
}

// MARK: - macOS File System Monitor

#if os(macOS)
actor MacOSFileSystemMonitor: FileSystemMonitorProtocol {
    private let logger = Logger(label: "MacOSFileSystemMonitor")

    private let folderURL: URL
    private let options: FolderSyncOptions
    private let onEvent: (FileEvent) async -> Void

    private var monitorTask: Task<Void, Never>?

    init(
        folderURL: URL,
        options: FolderSyncOptions,
        onEvent: @escaping (FileEvent) async -> Void
    ) throws {
        self.folderURL = folderURL
        self.options = options
        self.onEvent = onEvent
    }

    func start() async throws {
        // Cancel existing task
        monitorTask?.cancel()

        // Start new monitoring task
        monitorTask = Task {
            // Access security scoped resource if needed
            let accessing = folderURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // Monitor file system events
            for await event in FSEventAsyncStream(
                path: folderURL.path,
                flags: FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
            ) {
                await handleFSEvent(event)
            }
        }
    }

    func stop() async {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func handleFSEvent(_ event: FSEvent) async {
        switch event {
        case .itemCreated(let path, let itemType, _, _):
            if shouldMonitorFile(path: path, itemType: itemType) {
                await onEvent(.created(URL(fileURLWithPath: path)))
            }

        case .itemDataModified(let path, let itemType, _, _):
            if shouldMonitorFile(path: path, itemType: itemType) {
                await onEvent(.modified(URL(fileURLWithPath: path)))
            }

        case .itemRemoved(let path, let itemType, _, _):
            if shouldMonitorFile(path: path, itemType: itemType) {
                await onEvent(.deleted(URL(fileURLWithPath: path)))
            }

        case .itemRenamed(let path, let itemType, _, _):
            if shouldMonitorFile(path: path, itemType: itemType) {
                // Note: FSEvents doesn't provide old path for renames
                // We treat rename as modify for now
                await onEvent(.modified(URL(fileURLWithPath: path)))
            }

        default:
            break
        }
    }

    private func shouldMonitorFile(path: String, itemType: FSEvent.ItemType) -> Bool {
        // Only monitor files, not directories
        guard itemType == .file else { return false }

        // Check file extension filter
        guard !options.fileExtensions.isEmpty else { return true }

        return options.fileExtensions.contains { ext in
            path.hasSuffix(".\(ext)")
        }
    }
}
#endif

// MARK: - iOS File System Monitor

#if os(iOS)
actor IOSFileSystemMonitor: NSObject, FileSystemMonitorProtocol, NSFilePresenter {
    private let logger = Logger(label: "IOSFileSystemMonitor")

    private let folderURL: URL
    private let options: FolderSyncOptions
    private let onEvent: (FileEvent) async -> Void

    // NSFilePresenter requirements
    nonisolated var presentedItemURL: URL? { folderURL }
    nonisolated lazy var presentedItemOperationQueue = OperationQueue.main

    private var isActive = false

    init(
        folderURL: URL,
        options: FolderSyncOptions,
        onEvent: @escaping (FileEvent) async -> Void
    ) {
        self.folderURL = folderURL
        self.options = options
        self.onEvent = onEvent
        super.init()
    }

    func start() async throws {
        guard !isActive else { return }

        // Access security scoped resource
        _ = folderURL.startAccessingSecurityScopedResource()

        // Register as file presenter
        NSFileCoordinator.addFilePresenter(self)
        isActive = true
    }

    func stop() async {
        guard isActive else { return }

        NSFileCoordinator.removeFilePresenter(self)
        folderURL.stopAccessingSecurityScopedResource()
        isActive = false
    }

    // MARK: - NSFilePresenter Methods

    nonisolated func presentedSubitemDidAppear(at url: URL) {
        Task {
            if await shouldMonitorFile(url: url) {
                await onEvent(.created(url))
            }
        }
    }

    nonisolated func presentedSubitemDidChange(at url: URL) {
        Task {
            if await shouldMonitorFile(url: url) {
                // Check if file still exists
                if FileManager.default.fileExists(atPath: url.path) {
                    await onEvent(.modified(url))
                } else {
                    await onEvent(.deleted(url))
                }
            }
        }
    }

    nonisolated func accommodatePresentedSubitemDeletion(at url: URL) async throws {
        if await shouldMonitorFile(url: url) {
            await onEvent(.deleted(url))
        }
    }

    private func shouldMonitorFile(url: URL) -> Bool {
        // Check if it's a file (not directory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        // Check file extension filter
        guard !options.fileExtensions.isEmpty else { return true }

        return options.fileExtensions.contains { ext in
            url.pathExtension == ext
        }
    }
}
#endif

// MARK: - iCloud Status Monitor

actor ICloudStatusMonitor {
    private let logger = Logger(label: "ICloudStatusMonitor")

    private let folderURL: URL
    private let options: FolderSyncOptions
    private let statusResolver = ICloudStatusResolver()

    @MainActor
    private var query: NSMetadataQuery?
    private var isMonitoring = false

    init(folderURL: URL, options: FolderSyncOptions) {
        self.folderURL = folderURL
        self.options = options
    }

    func start() async {
        guard !isMonitoring else { return }

        await MainActor.run {
            setupMetadataQuery()
        }

        isMonitoring = true
        logger.info("iCloud monitoring started for: \(folderURL.filePath)")
    }

    func stop() async {
        guard isMonitoring else { return }

        await MainActor.run {
            query?.stop()
            query = nil
            NotificationCenter.default.removeObserver(self)
        }

        isMonitoring = false
        logger.info("iCloud monitoring stopped for: \(folderURL.filePath)")
    }

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

        // Use ICloudStatusResolver to get actual iCloud status
        // NSMetadataQuery only tells us the file changed, not its actual status
        let status: FileStatus
        do {
            status = try await statusResolver.checkStatus(for: fileURL)
            logger.info("Resolved iCloud status for \(fileURL.lastPathComponent): \(String(describing: status))")
        } catch {
            logger.error("Failed to resolve iCloud status for \(fileURL.lastPathComponent): \(error)")
            status = .error(error.localizedDescription)
        }

        // Update status registry directly
        await FileSyncCoordinator.shared.updateFileStatus(for: fileURL, status: status)
    }

}
