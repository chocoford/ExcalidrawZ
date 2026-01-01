//
//  FileStorageManager.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/26.
//

import Foundation
import Logging
import Combine

// MARK: - Errors

enum FileStorageError: LocalizedError {
    case storageUnavailable
    case fileNotFound(String)
    case readFailed(String)
    case writeFailed(String)
    case deleteFailed(String)
    case fileTemporarilyUnavailable(String)

    var errorDescription: String? {
        switch self {
            case .storageUnavailable:
                return "Local storage is not available"
            case .fileNotFound(let path):
                return "File not found at path: \(path)"
            case .readFailed(let reason):
                return "Failed to read file: \(reason)"
            case .writeFailed(let reason):
                return "Failed to write file: \(reason)"
            case .deleteFailed(let reason):
                return "Failed to delete file: \(reason)"
            case .fileTemporarilyUnavailable(let reason):
                return reason
        }
    }
}

/// File change event for sync notifications
struct FileChangeEvent {
    enum ChangeType {
        case created
        case modified
        case deleted
    }

    let fileID: UUID
    let relativePath: String
    let changeType: ChangeType
    let timestamp: Date
}

// MARK: - Failure Tracker

/// Tracks load failures to avoid excessive retry attempts
private actor FailureTracker {
    private var failures: [String: FailureRecord] = [:]
    private let logger = Logger(label: "FailureTracker")

    struct FailureRecord {
        var count: Int
        var lastAttempt: Date
        var firstFailure: Date
    }

    /// Record a load failure for a file
    /// - Returns: The total failure count for this file
    func recordFailure(for fileID: String) -> Int {
        if var record = failures[fileID] {
            record.count += 1
            record.lastAttempt = Date()
            failures[fileID] = record
        } else {
            failures[fileID] = FailureRecord(
                count: 1,
                lastAttempt: Date(),
                firstFailure: Date()
            )
        }

        let record = failures[fileID]!
        logger.warning("File load failed [\(record.count)x]: \(fileID)")
        return record.count
    }

    /// Check if file is marked as missing (3+ failures)
    /// User can always attempt to load, but UI can use this to show warning
    func isMissing(fileID: String) -> Bool {
        guard let record = failures[fileID] else {
            return false
        }
        return record.count >= 3
    }

    /// Reset failure record for a file (called after successful load)
    func reset(fileID: String) {
        if failures.removeValue(forKey: fileID) != nil {
            logger.info("Reset failure record for: \(fileID)")
        }
    }
}

