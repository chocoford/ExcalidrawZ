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

// MARK: - FileStorageContentType Utilities

extension FileStorageContentType {
    /// Generate relative path for a file
    /// - Parameter fileID: The file identifier
    /// - Returns: The relative path (e.g., "Files/uuid.excalidrawz")
    func generateRelativePath(fileID: String) -> String {
        let directory: String
        let filename: String
        
        switch self {
            case .file:
                directory = "Files"
                filename = "\(fileID).excalidrawz"
            case .collaborationFile:
                directory = "CollaborationFiles"
                filename = "\(fileID).excalidrawz_collab"
            case .checkpoint:
                directory = "Checkpoints"
                filename = "\(fileID).excalidrawz_checkpoint"
            case .mediaItem(let ext):
                directory = "MediaItems"
                filename = "\(fileID).\(ext)"
        }
        
        return "\(directory)/\(filename)"
    }
    
    /// Determine content type from relative path
    /// - Parameter relativePath: The relative path (e.g., "Files/uuid.excalidrawz")
    /// - Returns: The content type, or nil if unknown
    static func from(relativePath: String) -> FileStorageContentType? {
        let fileExtension = (relativePath as NSString).pathExtension
        
        switch fileExtension {
            case "excalidrawz":
                return .file
            case "excalidrawz_collab":
                return .collaborationFile
            case "excalidrawz_checkpoint":
                return .checkpoint
            case "png", "jpg", "jpeg", "gif", "svg", "webp", "pdf", "dat":
                // Media items can have various image extensions or .dat
                return .mediaItem(extension: fileExtension)
            default:
                // Unknown file type
                return nil
        }
    }
    
    /// Get file extension from MIME type
    /// - Parameter mimeType: The MIME type (e.g., "image/png")
    /// - Returns: File extension (e.g., "png")
    static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
            case "image/png": return "png"
            case "image/jpeg", "image/jpg": return "jpg"
            case "image/gif": return "gif"
            case "image/svg+xml": return "svg"
            case "application/pdf": return "pdf"
            case "image/webp": return "webp"
            default: return "dat"
        }
    }
    
    
    static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
            case "png": return "image/png"
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "svg": return "image/svg+xml"
            case "pdf": return "application/pdf"
            case "webp": return "image/webp"
            default: return "application/octet-stream"
        }
    }

}

/// File metadata structure
struct FileMetadata {
    let size: Int64
    let modifiedAt: Date
}
