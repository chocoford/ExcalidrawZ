//
//  FileSyncCoordinator.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/23/25.
//

import Foundation
import Logging

/// System-level coordinator for file synchronization and status monitoring.
///
/// This actor manages:
/// - Folder monitoring (file system events)
/// - iCloud status tracking (per-file via FileStatusService)
/// - Safe file access coordination
///
/// Usage:
/// ```swift
/// // Register a folder for monitoring
/// try await FileSyncCoordinator.shared.addFolder(at: folderURL, options: .default)
///
/// // Get status from FileStatusService
/// let statusBox = FileStatusService.shared.getOrCreateBox(
///     fileID: fileURL.absoluteString,
///     defaultStatus: .localFileDefault
/// )
/// ```
actor FileSyncCoordinator {
    // MARK: - Singleton

    static let shared = FileSyncCoordinator()

    // MARK: - Properties

    private let logger = Logger(label: "FileSyncCoordinator")

    /// Active folder monitors (keyed by folder URL)
    private var folderMonitors: [URL: FolderMonitor] = [:]

    /// File coordinator for safe file operations
    private let fileCoordinator = FileCoordinator.shared

    /// AsyncStream continuation for file change events
    private var eventContinuation: AsyncStream<FSChangeEvent>.Continuation?

    // MARK: - Initialization

    private init() {
        logger.info("FileSyncCoordinator initialized")
    }
    
    // MARK: - Folder Management
    
    /// Register a folder for monitoring
    /// - Parameters:
    ///   - url: The folder URL to monitor
    ///   - options: Configuration options
    /// - Throws: FolderError if folder is invalid or inaccessible
    func addFolder(at url: URL, options: FolderSyncOptions) async throws {
        // Validate URL
        guard url.isFileURL else {
            throw FolderError.invalidFolder
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.filePath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FolderError.folderNotFound
        }
        
        // Check if already monitoring
        guard folderMonitors[url] == nil else {
            logger.warning("Folder already being monitored: \(url.filePath)")
            throw FolderError.alreadyMonitoring
        }
        
        // Create and start monitor
        let monitor = FolderMonitor(
            folderURL: url,
            options: options,
            onFileEvent: { [weak self] event in
                await self?.handleFileEvent(event)
            }
        )
        
        folderMonitors[url] = monitor
        try await monitor.start()
        
        logger.info("Successfully started monitoring folder: \(url.filePath)")
    }
    
    /// Remove a folder from monitoring
    /// - Parameter url: The folder URL to stop monitoring
    func removeFolder(at url: URL) async {
        guard let monitor = folderMonitors[url] else {
            logger.warning("Attempted to remove folder that wasn't being monitored: \(url.lastPathComponent)")
            return
        }

        logger.info("Removing folder from monitoring: \(url.lastPathComponent)")

        await monitor.stop()
        folderMonitors.removeValue(forKey: url)

        logger.info("Successfully stopped monitoring folder: \(url.lastPathComponent)")
    }
    
    /// Remove all folders from monitoring
    func removeAllFolders() async {
        logger.info("Removing all folders from monitoring")

        for (_, monitor) in folderMonitors {
            await monitor.stop()
        }

        folderMonitors.removeAll()

        logger.info("All folders removed from monitoring")
    }
    
    // MARK: - File Status Update

    /// Update file status directly (called by ICloudStatusMonitor)
    /// - Parameters:
    ///   - fileURL: The file URL
    ///   - status: The new status
    func updateFileStatus(for fileURL: URL, status: ICloudFileStatus) async {
        await MainActor.run {
            FileStatusService.shared.updateICloudStatus(
                fileID: fileURL.absoluteString,
                status: status
            )
        }

        // Emit status change event
        eventContinuation?.yield(.statusChanged(url: fileURL, status: status))
    }

#if os(iOS)
    /// Set monitoring level for an iCloud file (iOS only)
    ///
    /// This method allows UI to control polling frequency for iCloud files:
    /// - Set to `.active` when user opens/edits a file
    /// - Set to `.visible` when file is shown in a list
    /// - Set to `.background` when file is no longer visible
    ///
    /// - Parameters:
    ///   - fileURL: The file URL to monitor
    ///   - level: The monitoring level
    func setFileMonitoringLevel(_ fileURL: URL, level: FileMonitoringLevel) async {
        await setFilesMonitoringLevel([fileURL], level: level)
    }
    
    func setFilesMonitoringLevel(_ filesURL: [URL], level: FileMonitoringLevel) async {
        var monitors: [URL: (FolderMonitor, [URL])] = [:]
        for fileURL in filesURL {
            // Find the folder monitor for this file
            let folderURL = fileURL.deletingLastPathComponent()
            if monitors[folderURL] != nil {
                monitors[folderURL]?.1.append(fileURL)
                continue
            }
            
            guard let monitor = folderMonitors.first(where: {folderURL.filePath.hasPrefix($0.key.filePath)})?.value else {
                logger.warning("No folder monitor found for: \(folderURL.filePath)")
                continue
            }
            monitors[folderURL] = (monitor, [fileURL])
        }

        for (monitor, filesURL) in monitors.values {
            await monitor.setFilesMonitoringLevel(filesURL, level: level)
        }
    }
#endif

    // MARK: - File Change Events

    /// Subscribe to file change events
    ///
    /// Usage:
    /// ```swift
    /// Task {
    ///     for await event in await FileSyncCoordinator.shared.fileChangesStream {
    ///         switch event {
    ///             case .created(let url):
    ///                 print("File created: \(url)")
    ///             case .statusChanged(let url, let status):
    ///                 print("Status changed: \(url) - \(status)")
    ///             // ...
    ///         }
    ///     }
    /// }
    /// ```
    /// - Returns: AsyncStream of FSChangeEvent
    var fileChangesStream: AsyncStream<FSChangeEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { [weak self] in
                    await self?.clearEventContinuation()
                }
            }
        }
    }

    private func clearEventContinuation() {
        eventContinuation = nil
    }

    // MARK: - File Operations

    /// Open a file safely, downloading if necessary
    /// - Parameter url: The file URL to open
    /// - Returns: File data
    /// - Throws: FileCoordinatorError if unable to open file
    func openFile(_ url: URL) async throws -> Data {
        return try await fileCoordinator.coordinatedRead(url: url) { coordinatedURL in
            try Data(contentsOf: coordinatedURL)
        }
    }

    /// Save data to a file safely
    /// - Parameters:
    ///   - url: The file URL to save to
    ///   - data: The data to write
    /// - Throws: FileCoordinatorError if unable to save file
    func saveFile(at url: URL, data: Data) async throws {
        try await fileCoordinator.coordinatedWrite(url: url, data: data)
    }

    /// Download an iCloud file
    /// - Parameter url: The file URL to download
    /// - Throws: FileCoordinatorError if unable to download
    func downloadFile(_ url: URL) async throws {
        try await fileCoordinator.downloadFile(url: url)
    }

    /// Delete a file safely
    /// - Parameter url: The file URL to delete
    /// - Throws: FileCoordinatorError if unable to delete
    func deleteFile(_ url: URL) async throws {
        try await fileCoordinator.deleteFile(url: url)
    }

    // MARK: - File Event Handling

    /// Handle file system events
    ///
    /// Note: For iCloud files, ICloudStatusMonitor will handle status updates.
    private func handleFileEvent(_ event: FileEvent) async {
        switch event {
            case .created(let url):
                logger.debug("File created: \(url.lastPathComponent)")
                eventContinuation?.yield(.created(url))

            case .modified(let url):
                logger.debug("File modified: \(url.lastPathComponent)")
                eventContinuation?.yield(.modified(url))

            case .deleted(let url):
                logger.debug("File deleted: \(url.lastPathComponent)")
                eventContinuation?.yield(.deleted(url))

            case .renamed(let oldURL, let newURL):
                logger.debug("File renamed: \(oldURL.lastPathComponent) -> \(newURL.lastPathComponent)")
                eventContinuation?.yield(.renamed(old: oldURL, new: newURL))
        }
    }
}

