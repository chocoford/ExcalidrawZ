//
//  MigrationV2.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 11/21/25.
//

@preconcurrency import CoreData
import Foundation
import Logging

struct Migration_MoveContentToICloudDrive: MigrationVersion {
    static var name: String = "Move Content To File Storage"
    static var description: String =
        "Moves file content from local database to unified file storage system (local + iCloud sync). This improves app performance by storing only file metadata locally while keeping actual file data in the file system."

    let logger = Logger(label: "Migration_MoveContentToICloudDrive")
    var context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func checkIfShouldMigrate() async throws -> Bool {
        return await context.perform {
            // Check if there are any File entities with content but no filePath
            let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
            fileFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
            fileFetchRequest.fetchLimit = 1

            if let fileCount = try? context.count(for: fileFetchRequest), fileCount > 0 {
                return true
            }

            // Check if there are any MediaItem entities with dataURL but no filePath
            let mediaFetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            mediaFetchRequest.predicate = NSPredicate(format: "dataURL != nil AND filePath == nil")
            mediaFetchRequest.fetchLimit = 1

            if let mediaCount = try? context.count(for: mediaFetchRequest), mediaCount > 0 {
                return true
            }

            // Check if there are any FileCheckpoint entities with content but no filePath
            let checkpointFetchRequest = NSFetchRequest<FileCheckpoint>(
                entityName: "FileCheckpoint")
            checkpointFetchRequest.predicate = NSPredicate(
                format: "content != nil AND filePath == nil")
            checkpointFetchRequest.fetchLimit = 1

            if let checkpointCount = try? context.count(for: checkpointFetchRequest),
                checkpointCount > 0
            {
                return true
            }

            return false
        }
    }

    /// V2: Move File.content from CoreData to File Storage (local + iCloud sync)
    func migrate(
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws {
        logger.info("🔧 Starting migration: CoreData content → File Storage")
        let start = Date()

        // Migrate Files (0 - 1/3)
        try await migrateFiles { description, progress in
            await progressHandler(description, progress / 3)
        }

        // Migrate MediaItems (1/3 - 2/3)
        try await migrateMediaItems { description, progress in
            await progressHandler(description, 1.0 / 3.0 + progress / 3)
        }

        // Migrate FileCheckpoints (2/3 - 1)
        try await migrateCheckpoints { description, progress in
            await progressHandler(description, 2.0 / 3.0 + progress / 3)
        }

        logger.info("🎉 Migration completed. Time cost: \(-start.timeIntervalSinceNow) s")
    }

    // MARK: - Private Migration Methods

    private func migrateFiles(
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "filePath == nil AND content != nil")

        let files = try await context.perform {
            try self.context.fetch(fetchRequest)
        }

        let waitingInterval: TimeInterval = 2 / Double(files.count)

        logger.info("Migrating \(files.count) files to file storage")

        for (i, file) in files.enumerated() {
            let objectID = file.objectID

            // Step 1: Extract data from CoreData
            let (content, fileID, fileName, updatedAt) = try await context.perform {
                guard let file = self.context.object(with: objectID) as? File else {
                    throw AppError.fileError(.notFound)
                }
                guard let content = file.content,
                    let fileID = file.id else {
                    throw AppError.fileError(
                        .contentNotAvailable(
                            filename: file.name ?? String(localizable: .generalUnknown)
                        )
                    )
                }
                return (content, fileID, file.name, file.updatedAt)
            }

            await progressHandler(
                "Migration file '\(fileName ?? String(localizable: .generalUntitled))'",
                Double(i) / Double(files.count)
            )

            do {
                // Step 2: Save to FileStorageManager
                let relativePath = try await FileStorageManager.shared.saveContent(
                    content,
                    fileID: fileID.uuidString,
                    type: .file,
                    updatedAt: updatedAt
                )

                // Step 3: Update entity in separate context.perform
                try await context.perform {
                    guard let file = self.context.object(with: objectID) as? File else { return }
                    file.updateAfterSavingToStorage(filePath: relativePath)
                    try self.context.save()
                }

                logger.info("Migrated file: \(fileName ?? "Unnamed") → \(relativePath)")
            } catch {
                logger.error(
                    "Failed migrating file \(fileName ?? "Unnamed"): \(error)")
            }
            if waitingInterval > 0.02 {
                try await Task.sleep(nanoseconds: UInt64(waitingInterval * 1e+9))
            }
        }
    }

