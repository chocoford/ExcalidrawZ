//
//  SyncStatusState.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/28.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Sync Status Types

/// File synchronization status
enum FileSyncStatus: Equatable, CustomStringConvertible {
    case synced                    // File is in sync with iCloud
    case uploading                 // Currently uploading to iCloud
    case downloading(progress: Double)  // Currently downloading from iCloud (0.0-1.0)
    case needsUpload              // Local changes pending upload
    case needsDownload            // iCloud has newer version
    case queued(operation: QueuedOperation)  // Queued for sync operation
    case conflict                  // Conflict between local and iCloud
    case notAvailable             // iCloud not available
    case error(String)            // Sync error occurred

    enum QueuedOperation: Equatable {
        case upload
        case download
        case delete
        case conflictResolution
    }

    var description: String {
        switch self {
        case .synced: return "Synced"
        case .uploading: return "Uploading..."
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .needsUpload: return "Needs Upload"
        case .needsDownload: return "Needs Download"
        case .queued(let op):
            switch op {
            case .upload: return "Queued for Upload"
            case .download: return "Queued for Download"
            case .delete: return "Queued for Deletion"
            case .conflictResolution: return "Conflict Resolution Queued"
            }
        case .conflict: return "Conflict"
        case .notAvailable: return "Not Available"
        case .error(let message): return "Error: \(message)"
        }
    }

    /// Whether the file is currently syncing
    var isSyncing: Bool {
        switch self {
        case .uploading, .downloading:
            return true
        default:
            return false
        }
    }

    /// Get download progress if downloading
    var downloadProgress: Double? {
        if case .downloading(let progress) = self {
            return progress
        }
        return nil
    }

    /// Whether the file needs user attention
    var needsAttention: Bool {
        switch self {
        case .conflict, .error:
            return true
        default:
            return false
        }
    }
}

// MARK: - File Sync Info

/// Complete sync information for a file
struct FileSyncInfo: Equatable {
    let fileID: String
    let relativePath: String
    let status: FileSyncStatus
    let lastSyncedAt: Date?
    let queuePosition: Int?  // Position in sync queue, nil if not queued

    init(fileID: String, relativePath: String, status: FileSyncStatus, lastSyncedAt: Date? = nil, queuePosition: Int? = nil) {
        self.fileID = fileID
        self.relativePath = relativePath
        self.status = status
        self.lastSyncedAt = lastSyncedAt
        self.queuePosition = queuePosition
    }
}

// MARK: - Sync Status State

/// Observable state for tracking file synchronization status
/// Use this in SwiftUI views to display sync status for each file
/// This is for iCloud files...
///
/// Usage in SwiftUI:
/// ```swift
/// @ObservedObject var syncStatus = SyncStatusState.shared
/// let status = syncStatus.getStatus(for: fileID)
/// ```
@MainActor
class SyncStatusState: ObservableObject {
    /// Shared instance
    static let shared = SyncStatusState()

    /// File sync statuses (fileID -> status)
    @Published private(set) var fileStatuses: [String: FileSyncStatus] = [:]

    /// Files currently being synced
    private var activeOperations: Set<String> = []

    /// MediaItems download progress
    @Published private(set) var mediaItemsDownloadProgress: (current: Int, total: Int)?

    /// Overall sync progress message
    @Published private(set) var syncProgressMessage: String?

    private init() {}

    // MARK: - Status Access

    /// Get current status for a file
    func getStatus(for fileID: String) -> FileSyncStatus {
        return fileStatuses[fileID] ?? .synced
    }

    /// Get all files with pending sync operations
    func getPendingFiles() -> [(fileID: String, status: FileSyncStatus)] {
        return fileStatuses.compactMap { (fileID, status) in
            if status.isSyncing || status.needsAttention {
                return (fileID, status)
            }
            return nil
        }
    }

    // MARK: - Status Updates

    /// Update status for a file
    func updateStatus(fileID: String, status: FileSyncStatus) {
        fileStatuses[fileID] = status
    }

    /// Mark file as actively syncing
    func markSyncing(fileID: String, operation: FileSyncStatus.QueuedOperation) {
        activeOperations.insert(fileID)

        let status: FileSyncStatus
        switch operation {
        case .upload:
            status = .uploading
        case .download:
            status = .downloading(progress: 0.0)
        case .delete, .conflictResolution:
            status = .queued(operation: operation)
        }

        updateStatus(fileID: fileID, status: status)
    }

    /// Mark file sync as completed
    func markCompleted(fileID: String) {
        activeOperations.remove(fileID)
        updateStatus(fileID: fileID, status: .synced)
    }

    /// Mark file sync as failed
    func markFailed(fileID: String, error: String) {
        activeOperations.remove(fileID)
        updateStatus(fileID: fileID, status: .error(error))
    }

    /// Mark file as queued for sync
    func markQueued(fileID: String, operation: FileSyncStatus.QueuedOperation) {
        updateStatus(fileID: fileID, status: .queued(operation: operation))
    }

    /// Clear status for a file (when deleted)
    func clearStatus(fileID: String) {
        fileStatuses.removeValue(forKey: fileID)
        activeOperations.remove(fileID)
    }

    // MARK: - Media Items Progress

    /// Update MediaItems download progress
    func updateMediaItemsProgress(current: Int, total: Int) {
        mediaItemsDownloadProgress = (current, total)
        if current >= total {
            // Clear progress after a delay
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    if let progress = self.mediaItemsDownloadProgress,
                       progress.current >= progress.total {
                        self.mediaItemsDownloadProgress = nil
                    }
                }
            }
        }
    }

    /// Clear MediaItems progress
    func clearMediaItemsProgress() {
        mediaItemsDownloadProgress = nil
    }

    /// Update overall sync progress message
    func updateSyncProgressMessage(_ message: String?) {
        syncProgressMessage = message
    }

    // MARK: - Computed Properties

    /// Whether there are any active sync operations
    var hasActiveSyncOperations: Bool {
        return !activeOperations.isEmpty ||
               mediaItemsDownloadProgress != nil ||
               syncProgressMessage != nil
    }

    /// Count of files currently syncing
    var syncingFilesCount: Int {
        return activeOperations.count
    }

    // MARK: - File Download Progress

    /// Update download progress for a specific file
    /// - Parameters:
    ///   - fileID: The file identifier
    ///   - progress: Download progress from 0.0 to 1.0
    func updateDownloadProgress(fileID: String, progress: Double) {
        let clampedProgress = min(max(progress, 0.0), 1.0)
        updateStatus(fileID: fileID, status: .downloading(progress: clampedProgress))

        // Auto-complete when done
        if clampedProgress >= 1.0 {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await MainActor.run {
                    self.markCompleted(fileID: fileID)
                }
            }
        }
    }

    /// Get download progress for a specific file
    /// - Parameter fileID: The file identifier
    /// - Returns: Download progress from 0.0 to 1.0, or nil if not downloading
    func getDownloadProgress(for fileID: String) -> Double? {
        return fileStatuses[fileID]?.downloadProgress
    }
}
