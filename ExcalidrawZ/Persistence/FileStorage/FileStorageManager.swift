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

/// Unified file storage manager (Coordinator Layer)
/// Coordinates between LocalStorageManager, iCloudDriveFileManager, and SyncCoordinator
/// External code should only interact with this manager
actor FileStorageManager {
    static let shared = FileStorageManager()

    private let logger = Logger(label: "FileStorageManager")

    // Managed components
    private let localManager: LocalStorageManager
    private let iCloudManager: iCloudDriveFileManager
    private let syncCoordinator: SyncCoordinator

    // MARK: - Type Aliases for external use

    typealias StorageDirectory = LocalStorageManager.StorageDirectory
    typealias ContentType = FileStorageContentType

    // MARK: - Initialization

    private init() {
        self.localManager = LocalStorageManager()
        self.iCloudManager = iCloudDriveFileManager()
        self.syncCoordinator = SyncCoordinator(
            localManager: self.localManager,
            iCloudManager: self.iCloudManager
        )
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
                await syncCoordinator.queueUpload(fileID: fileID, relativePath: saveResult.relativePath)
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
        // Use SyncCoordinator to load with version checking
        return try await syncCoordinator.loadContentWithSync(relativePath: relativePath, fileID: fileID)
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
            await syncCoordinator.queueCloudDelete(fileID: fileID, relativePath: relativePath)
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
            await syncCoordinator.enqueue(syncEvent)
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
        return await syncCoordinator.getQueueCount()
    }

    // MARK: - Sync Management (Public API)

    /// Trigger DiffScan to synchronize local and iCloud storage
    /// Should be called on app startup
    func performStartupSync() async throws {
        logger.info("Starting startup sync...")
        try await syncCoordinator.performDiffScan()
        logger.info("Startup sync completed")
    }

    /// Manually trigger sync queue processing
    func processPendingSync() async {
        await syncCoordinator.processQueue()
    }
}
