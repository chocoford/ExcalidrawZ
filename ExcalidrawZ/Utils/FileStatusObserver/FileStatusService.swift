//
//  FileStatusService.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/31/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - SyncState

/// ObservableObject that provides reactive UI state for sync operations
/// This is observed by UI components to display sync progress
@MainActor
class SyncState: ObservableObject {
    /// Files currently syncing
    @Published var syncingFiles: [FileStatusBox] = []

    /// MediaItems batch download progress
    @Published var mediaItemsDownloadProgress: (current: Int, total: Int)?

    /// Overall sync progress (for all file types: File, MediaItem, Checkpoint, etc.)
    @Published var overallProgress: (current: Int, total: Int)?

    /// Overall sync progress message
    @Published var syncProgressMessage: String?

    /// Whether there are any active sync operations
    var hasActiveSyncOperations: Bool {
        return !syncingFiles.isEmpty ||
               mediaItemsDownloadProgress != nil ||
               overallProgress != nil ||
               syncProgressMessage != nil
    }

    /// Count of files currently syncing
    var syncingFilesCount: Int {
        return syncingFiles.count
    }

    /// Update syncing files from all status boxes
    func updateSyncingFiles(from boxes: [FileStatusBox]) {
        syncingFiles = boxes.filter { $0.status.syncStatus?.isSyncing == true }
    }
}

// MARK: - FileStatusService

/// Centralized service for managing FileStatusBox instances
///
/// This service provides a single source of truth for file statuses and ensures
/// efficient UI updates by maintaining one StatusBox per file.
///
/// Supports all file types:
/// - CoreData File (from FileStorage): Full status tracking including sync status
/// - MediaItem: Full status tracking including sync status
/// - LocalFile: iCloud status tracking via FileSyncCoordinator
/// - TemporaryFile: Fixed status (always available, no sync)
/// - CollaborationFile: Full status tracking
///
/// Global sync state:
/// - mediaItemsDownloadProgress: Batch MediaItems download progress
/// - syncProgressMessage: Overall sync message (e.g., "Syncing 5 files...")
/// - hasActiveSyncOperations: Whether any files are actively syncing
/// - syncingFilesCount: Number of files currently syncing
///
/// Usage:
/// - FileStorageManager, SyncCoordinator, and iCloudDriveFileManager call update methods
/// - FileSyncCoordinator updates iCloud status for LocalFile
/// - UI components use FileStatusProvider or observeFileStatus()
/// - UI can observe global properties (mediaItemsDownloadProgress, syncProgressMessage)
@MainActor
class FileStatusService {
    static let shared = FileStatusService()

    /// Per-file status boxes
    /// UI should observe individual FileStatusBox instances, not this dictionary
    private var statusBoxes: [String: FileStatusBox] = [:]

    /// Subscriptions to FileStatusBox changes
    /// When any box's status changes, we update syncState
    private var subscriptions: [String: AnyCancellable] = [:]

    /// Reactive sync state for UI observation
    /// UI should observe this ObservableObject for sync progress updates
    let syncState = SyncState()

    private init() {}

    /// Get or create status box for file identifier
    /// - Parameters:
    ///   - fileID: The file identifier (UUID string, URL.absoluteString, or objectID.description)
    ///   - defaultStatus: Default status for new boxes (use .localFileDefault for LocalFile/TemporaryFile)
    /// - Returns: The FileStatusBox for this file
    func statusBox(fileID: String, defaultStatus: FileStatus = .default) -> FileStatusBox {
        if let box = statusBoxes[fileID] {
            return box
        }
        let box = FileStatusBox(fileID: fileID, status: defaultStatus)
        statusBoxes[fileID] = box

        // Subscribe to box changes to update syncState
        subscriptions[fileID] = box.objectWillChange.sink { [weak self] in
            guard let self = self else { return }
            // Update syncState when any box changes
            self.syncState.updateSyncingFiles(from: Array(self.statusBoxes.values))
        }

        return box
    }
    
    /// Get or create status box for an ActiveFile
    /// - Parameter file: The active file (automatically determines default status based on file type)
    /// - Returns: The FileStatusBox for this file
    func statusBox(for file: FileState.ActiveFile) -> FileStatusBox {
        // Determine default status based on file type
        let defaultStatus: FileStatus
        switch file {
            case .localFile, .temporaryFile:
                // LocalFile and TemporaryFile always use local default (available, idle, local)
                defaultStatus = .localFileDefault
            case .file, .collaborationFile:
                // CoreData files use regular default
                defaultStatus = .default
        }
        
        return statusBox(fileID: file.id, defaultStatus: defaultStatus)
    }
    
    // MARK: - Update Methods
    
    /// Called by FileStorageManager when content is missing
    /// - Parameters:
    ///   - fileID: The file identifier
    ///   - failureCount: Number of consecutive failures
    @MainActor
    func markMissing(fileID: String, failureCount: Int) {
        let box = statusBox(fileID: fileID)
        box.updateContentAvailability(.missing)
    }
    
    /// Called by FileStorageManager when content is available
    /// - Parameter fileID: The file identifier
    func markAvailable(fileID: String) {
        let box = statusBox(fileID: fileID)
        box.updateContentAvailability(.available)
    }
    
