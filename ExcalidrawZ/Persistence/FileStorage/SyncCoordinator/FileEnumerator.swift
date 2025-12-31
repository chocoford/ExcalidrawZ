//
//  FileEnumerator.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/12/31.
//

import Foundation
import CoreData
import Logging

/// File enumeration from different sources (local, iCloud, CoreData)
struct FileEnumerator {
    private let logger = Logger(label: "FileEnumerator")
    private let localManager: LocalStorageManager
    private let iCloudManager: iCloudDriveFileManager

    init(localManager: LocalStorageManager, iCloudManager: iCloudDriveFileManager) {
        self.localManager = localManager
        self.iCloudManager = iCloudManager
    }

    // MARK: - File Enumeration

    /// Enumerate all local files
    func enumerateLocalFiles() async throws -> [SyncFileState] {
        var files: [SyncFileState] = []

        guard let storageURL = await localManager.getStorageURL() else {
            return files
        }

        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: storageURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Check if it's a regular file
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            // Extract fileID from filename
            let filename = fileURL.lastPathComponent
            let components = filename.split(separator: ".")
            guard let fileIDSubstring = components.first else {
                continue
            }
            let fileID = String(fileIDSubstring)

            // Get metadata
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
            let size = attributes[.size] as? Int64 ?? 0

            // Get relative path
            let relativePath = String(fileURL.path.dropFirst(storageURL.path.count + 1))

            // Determine content type from file extension
            guard let contentType = FileStorageContentType.from(relativePath: relativePath) else {
                // Skip files with unknown extensions
                continue
            }

            files.append(SyncFileState(
                fileID: fileID,
                relativePath: relativePath,
                contentType: contentType,
                modifiedAt: modifiedAt,
                size: size
            ))
        }

        return files
    }

    /// Enumerate all iCloud files
    func enumerateICloudFiles() async throws -> [SyncFileState] {
        var files: [SyncFileState] = []

        guard let containerURL = await iCloudManager.containerURL else {
            return files
        }

        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: containerURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Check if it's a regular file
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            // Extract fileID from filename
            let filename = fileURL.lastPathComponent
            let components = filename.split(separator: ".")
            guard let fileIDSubstring = components.first else {
                continue
            }
            let fileID = String(fileIDSubstring)

            // Get metadata
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
            let size = attributes[.size] as? Int64 ?? 0

            // Get relative path
            let relativePath = String(fileURL.path.dropFirst(containerURL.path.count + 1))

            // Determine content type from file extension
            guard let contentType = FileStorageContentType.from(relativePath: relativePath) else {
                // Skip files with unknown extensions
                continue
            }

            files.append(SyncFileState(
                fileID: fileID,
                relativePath: relativePath,
                contentType: contentType,
                modifiedAt: modifiedAt,
                size: size
            ))
        }

        return files
    }

    /// Enumerate all files that should exist based on CoreData entities
    func enumerateExpectedFiles() async -> [SyncFileState] {
        let context = PersistenceController.shared.newTaskContext()
        var expectedFiles: [SyncFileState] = []

        // Fetch all File entities
        do {
            let fileRequest: NSFetchRequest<File> = File.fetchRequest()
            fileRequest.propertiesToFetch = ["id", "updatedAt"]
            let files = try context.fetch(fileRequest)
            for file in files {
                guard let fileID = file.id?.uuidString,
                      let updatedAt = file.updatedAt else { continue }

                let relativePath = FileStorageContentType.file.generateRelativePath(fileID: fileID)
                expectedFiles.append(SyncFileState(
                    fileID: fileID,
                    relativePath: relativePath,
                    contentType: .file,
                    modifiedAt: updatedAt,
                    size: 0  // Size will be determined from filesystem
                ))
            }
        } catch {
            logger.error("Failed to fetch File entities: \(error.localizedDescription)")
        }

        // Fetch all CollaborationFile entities
        do {
            let collabRequest: NSFetchRequest<CollaborationFile> = CollaborationFile.fetchRequest()
            collabRequest.propertiesToFetch = ["id", "updatedAt"]
            let collabFiles = try context.fetch(collabRequest)
            for collabFile in collabFiles {
                guard let fileID = collabFile.id?.uuidString,
                      let updatedAt = collabFile.updatedAt else { continue }

                let relativePath = FileStorageContentType.collaborationFile.generateRelativePath(fileID: fileID)
                expectedFiles.append(SyncFileState(
                    fileID: fileID,
                    relativePath: relativePath,
                    contentType: .collaborationFile,
                    modifiedAt: updatedAt,
                    size: 0
                ))
            }
        } catch {
            logger.error("Failed to fetch CollaborationFile entities: \(error.localizedDescription)")
        }

        // Fetch all FileCheckpoint entities
        do {
            let checkpointRequest: NSFetchRequest<FileCheckpoint> = FileCheckpoint.fetchRequest()
            checkpointRequest.propertiesToFetch = ["id", "updatedAt"]
            let checkpoints = try context.fetch(checkpointRequest)
            for checkpoint in checkpoints {
                guard let fileID = checkpoint.id?.uuidString,
                      let timestamp = checkpoint.updatedAt else { continue }

                let relativePath = FileStorageContentType.checkpoint.generateRelativePath(fileID: fileID)
                expectedFiles.append(SyncFileState(
                    fileID: fileID,
                    relativePath: relativePath,
                    contentType: .checkpoint,
                    modifiedAt: timestamp,
                    size: 0
                ))
            }
        } catch {
            logger.error("Failed to fetch FileCheckpoint entities: \(error.localizedDescription)")
        }

        // Fetch all MediaItem entities
        do {
            let mediaRequest: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            mediaRequest.propertiesToFetch = ["id", "mimeType", "createdAt"]
            let mediaItems = try context.fetch(mediaRequest)
            for mediaItem in mediaItems {
                guard let fileID = mediaItem.id,
                      let mimeType = mediaItem.mimeType,
                      let createdAt = mediaItem.createdAt else { continue }
                let ext = FileStorageContentType.fileExtension(for: mimeType)
                let contentType = FileStorageContentType.mediaItem(extension: ext)
                let relativePath = contentType.generateRelativePath(fileID: fileID)
                expectedFiles.append(SyncFileState(
                    fileID: fileID,
                    relativePath: relativePath,
                    contentType: contentType,
                    modifiedAt: createdAt,
                    size: 0
                ))
            }
        } catch {
            logger.error("Failed to fetch MediaItem entities: \(error.localizedDescription)")
        }

        logger.info("Found \(expectedFiles.count) expected files from CoreData")
        return expectedFiles
    }
}
