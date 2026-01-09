//
//  FileStatus.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/12/31.
//

import SwiftUI
import Logging

// MARK: - FileSyncStatus

/// File synchronization status (for CoreData Files syncing between Local ↔ iCloud Drive)
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
            case .synced: return String(localizable: .fileStatusDescriptionSynced)
            case .uploading: return String(localizable: .fileStatusDescriptionUploading)
            case .downloading(let progress):
                return String(localizable: .fileStatusDescriptionDownloading(progress))
            case .needsUpload: return String(localizable: .fileStatusDescriptionNeedsUpload)
            case .needsDownload: return String(localizable: .fileStatusDescriptionNeedsDownload)
            case .queued(let op):
                switch op {
                    case .upload: return String(localizable: .fileStatusDescriptionQueuedForUpload)
                    case .download: return String(localizable: .fileStatusDescriptionQueuedForDownload)
                    case .delete: return String(localizable: .fileStatusDescriptionQueuedForDelete)
                    case .conflictResolution: return String(localizable: .fileStatusDescriptionQueuedForConflictResolution)
                }
            case .conflict: return String(localizable: .fileStatusDescriptionConflict)
            case .notAvailable: return String(localizable: .fileStatusDescriptionNotAvailable)
            case .error(let message): return String(localizable: .fileStatusDescriptionError(message))
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

// MARK: - FileStatus

/// Represents the complete status of a file (CoreData File, LocalFile, TemporaryFile, or CollaborationFile)
/// This includes content availability, iCloud status, and sync status (for CoreData files only)
struct FileStatus: Equatable {
    var contentAvailability: ContentAvailability = .available
    var syncStatus: FileSyncStatus? = nil  // nil for LocalFile/TemporaryFile, used for CoreData File sync
    var iCloudStatus: ICloudFileStatus = .local
    
    /// Content availability status
    enum ContentAvailability: Equatable {
        case available
        case missing
        case loading
    }
    
    static var `default`: FileStatus {
        FileStatus(syncStatus: .synced)  // CoreData files start as synced
    }
    
    /// Default status for LocalFile and TemporaryFile (always available, no sync, local only)
    static var localFileDefault: FileStatus {
        FileStatus(
            contentAvailability: .available,
            syncStatus: nil,  // LocalFile/TemporaryFile don't have sync status
            iCloudStatus: .local
        )
    }
}

// MARK: - FileStatusBox

/// A per-file ObservableObject that holds the current status of a file
///
/// This design ensures that when a file's status changes, only the corresponding
/// UI row is refreshed, rather than the entire file list.
@MainActor
final class FileStatusBox: ObservableObject, @MainActor Identifiable {
    private let logger = Logger(label: "FileStatusBox")
    
    /// The current status of this file
    @Published var status: FileStatus
    
    /// The file identifier this box represents
    let fileID: String
    
    var id: String { fileID }
    
    /// Timestamp of last status update
    @Published var lastUpdated: Date
    
    init(fileID: String, status: FileStatus = .default) {
        self.fileID = fileID
        self.status = status
        self.lastUpdated = Date()
    }
    
    /// Update content availability
    func updateContentAvailability(_ availability: FileStatus.ContentAvailability) {
        guard status.contentAvailability != availability else { return }
        status.contentAvailability = availability
        lastUpdated = Date()
    }
    
    /// Update sync status (for CoreData files only)
    func updateSyncStatus(_ syncStatus: FileSyncStatus?) {
        guard status.syncStatus != syncStatus else { return }
        status.syncStatus = syncStatus
        lastUpdated = Date()
    }
    
    /// Update iCloud status
    func updateICloudStatus(_ iCloudStatus: ICloudFileStatus) {
        guard status.iCloudStatus != iCloudStatus else { return }
        status.iCloudStatus = iCloudStatus
        lastUpdated = Date()
    }
}