    private func migrateMediaItems(
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws {
        let fetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
        fetchRequest.predicate = NSPredicate(format: "filePath == nil AND dataURL != nil")

        let mediaItems = try await context.perform {
            try self.context.fetch(fetchRequest)
        }

        let waitingInterval: TimeInterval = 2 / Double(max(1, mediaItems.count))

        logger.info("Migrating \(mediaItems.count) media items to file storage")

        for (i, mediaItem) in mediaItems.enumerated() {
            let objectID = mediaItem.objectID

            // Step 1: Extract data from CoreData
            let (dataURL, mediaID, updatedAt) = try await context.perform {
                guard let mediaItem = self.context.object(with: objectID) as? MediaItem,
                    let dataURL = mediaItem.dataURL,
                    let mediaID = mediaItem.id
                else {
                    throw MediaItemError.missingID
                }
                // Use createdAt if available, otherwise use current time
                let timestamp = mediaItem.createdAt ?? Date()
                return (dataURL, mediaID, timestamp)
            }

            await progressHandler(
                "Migrating media item '\(mediaID)'",
                Double(i) / Double(mediaItems.count)
            )

            do {
                // Step 2: Save to FileStorageManager (local + auto iCloud sync)
                let relativePath = try await FileStorageManager.shared.saveMediaItem(
                    dataURL: dataURL,
                    mediaID: mediaID,
                    updatedAt: updatedAt
                )

                // Step 3: Update entity in separate context.perform
                try await context.perform {
                    guard let mediaItem = self.context.object(with: objectID) as? MediaItem else {
                        return
                    }
                    mediaItem.updateAfterSavingToStorage(filePath: relativePath)
                    try self.context.save()
                }

                logger.info("Migrated media item: \(mediaID)<\(updatedAt)> → \(relativePath)")
            } catch {
                logger.error(
                    "Failed migrating media item \(mediaID)<\(updatedAt)>: \(error.localizedDescription)")
            }

            if waitingInterval > 0.02 {
                try await Task.sleep(nanoseconds: UInt64(waitingInterval * 1e+9))
            }
        }
    }

    private func migrateCheckpoints(
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "filePath == nil AND content != nil")

        let checkpoints = try await context.perform {
            try self.context.fetch(fetchRequest)
        }

        let waitingInterval: TimeInterval = 2 / Double(max(1, checkpoints.count))

        logger.info("Migrating \(checkpoints.count) checkpoints to file storage")

        for (i, checkpoint) in checkpoints.enumerated() {
            let objectID = checkpoint.objectID

            // Step 1: Extract data from CoreData
            let (content, checkpointID, updatedAt) = try await context.perform {
                guard let checkpoint = self.context.object(with: objectID) as? FileCheckpoint,
                    let content = checkpoint.content,
                    let checkpointID = checkpoint.id
                else {
                    throw FileCheckpointError.contentNotAvailable
                }
                return (content, checkpointID, checkpoint.updatedAt)
            }

            await progressHandler(
                "Migrating checkpoint '\(checkpointID)'",
                Double(i) / Double(checkpoints.count)
            )

            do {
                // Step 2: Save to FileStorageManager (local + auto iCloud sync)
                let relativePath = try await FileStorageManager.shared.saveContent(
                    content,
                    fileID: checkpointID.uuidString,
                    type: .checkpoint,
                    updatedAt: updatedAt
                )

                // Step 3: Update entity in separate context.perform
                try await context.perform {
                    guard let checkpoint = self.context.object(with: objectID) as? FileCheckpoint
                    else { return }
                    checkpoint.updateAfterSavingToStorage(filePath: relativePath)
                    try self.context.save()
                }

                logger.info("Migrated checkpoint: \(checkpointID) → \(relativePath)")
            } catch {
                logger.error(
                    "Failed migrating checkpoint \(checkpointID): \(error.localizedDescription)")
            }

            if waitingInterval > 0.02 {
                try await Task.sleep(nanoseconds: UInt64(waitingInterval * 1e+9))
            }
        }
    }
}
