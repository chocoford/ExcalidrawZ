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

/// Sync event with operation details
struct SyncEvent: Codable, Identifiable {
    let id: UUID
    let fileID: String
    let relativePath: String
    let operation: SyncOperation
    let timestamp: Date
    let retryCount: Int

    init(fileID: String, relativePath: String, operation: SyncOperation, timestamp: Date = Date(), retryCount: Int = 0) {
        self.id = UUID()
        self.fileID = fileID
        self.relativePath = relativePath
        self.operation = operation
        self.timestamp = timestamp
        self.retryCount = retryCount
    }

    /// Create a new event with incremented retry count
    func withIncrementedRetry() -> SyncEvent {
        return SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: operation,
            timestamp: timestamp,
            retryCount: retryCount + 1
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

    enum Location {
        case local
        case iCloud
    }

    /// Composite key for unique identification
    var compositeKey: String {
        return "\(fileID):\(contentType.description)"
    }
}
