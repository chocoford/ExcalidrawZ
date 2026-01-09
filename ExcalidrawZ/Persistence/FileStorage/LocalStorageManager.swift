//
//  LocalStorageManager.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/26.
//

import Foundation
import Logging

/// Result of a save operation
struct SaveResult {
    let relativePath: String
    let wasModified: Bool
}

/// Local storage manager
/// Handles all local file operations in Application Support directory
actor LocalStorageManager {
    private let logger = Logger(label: "LocalStorageManager")
    
    init() {}
    
    // MARK: - Storage Directories
    
    enum StorageDirectory: String {
        case files = "Files"
        case collaborationFiles = "CollaborationFiles"
        case mediaItems = "MediaItems"
        case checkpoints = "Checkpoints"
        
        var path: String { rawValue }
    }
    
    // MARK: - Helper Extensions
    
    /// Extension to map FileStorageContentType to StorageDirectory
    private func directory(for type: FileStorageContentType) -> StorageDirectory {
        switch type {
            case .file: return .files
            case .collaborationFile: return .collaborationFiles
            case .checkpoint: return .checkpoints
            case .mediaItem: return .mediaItems
        }
    }
    
    // MARK: - Local Storage URL
    
    /// Get local storage base URL (Application Support directory)
    private var localStorageURL: URL? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        
        let storageURL = appSupport
            .appendingPathComponent("FileStorage", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        return storageURL
    }
    
    /// Ensure directory exists for storage type
    private func ensureDirectoryExists(for directory: StorageDirectory) throws -> URL {
        guard let baseURL = localStorageURL else {
            throw FileStorageError.storageUnavailable
        }
        
        let directoryURL = baseURL.appendingPathComponent(directory.path, isDirectory: true)
        
        if !FileManager.default.fileExists(at: directoryURL) {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        return directoryURL
    }
    
    // MARK: - Core Storage Operations
    
    /// Save content to local storage
    /// - Parameters:
    ///   - content: The content data to save
    ///   - fileID: The file identifier as String
    ///   - type: The content type
    ///   - updatedAt: Optional update timestamp
    /// - Returns: SaveResult with path and modification status
    func saveContent(
        _ content: Data,
        fileID: String,
        type: FileStorageContentType,
        updatedAt: Date? = nil
    ) throws -> SaveResult {
        let directory = try ensureDirectoryExists(for: directory(for: type))
        
        let filename: String
        switch type {
            case .mediaItem(let ext):
                // Use the provided extension for media items
                filename = "\(fileID).\(ext)"
            default:
                filename = "\(fileID).\(type.fileExtension)"
        }
        
        let fileURL = directory.appendingPathComponent(filename)
        let relativePath = "\(self.directory(for: type).path)/\(filename)"
        
        // Check if file exists and content is identical
        if FileManager.default.fileExists(at: fileURL) {
            do {
                let existingContent = try Data(contentsOf: fileURL)
                if existingContent == content {
                    logger.info("Content unchanged, skipping write: \(filename)")
                    do {
                        try FileManager.default.setAttributes(
                            [.modificationDate: updatedAt ?? Date()],
                            ofItemAtPath: fileURL.filePath
                        )
                    } catch {
                        logger.info("Update \(type.fileExtension)'s modified_at failed.")
                    }
                    return SaveResult(relativePath: relativePath, wasModified: false)
                }
            } catch {
                // Failed to read existing file, proceed with write
                logger.warning("Failed to read existing file for comparison: \(error.localizedDescription)")
            }
        }
        
        do {
            // Write content atomically
            try content.write(to: fileURL, options: .atomic)
            
            // Set modification date if provided
            do {
                try FileManager.default.setAttributes(
                    [.modificationDate: updatedAt ?? Date()],
                    ofItemAtPath: fileURL.filePath
                )
            } catch {
                logger.info("Update \(type.fileExtension)'s modified_at failed.")
            }
            
            logger.debug("Saved \(type.fileExtension) to local storage: \(fileURL)")
            return SaveResult(relativePath: relativePath, wasModified: true)
        } catch {
            logger.error("Failed to save file: \(error.localizedDescription)")
            throw FileStorageError.writeFailed(error.localizedDescription)
        }
    }
    
    /// Load content from local storage
    /// - Parameter relativePath: The relative path to the file
    /// - Returns: The content data
    func loadContent(relativePath: String) throws -> Data {
        guard let baseURL = localStorageURL else {
            throw FileStorageError.storageUnavailable
        }
        
        let fileURL = baseURL.appendingPathComponent(relativePath)
        
        guard FileManager.default.fileExists(at: fileURL) else {
            throw FileStorageError.fileNotFound(relativePath)
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            logger.info("Loaded content from local storage: \(relativePath)")
            return data
        } catch {
            logger.error("Failed to load file: \(error.localizedDescription)")
            throw FileStorageError.readFailed(error.localizedDescription)
        }
    }
    
    /// Delete content from local storage
    /// - Parameter relativePath: The relative path to the file
    func deleteContent(relativePath: String) throws {
        guard let baseURL = localStorageURL else {
            throw FileStorageError.storageUnavailable
        }
        
        let fileURL = baseURL.appendingPathComponent(relativePath)
        
        guard FileManager.default.fileExists(at: fileURL) else {
            logger.warning("File already deleted or not found: \(relativePath)")
            return
        }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted file from local storage: \(relativePath)")
        } catch {
            logger.error("Failed to delete file: \(error.localizedDescription)")
            throw FileStorageError.deleteFailed(error.localizedDescription)
        }
    }
    
    /// Check if file exists in local storage
    /// - Parameter relativePath: The relative path to check
    /// - Returns: True if file exists
    func fileExists(relativePath: String) -> Bool {
        guard let baseURL = localStorageURL else {
            return false
        }
        
        let fileURL = baseURL.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(at: fileURL)
    }
    
    /// Get file metadata
    /// - Parameter relativePath: The relative path to the file
    /// - Returns: File metadata (size and modification date)
    func getFileMetadata(relativePath: String) throws -> FileMetadata {
        guard let baseURL = localStorageURL else {
            throw FileStorageError.storageUnavailable
        }
        
        let fileURL = baseURL.appendingPathComponent(relativePath)
        
        guard FileManager.default.fileExists(at: fileURL) else {
            throw FileStorageError.fileNotFound(relativePath)
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.filePath)
        let size = attributes[.size] as? Int64 ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
        
        return FileMetadata(size: size, modifiedAt: modifiedAt)
    }
    
    // MARK: - Media Item Operations
    
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
    ) throws -> String {
        // Parse data URL
        guard let (mimeType, base64Data) = parseDataURL(dataURL),
              let data = Data(base64Encoded: base64Data) else {
            throw FileStorageError.writeFailed("Invalid data URL format")
        }
        
        let directory = try ensureDirectoryExists(for: .mediaItems)
        let fileExtension = FileStorageContentType.fileExtension(for: mimeType)
        let filename = "\(mediaID).\(fileExtension)"
        let fileURL = directory.appendingPathComponent(filename)
        let relativePath = "\(StorageDirectory.mediaItems.path)/\(filename)"
        
        do {
            try data.write(to: fileURL, options: .atomic)

            // Always set modification date (use provided date or current time)
            let date = updatedAt ?? Date()
            try? FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: fileURL.filePath
            )

            logger.debug("Saved media item to local storage: \(filename)")
            return relativePath
        } catch {
            throw FileStorageError.writeFailed(error.localizedDescription)
        }
    }
    
    /// Load media item and convert to data URL
    /// - Parameter relativePath: The relative path to the media file
    /// - Returns: The data URL string
    func loadMediaItem(relativePath: String) throws -> String {
        let data = try loadContent(relativePath: relativePath)
        let base64 = data.base64EncodedString()
        
        // Determine mime type from file extension
        let pathExtension = (relativePath as NSString).pathExtension
        let mimeType = mimeType(for: pathExtension)
        
        return "data:\(mimeType);base64,\(base64)"
    }
    
    // MARK: - Storage Statistics
    
    /// Get total storage size
    /// - Returns: Total size in bytes
    func getTotalStorageSize() throws -> Int64 {
        guard let baseURL = localStorageURL else {
            throw FileStorageError.storageUnavailable
        }
        
        var totalSize: Int64 = 0
        
        let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    // MARK: - Helper Methods
    
    private func parseDataURL(_ dataURL: String) -> (mimeType: String, base64Data: String)? {
        guard dataURL.hasPrefix("data:") else { return nil }
        
        let components = dataURL.dropFirst(5).split(separator: ",", maxSplits: 1)
        guard components.count == 2 else { return nil }
        
        let header = String(components[0])
        let base64 = String(components[1])
        
        let mimeType = header.split(separator: ";").first.map(String.init) ?? "application/octet-stream"
        
        return (mimeType, base64)
    }

    private func mimeType(for fileExtension: String) -> String {
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
    
    // MARK: - Public Helper Methods
    
    /// Get the base storage URL
    func getStorageURL() -> URL? {
        return localStorageURL
    }
    
    /// Get the full URL for a relative path
    func getFileURL(relativePath: String) throws -> URL {
        guard let baseURL = localStorageURL else {
            throw FileStorageError.storageUnavailable
        }
        return baseURL.appendingPathComponent(relativePath)
    }
}
