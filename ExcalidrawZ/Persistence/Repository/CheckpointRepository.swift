//
//  CheckpointRepository.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/21.
//

import Foundation
import CoreData
import Logging

/// Actor responsible for FileCheckpoint entity operations with iCloud Drive integration
actor CheckpointRepository {
    private let logger = Logger(label: "CheckpointRepository")

    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Create Checkpoint

    /// Create a new checkpoint for a file
    /// - Parameters:
    ///   - fileObjectID: The file to create checkpoint for
    ///   - content: The checkpoint content
    ///   - filename: The filename at the time of checkpoint
    /// - Returns: The objectID of the created checkpoint
    func createCheckpoint(
        fileObjectID: NSManagedObjectID,
        content: Data,
        filename: String?
    ) async throws -> NSManagedObjectID {
        // Create checkpoint entity with content as fallback
        let checkpointObjectID = try await context.perform {
            guard let file = self.context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }

            let checkpoint = FileCheckpoint(context: self.context)
            checkpoint.id = UUID()
            checkpoint.content = content
            checkpoint.filename = filename
            checkpoint.updatedAt = .now
            file.addToCheckpoints(checkpoint)

            try self.context.save()

            // Clean up old checkpoints if needed
            if let checkpoints = try? PersistenceController.shared.fetchFileCheckpoints(of: file, viewContext: self.context),
               checkpoints.count > 50 {
                file.removeFromCheckpoints(checkpoints.last!)
            }

            return checkpoint.objectID
        }

        // Save checkpoint to storage
        try await saveCheckpointToStorage(checkpointObjectID: checkpointObjectID)

        return checkpointObjectID
    }

    // MARK: - Update Checkpoint

    /// Update the latest checkpoint for a file
    /// - Parameters:
    ///   - fileObjectID: The file to update checkpoint for
    ///   - content: The new checkpoint content
    ///   - filename: The filename at the time of checkpoint
    func updateLatestCheckpoint(
        fileObjectID: NSManagedObjectID,
        content: Data,
        filename: String?
    ) async throws {
        let checkpointObjectID: NSManagedObjectID? = try await context.perform {
            guard let file = self.context.object(with: fileObjectID) as? File else {
                return nil
            }

            // MUST Inline fetch
            let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetchRequest.predicate = NSPredicate(format: "file == %@", file)
            fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
            guard let checkpoint = try self.context.fetch(fetchRequest).first else {
                return nil
            }

            self.logger.info("Updating latest checkpoint")
            checkpoint.content = content
            checkpoint.filename = filename
            checkpoint.updatedAt = .now

            try self.context.save()

            return checkpoint.objectID
        }

        // Save checkpoint to storage if it exists
        if let checkpointObjectID = checkpointObjectID {
            try await saveCheckpointToStorage(checkpointObjectID: checkpointObjectID)
        }
    }

    // MARK: - Load Checkpoint

    /// Load checkpoint content from iCloud Drive or CoreData
    /// - Parameter checkpointObjectID: The checkpoint objectID
    /// - Returns: The checkpoint content
    func loadCheckpointContent(
        checkpointObjectID: NSManagedObjectID
    ) async throws -> Data {
        guard let checkpoint = context.object(with: checkpointObjectID) as? FileCheckpoint else {
            throw AppError.fileError(.notFound)
        }

        return try await checkpoint.loadContent()
    }

    // MARK: - Delete Checkpoint

    /// Delete a checkpoint
    /// - Parameter checkpointObjectID: The checkpoint objectID to delete
    func deleteCheckpoint(
        checkpointObjectID: NSManagedObjectID
    ) async throws {
        // Extract checkpoint info before deletion
        let (filePath, checkpointID): (String?, UUID?) = try await context.perform {
            guard let checkpoint = self.context.object(with: checkpointObjectID) as? FileCheckpoint else {
                return (nil, nil)
            }
            let path = checkpoint.filePath
            let id = checkpoint.id

            // Delete database record first
            self.context.delete(checkpoint)
            try self.context.save()

            return (path, id)
        }

        // Delete physical file from storage (local + iCloud)
        if let relativePath = filePath, let fileID = checkpointID {
            do {
                try await FileStorageManager.shared.deleteContent(relativePath: relativePath, fileID: fileID.uuidString)
            } catch {
                // Log but don't throw - database record is already deleted
                print("Warning: Failed to delete checkpoint file from storage: \(error)")
            }
        }
    }

    // MARK: - Save Checkpoint

    /// Save checkpoint content to storage (local + auto iCloud sync)
    /// - Parameter checkpointObjectID: The checkpoint objectID
    func saveCheckpointToStorage(checkpointObjectID: NSManagedObjectID) async throws {
        // Get checkpoint content, ID, and metadata from CoreData
        let (content, checkpointID, updatedAt) = try await context.perform {
            guard let checkpoint = self.context.object(with: checkpointObjectID) as? FileCheckpoint,
                  let content = checkpoint.content,
                  let checkpointID = checkpoint.id else {
                throw FileCheckpointError.contentNotAvailable
            }
            return (content, checkpointID, checkpoint.updatedAt)
        }

        // Save to storage (local + iCloud sync)
        let relativePath = try await FileStorageManager.shared.saveContent(
            content,
            fileID: checkpointID.uuidString,
            type: .checkpoint,
            updatedAt: updatedAt
        )

        // Update after successful save
        try await context.perform {
            guard let checkpoint = self.context.object(with: checkpointObjectID) as? FileCheckpoint else { return }
            checkpoint.updateAfterSavingToStorage(filePath: relativePath)
            try self.context.save()
        }
        logger.info("Saved checkpoint to storage: \(relativePath)")
    }

    // MARK: - Restore Checkpoint

    /// Restore a file to a checkpoint state
    /// - Parameters:
    ///   - checkpointObjectID: The checkpoint to restore from
    ///   - fileObjectID: The file to restore to
    func restoreCheckpoint(
        checkpointObjectID: NSManagedObjectID,
        to fileObjectID: NSManagedObjectID
    ) async throws {
        // Load checkpoint content
        let content = try await loadCheckpointContent(checkpointObjectID: checkpointObjectID)

        // Update file with checkpoint content in CoreData
        // Note: Caller is responsible for saving the file to storage if needed
        // by calling FileRepository.saveFileContentToStorage(fileObjectID:)
        try await context.perform {
            guard let file = self.context.object(with: fileObjectID) as? File,
                  let checkpoint = self.context.object(with: checkpointObjectID) as? FileCheckpoint else {
                throw AppError.fileError(.notFound)
            }

            file.content = content
            file.name = checkpoint.filename
            file.updatedAt = .now

            try self.context.save()
        }
    }
}
