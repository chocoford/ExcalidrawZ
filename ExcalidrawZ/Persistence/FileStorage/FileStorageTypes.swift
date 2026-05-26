//
//  FileStorageTypes.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/27.
//

import Foundation

// MARK: - Shared Types

/// Content type for file storage (shared between local and iCloud)
///
/// Each case identifies a domain namespace under the storage root: own
/// directory, own filename convention, own iCloud sync routing. New
/// kinds of file content go here as additional cases — both the
/// LocalStorageManager and iCloudDriveFileManager exhaustively switch
/// on this so adding a case forces wiring on both sides.
///
/// `.aiChatAttachment(extension:)` is the per-message attachment carried
/// by an `AIConversationMessage` (typically a screenshot the user
/// pasted into chat or an image the assistant returned). It uses
/// `extension` rather than a fixed file suffix because attachment
/// formats are heterogeneous (png/jpg/gif/pdf/...).
enum FileStorageContentType: Hashable, Equatable, CustomStringConvertible {
    case file
    case collaborationFile
    case checkpoint
    case mediaItem(extension: String)
    case aiChatAttachment(extension: String)

    var fileExtension: String {
        switch self {
            case .file: return "excalidrawz"
            case .collaborationFile: return "excalidrawz_collab"
            case .checkpoint: return "excalidrawz_checkpoint"
            case .mediaItem(let ext): return ext
            case .aiChatAttachment(let ext): return ext
        }
    }

    var description: String {
        switch self {
            case .file: "file"
            case .collaborationFile: "collaborationFile"
            case .checkpoint: "checkpoint"
            case .mediaItem: "mediaItem"
            case .aiChatAttachment: "aiChatAttachment"
        }
    }
}

// MARK: - FileStorageContentType Utilities

extension FileStorageContentType {
    /// Generate relative path for a file
    /// - Parameter fileID: The file identifier. For `.aiChatAttachment`,
    ///   this is expected to embed the conversation id as a leading
    ///   path component (e.g. `"<conversationID>/<UUID>"`) so all
    ///   attachments for a conversation live under one subdirectory —
    ///   makes bulk delete / GC tractable.
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
            case .aiChatAttachment(let ext):
                directory = "AIChatAttachments"
                filename = "\(fileID).\(ext)"
        }

        return "\(directory)/\(filename)"
    }

    /// Determine content type from relative path
    /// - Parameter relativePath: The relative path (e.g., "Files/uuid.excalidrawz")
    /// - Returns: The content type, or nil if unknown
    static func from(relativePath: String) -> FileStorageContentType? {
        let fileExtension = (relativePath as NSString).pathExtension
        // AI chat attachments share extensions with media items (png/jpg/etc.),
        // so directory prefix wins over extension-only matching. Without
        // this, SyncCoordinator would route an AI attachment through the
        // MediaItems pipeline.
        let topDirectory = relativePath.split(separator: "/").first.map(String.init) ?? ""
        if topDirectory == "AIChatAttachments" {
            return .aiChatAttachment(extension: fileExtension)
        }

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
