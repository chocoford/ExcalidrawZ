//
//  SyncModels.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/12/31.
//

import Foundation

/// Sync operation type
enum SyncOperation: Codable, CustomStringConvertible {
    case uploadToCloud      // Local → iCloud
    case downloadFromCloud  // iCloud → Local
    case deleteFromCloud    // Remove from iCloud
    case deleteFromLocal    // Remove from local

    var description: String {
        switch self {
            case .uploadToCloud: return "upload to cloud"
            case .downloadFromCloud: return "download from cloud"
            case .deleteFromCloud: return "delete from cloud"
            case .deleteFromLocal: return "delete from local"
        }
    }
}

/// Sync priority
/// - high: User-triggered operations (activeFile changes) - processed immediately
/// - normal: Background operations (DiffScan) - processed after high priority tasks
enum SyncPriority: Int, Codable, Comparable {
    case normal = 0
    case high = 1

    static func < (lhs: SyncPriority, rhs: SyncPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Sync event with operation details
struct SyncEvent: Codable, Identifiable {
    let id: UUID
    let fileID: String
    let relativePath: String
    let operation: SyncOperation
    let timestamp: Date
    let retryCount: Int
    let priority: SyncPriority

    init(
        fileID: String,
        relativePath: String,
        operation: SyncOperation,
        timestamp: Date = Date(),
        retryCount: Int = 0,
        priority: SyncPriority = .normal
    ) {
        self.id = UUID()
        self.fileID = fileID
        self.relativePath = relativePath
        self.operation = operation
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.priority = priority
    }

    /// Create a new event with incremented retry count
    func withIncrementedRetry() -> SyncEvent {
        return SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: operation,
            timestamp: timestamp,
            retryCount: retryCount + 1,
            priority: priority
        )
    }
}

/// File state for synchronization comparison
struct SyncFileState: Equatable, Hashable {
    let fileID: String
    let relativePath: String
    let contentType: FileStorageContentType
    let modifiedAt: Date
    let size: Int64
    let downloadStatus: DownloadStatus?  // macOS: iCloud download status, iOS: nil

    enum Location {
        case local
        case iCloud
    }

    /// iCloud download status (macOS only)
    enum DownloadStatus: Equatable, Hashable {
        case notDownloaded  // File not downloaded (placeholder only)
        case downloaded     // File downloaded but cloud has update
        case current        // File is up-to-date
    }

    /// Composite key for unique identification
    var compositeKey: String {
        return "\(fileID):\(contentType.description)"
    }

    init(
        fileID: String,
        relativePath: String,
        contentType: FileStorageContentType,
        modifiedAt: Date,
        size: Int64,
        downloadStatus: DownloadStatus? = nil
    ) {
        self.fileID = fileID
        self.relativePath = relativePath
        self.contentType = contentType
        self.modifiedAt = modifiedAt
        self.size = size
        self.downloadStatus = downloadStatus
    }
}