/// Unified file storage manager (Coordinator Layer)
/// Coordinates between LocalStorageManager, iCloudDriveFileManager, and SyncCoordinator
/// External code should only interact with this manager
actor FileStorageManager {
    static let shared = FileStorageManager()

    private let logger = Logger(label: "FileStorageManager")

    // Managed components
    private let localManager: LocalStorageManager
    private let iCloudManager: iCloudDriveFileManager

    // SyncCoordinator is initialized after migration completes
    private var syncCoordinator: SyncCoordinator?

    // Failure tracking for missing files
    private let failureTracker = FailureTracker()

    // MARK: - Type Aliases for external use

    typealias StorageDirectory = LocalStorageManager.StorageDirectory
    typealias ContentType = FileStorageContentType

    // MARK: - Initialization

    private init() {
        self.localManager = LocalStorageManager()
        self.iCloudManager = iCloudDriveFileManager()
        // SyncCoordinator will be initialized after migration via enableSync()
    }

    // MARK: - Sync Control

    /// Enable sync after migration completes
    /// Should be called by StartupSyncModifier when migration phase becomes .closed
    func enableSync() {
        guard syncCoordinator == nil else {
            logger.warning("Sync already enabled, ignoring duplicate enableSync() call")
            return
        }
        logger.info("Initializing SyncCoordinator...")
        syncCoordinator = SyncCoordinator(
            localManager: localManager,
            iCloudManager: iCloudManager
        )
        logger.info("FileStorage sync enabled")
    }

    // MARK: - Core Storage Operations (Public API)
    
    /// Save content to storage (local + iCloud sync)
    /// - Parameters:
    ///   - content: The content data to save
    ///   - fileID: The file identifier (String, typically UUID)
    ///   - type: The content type
    ///   - updatedAt: Optional update timestamp
    /// - Returns: The relative path to the stored file
    func saveContent(
        _ content: Data,
        fileID: String,
        type: ContentType,
        updatedAt: Date? = nil
    ) async throws -> String {
        // Step 1: Save to local storage (always succeeds or throws)
        let saveResult = try await localManager.saveContent(
            content,
            fileID: fileID,
            type: type,
            updatedAt: updatedAt
        )

        // Step 2: Queue for iCloud sync only if content was actually modified
        if saveResult.wasModified {
            Task {
                await syncCoordinator?.queueUpload(fileID: fileID, relativePath: saveResult.relativePath)
            }
        } else {
            logger.debug("Content unchanged, skipping iCloud sync queue for: \(fileID)")
        }

        return saveResult.relativePath
    }
    
    /// Load content from storage with bidirectional sync
    /// Checks iCloud for newer version before returning local content
    /// - Parameters:
    ///   - relativePath: The relative path to the file
    ///   - fileID: The file identifier (String, typically UUID) for sync checking
    /// - Returns: The content data
    func loadContent(relativePath: String, fileID: String) async throws -> Data {
        do {
            // Use SyncCoordinator to load with version checking (if sync enabled)
            let data: Data
            if let syncCoordinator = syncCoordinator {
                data = try await syncCoordinator.loadContentWithSync(relativePath: relativePath, fileID: fileID)
            } else {
                // Migration not complete, load from local only
                data = try await localManager.loadContent(relativePath: relativePath)
            }

            // Success - reset failure record and update status
            await failureTracker.reset(fileID: fileID)
            Task { @MainActor in
                FileStatusService.shared.markAvailable(fileID: fileID)
            }
            return data

        } catch {
            // Record failure for file not found errors (passive tracking)
            if case FileStorageError.fileNotFound = error {
                let failureCount = await failureTracker.recordFailure(for: fileID)
                Task { @MainActor in
                    FileStatusService.shared.markMissing(fileID: fileID, failureCount: failureCount)
                }
            }
            throw error
        }
    }

    /// Load content from storage (legacy method without fileID)
    /// Does not perform iCloud version checking
    /// - Parameter relativePath: The relative path to the file
    /// - Returns: The content data
    func loadContent(relativePath: String) async throws -> Data {
        // Load from local storage only
        return try await localManager.loadContent(relativePath: relativePath)
    }
    
    /// Delete content from storage (local + iCloud)
    /// - Parameters:
    ///   - relativePath: The relative path to the file
    ///   - fileID: The file identifier (String, typically UUID)
    func deleteContent(relativePath: String, fileID: String) async throws {
        // Step 1: Delete from local storage
        try await localManager.deleteContent(relativePath: relativePath)

        // Step 2: Queue iCloud deletion (auto-processes after debounce)
        Task {
            await syncCoordinator?.queueCloudDelete(fileID: fileID, relativePath: relativePath)
        }
    }
    
    /// Check if file exists in storage
    /// - Parameter relativePath: The relative path to check
    /// - Returns: True if file exists
    func fileExists(relativePath: String) async -> Bool {
        return await localManager.fileExists(relativePath: relativePath)
    }
    
    /// Get file metadata
    /// - Parameter relativePath: The relative path to the file
    /// - Returns: File metadata (size and modification date)
    func getFileMetadata(relativePath: String) async throws -> FileMetadata {
        return try await localManager.getFileMetadata(relativePath: relativePath)
    }
    
    // MARK: - Media Item Operations (Public API)
    
    /// Save media item from data URL
    /// - Parameters:
    ///   - dataURL: The base64 data URL
    ///   - mediaID: The media item ID
    ///   - updatedAt: Optional update timestamp
    /// - Returns: The relative path to the stored file
    func saveMediaItem(
        dataURL: String,
        mediaID: String,
        updatedAt: Date? = nil
    ) async throws -> String {
        // Step 1: Save to local storage
        let relativePath = try await localManager.saveMediaItem(
            dataURL: dataURL,
            mediaID: mediaID,
            updatedAt: updatedAt
        )

        // Step 2: Queue for iCloud sync (auto-processes after debounce)
        let syncEvent = SyncEvent(
            fileID: mediaID,
            relativePath: relativePath,
            operation: .uploadToCloud,
            timestamp: Date()
        )
        Task {
            await syncCoordinator?.enqueue(syncEvent)
        }

        return relativePath
    }
    
    /// Load media item and convert to data URL
    /// - Parameter relativePath: The relative path to the media file
    /// - Returns: The data URL string
    func loadMediaItem(relativePath: String) async throws -> String {
        return try await localManager.loadMediaItem(relativePath: relativePath)
    }
    
    // MARK: - Storage Statistics (Public API)
    
    /// Get total storage size
    /// - Returns: Total size in bytes
    func getTotalStorageSize() async throws -> Int64 {
        return try await localManager.getTotalStorageSize()
    }
    
    // MARK: - iCloud Status (Public API)

    /// Get current iCloud availability status
    func getCurrentICloudStatus() async -> ICloudAvailabilityStatus {
        return await iCloudManager.getCurrentStatus()
    }

    /// Get number of pending sync operations
    func getPendingSyncCount() async -> Int {
        guard let syncCoordinator = syncCoordinator else { return 0 }
        return await syncCoordinator.getQueueCount()
    }

    // MARK: - Sync Management (Public API)

    /// Trigger DiffScan to synchronize local and iCloud storage
    /// Should be called after migration completes
    func performStartupSync() async throws {
        guard let syncCoordinator = syncCoordinator else {
            logger.warning("performStartupSync called before sync enabled, ignoring")
            return
        }
        logger.info("Starting startup sync...")
        try await syncCoordinator.performDiffScan()
        logger.info("Startup sync completed")
    }

    /// Manually trigger sync queue processing
    func processPendingSync() async {
        await syncCoordinator?.processQueue()
    }

    // MARK: - File Status Query (Public API)

    /// Check if a file is marked as missing (3+ load failures)
    /// UI can use this to display warning icons
    /// - Parameter fileID: The file identifier to check
    /// - Returns: True if file has failed to load 3 or more times
    func isFileMissing(fileID: String) async -> Bool {
        return await failureTracker.isMissing(fileID: fileID)
    }

    /// Attempt to recover a missing file by re-syncing from iCloud
    /// - Parameters:
    ///   - fileID: The file identifier to recover
    ///   - contentType: The content type (defaults to .file)
    /// - Throws: FileStorageError if recovery fails
    func attemptRecovery(fileID: String, contentType: ContentType = .file) async throws {
        logger.info("Attempting to recover file: \(fileID)")

        // Update UI status to loading
        Task { @MainActor in
            FileStatusService.shared.markLoading(fileID: fileID)
        }

        // Generate relativePath internally using contentType's utility method
        let relativePath = contentType.generateRelativePath(fileID: fileID)

        // Try to load content with iCloud sync check
        // If successful, loadContent() will automatically reset failure tracking and mark as available
        // If failed, it will throw an error and UI can show alert
        _ = try await loadContent(relativePath: relativePath, fileID: fileID)
        logger.info("Successfully recovered file: \(fileID)")
    }

    // MARK: - iCloud Update Check (Public API)

    /// Check if iCloud has a newer version without downloading
    /// - Parameters:
    ///   - relativePath: The relative path to the file
    ///   - fileID: The file identifier
    /// - Returns: True if iCloud has a newer version
    func checkForICloudUpdate(relativePath: String, fileID: String) async throws -> Bool {
        guard let syncCoordinator = syncCoordinator else {
            logger.warning("checkForICloudUpdate called before sync enabled, returning false")
            return false
        }
        return try await syncCoordinator.checkForICloudUpdate(relativePath: relativePath)
    }
}
