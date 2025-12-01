//
//  FileStorageTypes.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/27.
//

import Foundation

// MARK: - Shared Types

/// Content type for file storage (shared between local and iCloud)
enum FileStorageContentType: Hashable, Equatable, CustomStringConvertible {
    case file
    case collaborationFile
    case checkpoint
    case mediaItem(extension: String)

    var fileExtension: String {
        switch self {
            case .file: return "excalidrawz"
            case .collaborationFile: return "excalidrawz_collab"
            case .checkpoint: return "excalidrawz_checkpoint"
            case .mediaItem(let ext): return ext
        }
    }

    var description: String {
        switch self {
            case .file: "file"
            case .collaborationFile: "collaborationFile"
            case .checkpoint: "checkpoint"
            case .mediaItem: "mediaItem"
        }
    }
}

/// File metadata structure
struct FileMetadata {
    let size: Int64
    let modifiedAt: Date
}