// MARK: - File Events

enum FileEvent {
    case created(URL)
    case modified(URL)
    case deleted(URL)
    case renamed(old: URL, new: URL)
}

/// File system change events emitted by FileSyncCoordinator
///
/// Subscribe to these events to be notified of file system changes and iCloud status updates.
enum FSChangeEvent: Sendable {
    /// File was created
    case created(URL)

    /// File content was modified
    case modified(URL)

    /// File was deleted
    case deleted(URL)

    /// File was renamed
    case renamed(old: URL, new: URL)

    /// File iCloud status changed (downloading, downloaded, uploading, etc.)
    case statusChanged(url: URL, status: ICloudFileStatus)
}

// MARK: - Folder Errors

enum FolderError: LocalizedError {
    case permissionDenied
    case folderNotFound
    case invalidFolder
    case alreadyMonitoring

    var errorDescription: String? {
        switch self {
            case .permissionDenied:
                return String(localizable: .folderErrorDescriptionPermissionDenied)
            case .folderNotFound:
                return String(localizable: .folderErrorDescriptionNotFound)
            case .invalidFolder:
                return String(localizable: .folderErrorDescriptionInvalid)
            case .alreadyMonitoring:
                return String(localizable: .folderErrorDescriptionAlreadyMonitoring)
        }
    }
}

// MARK: - File Monitoring Level

/// Monitoring level for iCloud files (iOS only)
enum FileMonitoringLevel: Sendable {
    case active
    case visible
    case background
    case never

    /// Polling interval in seconds
    var pollingInterval: TimeInterval {
        switch self {
            case .active: return 3
            case .visible: return 15.0
            case .background: return 45.0
            case .never: return Double.greatestFiniteMagnitude
        }
    }
}