    /// Called by FileStorageManager when content is loading
    /// - Parameter fileID: The file identifier
    func markLoading(fileID: String) {
        let box = statusBox(fileID: fileID)
        box.updateContentAvailability(.loading)
    }
    
    /// Called by FileSyncCoordinator or iCloudDriveFileManager when iCloud status changes
    /// - Parameters:
    ///   - fileID: The file identifier
    ///   - status: The new iCloud status
    func updateICloudStatus(fileID: String, status: ICloudFileStatus) {
        let box = statusBox(fileID: fileID)
        box.updateICloudStatus(status)
    }
    
    // MARK: - Sync Status Management (for CoreData Files)
    
    /// Mark file as actively syncing (called by SyncCoordinator)
    /// - Parameters:
    ///   - fileID: The file identifier
    ///   - operation: The sync operation being performed
    func markSyncInProgress(fileID: String, operation: FileSyncStatus.QueuedOperation) {
        let box = statusBox(fileID: fileID)
        
        let status: FileSyncStatus
        switch operation {
            case .upload:
                status = .uploading
            case .download:
                status = .downloading(progress: 0.0)
            case .delete, .conflictResolution:
                status = .queued(operation: operation)
        }
        
        box.updateSyncStatus(status)
    }
    
    /// Mark file sync as completed (called by SyncCoordinator)
    /// - Parameter fileID: The file identifier
    func markSyncCompleted(fileID: String) {
        let box = statusBox(fileID: fileID)
        box.updateSyncStatus(.synced)
    }
    
    /// Mark file sync as failed (called by SyncCoordinator)
    /// - Parameters:
    ///   - fileID: The file identifier
    ///   - error: Error message
    func markSyncFailed(fileID: String, error: String) {
        let box = statusBox(fileID: fileID)
        box.updateSyncStatus(.error(error))
    }
    
    /// Mark file as queued for sync (called by SyncCoordinator)
    /// - Parameters:
    ///   - fileID: The file identifier
    ///   - operation: The queued operation
    func markSyncQueued(fileID: String, operation: FileSyncStatus.QueuedOperation) {
        let box = statusBox(fileID: fileID)
        box.updateSyncStatus(.queued(operation: operation))
    }
    
    /// Update sync download progress (called by SyncCoordinator)
    /// - Parameters:
    ///   - fileID: The file identifier
    ///   - progress: Download progress from 0.0 to 1.0
    func updateSyncDownloadProgress(fileID: String, progress: Double) {
        let box = statusBox(fileID: fileID)
        let clampedProgress = min(max(progress, 0.0), 1.0)
        box.updateSyncStatus(.downloading(progress: clampedProgress))
        
        // Auto-complete when done
        if clampedProgress >= 1.0 {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await MainActor.run {
                    self.markSyncCompleted(fileID: fileID)
                }
            }
        }
    }
    
    /// Clear all status for a file (when deleted)
    /// - Parameter fileID: The file identifier
    func clearStatus(fileID: String) {
        statusBoxes.removeValue(forKey: fileID)
        subscriptions.removeValue(forKey: fileID)
        // Update syncState after removing
        syncState.updateSyncingFiles(from: Array(statusBoxes.values))
    }
    
    // MARK: - Global Sync State Management
    
    /// Update MediaItems download progress
    /// - Parameters:
    ///   - current: Current number of downloaded items
    ///   - total: Total number of items to download
    func updateMediaItemsProgress(current: Int, total: Int) {
        syncState.mediaItemsDownloadProgress = (current, total)
        if current >= total {
            // Clear progress after a delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    if let progress = self.syncState.mediaItemsDownloadProgress,
                       progress.current >= progress.total {
                        self.syncState.mediaItemsDownloadProgress = nil
                    }
                }
            }
        }
    }

    /// Clear MediaItems progress
    func clearMediaItemsProgress() {
        syncState.mediaItemsDownloadProgress = nil
    }

    /// Update overall sync progress message
    /// - Parameter message: Progress message (nil to clear)
    func updateSyncProgressMessage(_ message: String?) {
        syncState.syncProgressMessage = message
    }

    /// Update overall sync progress
    /// - Parameters:
    ///   - current: Current number of synced files
    ///   - total: Total number of files to sync
    func updateOverallProgress(current: Int, total: Int) {
        syncState.overallProgress = (current, total)
        if current >= total {
            // Clear progress after a delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    if let progress = self.syncState.overallProgress,
                       progress.current >= progress.total {
                        self.syncState.overallProgress = nil
                    }
                }
            }
        }
    }

    /// Clear overall sync progress
    func clearOverallProgress() {
        syncState.overallProgress = nil
    }

    // MARK: - Computed Properties

    /// Whether there are any active sync operations (convenience accessor)
    var hasActiveSyncOperations: Bool {
        return syncState.hasActiveSyncOperations
    }

    /// Count of files currently syncing (convenience accessor)
    var syncingFilesCount: Int {
        return syncState.syncingFilesCount
    }
    
    /// Get current sync status for a file
    /// - Parameter fileID: The file identifier
    /// - Returns: The sync status, or .synced if not found
    func getSyncStatus(for fileID: String) -> FileSyncStatus {
        return statusBoxes[fileID]?.status.syncStatus ?? .synced
    }
}
