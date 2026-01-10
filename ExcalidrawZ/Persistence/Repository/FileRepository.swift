//
//  FileRepository.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import Foundation
import CoreData
import Logging

/// Actor responsible for File entity operations with iCloud Drive integration
actor FileRepository {
    private let logger = Logger(label: "FileRepository")

    // MARK: - Create File

    /// Create a new file with content and save to iCloud Drive
    /// - Parameters:
    ///   - name: The file name
    ///   - content: The file content data
    ///   - groupObjectID: The group to add the file to
    /// - Returns: The objectID of the created file
    func createFile(
        name: String,
        content: Data,
        groupObjectID: NSManagedObjectID
    ) async throws -> NSManagedObjectID {
        let context = PersistenceController.shared.newTaskContext()

        // Create file entity with content as fallback
        let fileObjectID = try await context.perform {
            let file = File(name: name, context: context)
            if let group = context.object(with: groupObjectID) as? Group {
                file.group = group
            }

            context.insert(file)
            try context.save()

            return file.objectID
        }

        // Save content to storage
        try await saveFileContentToStorage(fileObjectID: fileObjectID, content: content)

        return fileObjectID
    }

    /// Create a file from a URL and save to iCloud Drive
    /// - Parameters:
    ///   - url: The URL to load file content from
    ///   - groupObjectID: The group to add the file to
    /// - Returns: The objectID of the created file
    func createFileFromURL(
        _ url: URL,
        groupObjectID: NSManagedObjectID
    ) async throws -> NSManagedObjectID {
        // Extract filename
        let lastPathComponent = url.lastPathComponent
        var fileNameURL = url
        for _ in 0..<lastPathComponent.count(where: {$0 == "."}) {
            fileNameURL.deletePathExtension()
        }
        let filename = fileNameURL.lastPathComponent

        // Load file data
        let data = try Data(contentsOf: url)

        return try await createFile(
            name: filename,
            content: data,
            groupObjectID: groupObjectID
        )
    }

    /// Create a file from ExcalidrawFile data
    /// - Parameters:
    ///   - excalidrawFile: The excalidraw file to import
    ///   - groupObjectID: The group to add the file to
    /// - Returns: Tuple of (fileObjectID, mediaObjectIDs and their corresponding resource files)
    func createFileFromExcalidraw(
        _ excalidrawFile: ExcalidrawFile,
        groupObjectID: NSManagedObjectID
    ) async throws -> (fileObjectID: NSManagedObjectID, mediaItems: [(NSManagedObjectID, ExcalidrawFile.ResourceFile)]) {
        let context = PersistenceController.shared.newTaskContext()

        let fileContent = try excalidrawFile.contentWithoutFiles()
        let fileName = excalidrawFile.name ?? "Untitled"

        // Create file
        let fileObjectID = try await createFile(
            name: fileName,
            content: fileContent,
            groupObjectID: groupObjectID
        )

        // Get existing media items to avoid duplicates
        let allMediaItems = try await context.perform {
            try context.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
        }

        // Filter media items that need to be imported
        let mediaItemsNeedImport = excalidrawFile.files.values.filter { item in
            !allMediaItems.contains(where: { $0.id == item.id })
        }

        // Create media item entities
        var mediaItemPairs: [(NSManagedObjectID, ExcalidrawFile.ResourceFile)] = []
        for resource in mediaItemsNeedImport {
            let mediaObjectID = try await context.perform {
                guard let file = context.object(with: fileObjectID) as? File else {
                    throw AppError.fileError(.notFound)
                }

                let mediaItem = MediaItem(resource: resource, context: context)
                mediaItem.file = file
                context.insert(mediaItem)
                try context.save()

                return mediaItem.objectID
            }

            mediaItemPairs.append((mediaObjectID, resource))
        }

        // Save media items to iCloud Drive
        for (mediaObjectID, resource) in mediaItemPairs {
            do {
                // Try to save to iCloud Drive
                let mediaItemID = try await context.perform {
                    guard let mediaItem = context.object(with: mediaObjectID) as? MediaItem,
                          let mediaItemID = mediaItem.id else {
                        throw MediaItemError.missingID
                    }
                    return mediaItemID
                }

                let relativePath = try await FileStorageManager.shared.saveMediaItem(
                    dataURL: resource.dataURL,
                    mediaID: mediaItemID,
                    updatedAt: resource.createdAt
                )

                // Update after successful save
                try await context.perform {
                    guard let mediaItem = context.object(with: mediaObjectID) as? MediaItem else { return }
                    mediaItem.updateAfterSavingToStorage(filePath: relativePath)
                    try context.save()
                }
                logger.info("Saved media item to storage: \(relativePath)")
            } catch {
                logger.warning("Failed to save media item to iCloud Drive: \(error.localizedDescription)")
                continue
            }
        }

        return (fileObjectID, mediaItemPairs)
    }

    // MARK: - Update File

    /// Update file elements with new data and optionally create a checkpoint
    /// - Parameters:
    ///   - fileObjectID: The NSManagedObjectID of the file
    ///   - fileData: The new file data containing updated elements
    ///   - newCheckpoint: Whether to create a new checkpoint
    func updateElements(
        fileObjectID: NSManagedObjectID,
        fileData: Data,
        newCheckpoint: Bool
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        // Step 1: Load file entity to get access to loadContent()
        let file = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }
            return file
        }

        // Step 2: Load content outside context.perform
        let data = try await file.loadContent()

        // Step 3: Prepare updated content
        let contentData = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }
            var obj = try JSONSerialization.jsonObject(with: data) as! [String : Any]
            guard let fileDataJson = try JSONSerialization.jsonObject(with: fileData) as? [String : Any] else {
                throw AppError.fileError(.contentNotAvailable(filename: file.name ?? String(localizable: .generalUnknown)))
            }
            obj["elements"] = fileDataJson["elements"]
            obj["appState"] = fileDataJson["appState"]
            obj.removeValue(forKey: "files")
            return try JSONSerialization.data(withJSONObject: obj)
        }

        // Step 4: Update CoreData immediately (as fallback)
        try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else { return }
            file.content = contentData
            file.updatedAt = .now
            try context.save()
        }

        // Step 5: Save file to storage
        try await saveFileContentToStorage(fileObjectID: fileObjectID, content: contentData)

        // Step 6: Create or update checkpoint
        if newCheckpoint {
            self.logger.info("Creating new checkpoint for file")
            try await createCheckpoint(fileObjectID: fileObjectID, content: contentData)
        } else {
            try await updateLatestCheckpoint(fileObjectID: fileObjectID, content: contentData)
        }
    }

    /// Save file content to storage (local + auto iCloud sync)
    /// - Parameters:
    ///   - fileObjectID: The file objectID
    ///   - content: The content data to save
    func saveFileContentToStorage(fileObjectID: NSManagedObjectID, content: Data) async throws {
        let context = PersistenceController.shared.newTaskContext()

        // Step 1: Get file ID and metadata
        let (fileID, updatedAt) = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }
            guard let fileID = file.id else {
                throw AppError.fileError(.contentNotAvailable(filename: file.name ?? String(localizable: .generalUnknown)))
            }
            return (fileID, file.updatedAt)
        }

        // Step 2: Save to storage (local + iCloud sync)
        let relativePath = try await FileStorageManager.shared.saveContent(
            content,
            fileID: fileID.uuidString,
            type: .file,
            updatedAt: updatedAt
        )

        // Step 3: Update after successful save
        try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else { return }
            file.updateAfterSavingToStorage(filePath: relativePath)
            try context.save()
        }
        logger.info("Saved file to storage: \(relativePath)")
    }

    /// Create a new checkpoint for the file
    private func createCheckpoint(
        fileObjectID: NSManagedObjectID,
        content: Data
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        let checkpointObjectID = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }

            let checkpoint = FileCheckpoint(context: context)
            checkpoint.id = UUID()
            checkpoint.content = content
            checkpoint.filename = file.name
            checkpoint.updatedAt = .now
            file.addToCheckpoints(checkpoint)

            try context.save()

            // Clean up old checkpoints if needed
            if let checkpoints = try? PersistenceController.shared.fetchFileCheckpoints(of: file, viewContext: context),
               checkpoints.count > 50 {
                file.removeFromCheckpoints(checkpoints.last!)
            }

            return checkpoint.objectID
        }

        // Save checkpoint to storage using CheckpointRepository
        try await PersistenceController.shared.checkpointRepository.saveCheckpointToStorage(checkpointObjectID: checkpointObjectID)
    }

    /// Update the latest checkpoint for the file
    private func updateLatestCheckpoint(
        fileObjectID: NSManagedObjectID,
        content: Data
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        let checkpointObjectID: NSManagedObjectID? = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                return nil
            }

            // MUST Inline fetch
            let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetchRequest.predicate = NSPredicate(format: "file == %@", file)
            fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
            guard let checkpoint = try context.fetch(fetchRequest).first else {
                return nil
            }

            self.logger.info("Updating latest checkpoint")
            checkpoint.content = content
            checkpoint.filename = file.name
            checkpoint.updatedAt = .now

            try context.save()

            return checkpoint.objectID
        }

        // Save checkpoint to storage if it exists
        if let checkpointObjectID = checkpointObjectID {
            try await PersistenceController.shared.checkpointRepository.saveCheckpointToStorage(checkpointObjectID: checkpointObjectID)
        }
    }

    // MARK: - Export File

    /// Export file to disk at specified folder URL
    /// - Parameters:
    ///   - fileObjectID: The NSManagedObjectID of the file
    ///   - folderURL: The destination folder URL
    func exportToDisk(fileObjectID: NSManagedObjectID, folder folderURL: URL) async throws {
        let context = PersistenceController.shared.newTaskContext()

        let fileManager = FileManager.default

        // Step 1: Get file entity and generate unique filename
        let (file, fileName) = try await context.perform {
            let fileManager = FileManager.default

            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }

            var name = file.name ?? String(localizable: .generalUntitled)
            // Check for existing files and add number suffix if needed
            var i = 1
            while fileManager.fileExists(
                atPath: folderURL.appendingPathComponent(name, conformingTo: .excalidrawFile).filePath
            ) {
                name = (file.name ?? String(localizable: .generalUntitled)) + " (\(i))"
                i += 1
            }

            return (file, name)
        }

        // Step 2: Load content outside context.perform
        let content = try await file.loadContent()

        // Step 3: Create file on disk
        let fileURL = folderURL.appendingPathComponent(fileName, conformingTo: .excalidrawFile)
        fileManager.createFile(atPath: fileURL.filePath, contents: content)
    }

    // MARK: - Delete File

    /// Delete file (move to trash or permanently delete)
    /// - Parameters:
    ///   - fileObjectID: The NSManagedObjectID of the file
    ///   - forcePermanently: Whether to force permanent deletion
    ///   - save: Whether to save the context after deletion
    func delete(
        fileObjectID: NSManagedObjectID,
        forcePermanently: Bool = false,
        save: Bool = true
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        // Extract file info before deletion (for permanent deletion only)
        let (filePath, fileID, checkpointPaths): (String?, UUID?, [(String, UUID)]) = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                return (nil, nil, [])
            }

            if file.inTrash || forcePermanently {
                // Permanent deletion: collect file info and checkpoint info
                let checkpointsFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
                checkpointsFetchRequest.predicate = NSPredicate(format: "file = %@", file)
                let fileCheckpoints = try context.fetch(checkpointsFetchRequest)

                // Collect checkpoint paths for deletion
                let checkpointInfo = fileCheckpoints.compactMap { checkpoint -> (String, UUID)? in
                    guard let path = checkpoint.filePath, let id = checkpoint.id else { return nil }
                    return (path, id)
                }

                // Delete checkpoints from database
                if !fileCheckpoints.isEmpty {
                    let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: fileCheckpoints.map { $0.objectID })
                    try context.executeAndMergeChanges(using: batchDeleteRequest)
                }

                let path = file.filePath
                let id = file.id

                // Delete file from database
                context.delete(file)

                if save {
                    try context.save()
                }

                return (path, id, checkpointInfo)
            } else {
                // Soft deletion: move to trash
                file.inTrash = true
                file.deletedAt = .now

                if save {
                    try context.save()
                }

                return (nil, nil, [])
            }
        }

        // Delete physical files from storage (local + iCloud) - only for permanent deletion
        if let relativePath = filePath, let fileUUID = fileID {
            // Delete checkpoint files
            for (checkpointPath, checkpointID) in checkpointPaths {
                do {
                    try await FileStorageManager.shared.deleteContent(relativePath: checkpointPath, fileID: checkpointID.uuidString)
                } catch {
                    print("Warning: Failed to delete checkpoint file from storage: \(error)")
                }
            }

            // Delete main file
            do {
                try await FileStorageManager.shared.deleteContent(relativePath: relativePath, fileID: fileUUID.uuidString)
            } catch {
                print("Warning: Failed to delete file from storage: \(error)")
            }
        }
    }
}
