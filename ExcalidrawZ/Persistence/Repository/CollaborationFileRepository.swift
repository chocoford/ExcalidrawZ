//
//  CollaborationFileRepository.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/22.
//

import Foundation
import CoreData
import Logging

/// Actor responsible for CollaborationFile entity operations
actor CollaborationFileRepository {
    private let logger = Logger(label: "CollaborationFileRepository")

    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Update CollaborationFile Content

    /// Update collaboration file content with new data from server
    /// - Parameters:
    ///   - collaborationFileObjectID: The NSManagedObjectID of the collaboration file
    ///   - content: The new content data from server
    ///   - newCheckpoint: Whether to create a new checkpoint or update existing one
    func updateElements(
        collaborationFileObjectID: NSManagedObjectID,
        content: Data,
        newCheckpoint: Bool
    ) async throws {
        // Update CoreData immediately (as fallback)
        try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else { return }
            collaborationFile.content = content
            collaborationFile.updatedAt = .now
            try self.context.save()
        }

        // Save to storage (this will clear content and set filePath)
        try await saveCollaborationFileContentToStorage(collaborationFileObjectID: collaborationFileObjectID)

        // Create or update checkpoint
        if newCheckpoint {
            logger.info("Creating new checkpoint for collaboration file")
            try await createCheckpoint(collaborationFileObjectID: collaborationFileObjectID, content: content)
        } else {
            try await updateLatestCheckpoint(collaborationFileObjectID: collaborationFileObjectID, content: content)
        }
    }

    // MARK: - Save CollaborationFile Content

    /// Save collaboration file content to storage (local + auto iCloud sync)
    /// - Parameter collaborationFileObjectID: The collaboration file objectID
    func saveCollaborationFileContentToStorage(collaborationFileObjectID: NSManagedObjectID) async throws {
        // Load file content, ID, and metadata
        let (content, fileID, updatedAt) = try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                throw AppError.fileError(.notFound)
            }
            guard let content = collaborationFile.content,
                  let fileID = collaborationFile.id else {
                throw AppError.fileError(.contentNotAvailable(filename: collaborationFile.name ?? String(localizable: .generalUnknown)))
            }
            return (content, fileID, collaborationFile.updatedAt)
        }

        // Save to storage (local + iCloud sync)
        let relativePath = try await FileStorageManager.shared.saveContent(
            content,
            fileID: fileID.uuidString,
            type: .collaborationFile,
            updatedAt: updatedAt
        )

        // Update after successful save
        try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else { return }
            collaborationFile.updateAfterSavingToStorage(filePath: relativePath)
            try self.context.save()
        }
        logger.info("Saved collaboration file to storage: \(relativePath)")
    }

    // MARK: - Checkpoint Management

    /// Create a new checkpoint for the collaboration file
    /// - Parameters:
    ///   - collaborationFileObjectID: The NSManagedObjectID of the collaboration file
    ///   - content: The content to save in the checkpoint
    func createCheckpoint(
        collaborationFileObjectID: NSManagedObjectID,
        content: Data
    ) async throws {
        try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                throw AppError.fileError(.notFound)
            }

            let checkpoint = FileCheckpoint(context: self.context)
            checkpoint.id = UUID()
            checkpoint.content = content
            checkpoint.filename = collaborationFile.name
            checkpoint.updatedAt = .now
            collaborationFile.addToCheckpoints(checkpoint)

            try self.context.save()

            // Clean up old checkpoints if needed
            let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetchRequest.predicate = NSPredicate(format: "collaborationFile = %@", collaborationFile)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            if let checkpoints = try? self.context.fetch(fetchRequest),
               checkpoints.count > 50 {
                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: checkpoints.suffix(checkpoints.count - 50).map{$0.objectID})
                try self.context.executeAndMergeChanges(using: batchDeleteRequest)
            }
        }
    }

    /// Update the latest checkpoint for the collaboration file
    /// - Parameters:
    ///   - collaborationFileObjectID: The NSManagedObjectID of the collaboration file
    ///   - content: The new content for the checkpoint
    func updateLatestCheckpoint(
        collaborationFileObjectID: NSManagedObjectID,
        content: Data
    ) async throws {
        try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                return
            }

            // MUST Inline fetch
            let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetchRequest.predicate = NSPredicate(format: "collaborationFile = %@", collaborationFile)
            fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
            guard let checkpoint = try self.context.fetch(fetchRequest).first else {
                return
            }

            self.logger.info("Updating latest checkpoint")
            checkpoint.content = content
            checkpoint.filename = collaborationFile.name
            checkpoint.updatedAt = .now

            try self.context.save()
        }
    }

    // MARK: - Archive CollaborationFile

    enum ArchiveTarget {
        case file(_ groupID: NSManagedObjectID, _ fileID: NSManagedObjectID)
        case localFile(_ folderID: NSManagedObjectID, _ url: URL)
    }

    /// Archive collaboration file to local database
    /// - Parameters:
    ///   - collaborationFileObjectID: The NSManagedObjectID of the collaboration file
    ///   - targetGroupObjectID: The target group objectID
    ///   - delete: Whether to delete the collaboration file after archiving
    /// - Returns: The archive target result
    func archiveToGroup(
        collaborationFileObjectID: NSManagedObjectID,
        targetGroupObjectID: NSManagedObjectID,
        delete: Bool
    ) async throws -> ArchiveTarget {
        // Load content from CollaborationFile
        let (name, collaborationFile) = try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                throw AppError.fileError(.notFound)
            }
            return (
                collaborationFile.name ?? String(localizable: .generalUntitled),
                collaborationFile
            )
        }

        let content = try await collaborationFile.loadContent()

        let fileID = try await context.perform {
            guard let group = self.context.object(with: targetGroupObjectID) as? Group,
                  let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                throw AppError.fileError(.notFound)
            }

            let newFile = File(name: name, context: self.context)
            newFile.group = group
            newFile.content = content
            newFile.inTrash = false

            self.context.insert(newFile)

            if delete {
                self.context.delete(collaborationFile)
            }

            try self.context.save()

            return newFile.objectID
        }

        return .file(targetGroupObjectID, fileID)
    }

    /// Archive collaboration file to local folder
    /// - Parameters:
    ///   - collaborationFileObjectID: The NSManagedObjectID of the collaboration file
    ///   - targetLocalFolderObjectID: The target local folder objectID
    ///   - delete: Whether to delete the collaboration file after archiving
    /// - Returns: The archive target result with file URL
    func archiveToLocalFolder(
        collaborationFileObjectID: NSManagedObjectID,
        targetLocalFolderObjectID: NSManagedObjectID,
        delete: Bool
    ) async throws -> ArchiveTarget {
        // Load content from CollaborationFile
        let (name, collaborationFileID, collaborationFile) = try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                throw AppError.fileError(.notFound)
            }
            return (
                collaborationFile.name ?? String(localizable: .generalUntitled),
                collaborationFile.id,
                collaborationFile
            )
        }

        let content = try await collaborationFile.loadContent()

        // Sync files outside of context.perform since it's async
        var file = try ExcalidrawFile(data: content, id: collaborationFileID)
        try await file.syncFiles(context: self.context)

        let fileURL = try await context.perform {
            guard let localFolder = self.context.object(with: targetLocalFolderObjectID) as? LocalFolder,
                  let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                throw AppError.fileError(.notFound)
            }

            let fileURL = try localFolder.withSecurityScopedURL { scopedURL in
                let fileURL = scopedURL.appendingPathComponent(
                    name,
                    conformingTo: .excalidrawFile
                )
                try file.content?.write(to: fileURL)
                return fileURL
            }

            if delete {
                self.context.delete(collaborationFile)
            }

            try self.context.save()

            return fileURL
        }

        return .localFile(targetLocalFolderObjectID, fileURL)
    }

    // MARK: - Delete CollaborationFile

    /// Delete collaboration file and its checkpoints
    /// - Parameters:
    ///   - collaborationFileObjectID: The NSManagedObjectID of the collaboration file
    ///   - save: Whether to save the context after deletion
    func delete(
        collaborationFileObjectID: NSManagedObjectID,
        save: Bool = true
    ) async throws {
        // Extract file info before deletion
        let (filePath, fileID, checkpointPaths): (String?, UUID?, [(String, UUID)]) = try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                return (nil, nil, [])
            }

            // Collect checkpoint info before deletion
            let checkpointsFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            checkpointsFetchRequest.predicate = NSPredicate(format: "collaborationFile = %@", collaborationFile)
            let checkpoints = try self.context.fetch(checkpointsFetchRequest)

            let checkpointInfo = checkpoints.compactMap { checkpoint -> (String, UUID)? in
                guard let path = checkpoint.filePath, let id = checkpoint.id else { return nil }
                return (path, id)
            }

            // Delete checkpoints from database
            if !checkpoints.isEmpty {
                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: checkpoints.map{$0.objectID})
                try self.context.executeAndMergeChanges(using: batchDeleteRequest)
            }

            let path = collaborationFile.filePath
            let id = collaborationFile.id

            // Delete collaboration file from database
            self.context.delete(collaborationFile)

            if save {
                try self.context.save()
            }

            return (path, id, checkpointInfo)
        }

        // Delete physical files from storage (local + iCloud)
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
                print("Warning: Failed to delete collaboration file from storage: \(error)")
            }
        }
    }
}
