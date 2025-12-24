//
//  iCloudDriveDataMigrator.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import Foundation
@preconcurrency import CoreData
import OSLog

/// Migrates data from CoreData binary storage to iCloud Drive files
actor iCloudDriveDataMigrator {
    static let shared = iCloudDriveDataMigrator()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "iCloudDriveDataMigrator")
    private let fileManager = iCloudDriveFileManager.shared

    // MARK: - Migration Status

    /// Check if migration is needed
    func needsMigration(context: NSManagedObjectContext) async -> Bool {
        await context.perform {
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
            let checkpointFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            checkpointFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
            checkpointFetchRequest.fetchLimit = 1

            if let checkpointCount = try? context.count(for: checkpointFetchRequest), checkpointCount > 0 {
                return true
            }

            return false
        }
    }

    // MARK: - Migration

    /// Migrate all data from CoreData to iCloud Drive
    /// - Parameters:
    ///   - context: The NSManagedObjectContext to use
    ///   - progressHandler: Optional closure called with migration progress (0.0 to 1.0)
    func migrateAllData(
        context: NSManagedObjectContext,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        logger.info("Starting data migration to iCloud Drive")

        // Calculate total items to migrate
        let totalItems = await context.perform {
            let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
            fileFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
            let fileCount = (try? context.count(for: fileFetchRequest)) ?? 0

            let mediaFetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            mediaFetchRequest.predicate = NSPredicate(format: "dataURL != nil AND filePath == nil")
            let mediaCount = (try? context.count(for: mediaFetchRequest)) ?? 0

            let checkpointFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            checkpointFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
            let checkpointCount = (try? context.count(for: checkpointFetchRequest)) ?? 0

            return fileCount + mediaCount + checkpointCount
        }

        guard totalItems > 0 else {
            logger.info("No data to migrate")
            progressHandler?(1.0)
            return
        }

        var migratedCount = 0

        // Migrate File entities
        try await migrateFiles(context: context) { fileProgress in
            let progress = Double(migratedCount) / Double(totalItems) + fileProgress / Double(totalItems)
            progressHandler?(progress)
        }
        migratedCount += await getFilesMigrationCount(context: context)

        // Migrate MediaItem entities
        try await migrateMediaItems(context: context) { mediaProgress in
            let progress = Double(migratedCount) / Double(totalItems) + mediaProgress / Double(totalItems)
            progressHandler?(progress)
        }
        migratedCount += await getMediaItemsMigrationCount(context: context)

        // Migrate FileCheckpoint entities
        try await migrateFileCheckpoints(context: context) { checkpointProgress in
            let progress = Double(migratedCount) / Double(totalItems) + checkpointProgress / Double(totalItems)
            progressHandler?(progress)
        }

        progressHandler?(1.0)
        logger.info("Data migration completed successfully")
    }

    // MARK: - File Migration

    private func migrateFiles(
        context: NSManagedObjectContext,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
        fetchRequest.fetchBatchSize = 50

        let files = try await context.perform {
            try context.fetch(fetchRequest)
        }

        guard !files.isEmpty else { return }

        logger.info("Migrating \(files.count) File entities")

        for (index, file) in files.enumerated() {
            try await migrateFile(file, context: context)
            progressHandler?(Double(index + 1) / Double(files.count))
        }
    }

    private func migrateFile(_ file: File, context: NSManagedObjectContext) async throws {
        let objectID = file.objectID
        guard let content = file.content,
              let fileID = file.id else {
            logger.warning("Skipping file migration: missing content or ID")
            return
        }

        // Save to iCloud Drive
        let relativePath = try await fileManager.saveContent(content, id: fileID, type: .file)

        // Update CoreData entity using objectID
        await context.perform {
            guard let file = try? context.existingObject(with: objectID) as? File else { return }
            file.filePath = relativePath
            // Keep content for now as fallback
            // file.content = nil // Uncomment after migration is stable
            try? context.save()
        }

        logger.debug("Migrated File: \(fileID)")
    }

    // MARK: - MediaItem Migration

    private func migrateMediaItems(
        context: NSManagedObjectContext,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        let fetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
        fetchRequest.predicate = NSPredicate(format: "dataURL != nil AND filePath == nil")
        fetchRequest.fetchBatchSize = 50

        let mediaItems = try await context.perform {
            try context.fetch(fetchRequest)
        }

        guard !mediaItems.isEmpty else { return }

        logger.info("Migrating \(mediaItems.count) MediaItem entities")

        for (index, mediaItem) in mediaItems.enumerated() {
            try await migrateMediaItem(mediaItem, context: context)
            progressHandler?(Double(index + 1) / Double(mediaItems.count))
        }
    }

    private func migrateMediaItem(_ mediaItem: MediaItem, context: NSManagedObjectContext) async throws {
        let objectID = mediaItem.objectID
        guard let dataURL = mediaItem.dataURL,
              let itemID = mediaItem.id else {
            logger.warning("Skipping media item migration: missing dataURL or ID")
            return
        }

        // Save to iCloud Drive
        let relativePath = try await fileManager.saveMediaItem(dataURL: dataURL, itemID: itemID)

        // Update CoreData entity using objectID
        await context.perform {
            guard let mediaItem = try? context.existingObject(with: objectID) as? MediaItem else { return }
            mediaItem.filePath = relativePath
            // Keep dataURL for now as fallback
            // mediaItem.dataURL = nil // Uncomment after migration is stable
            try? context.save()
        }

        logger.debug("Migrated MediaItem: \(itemID)")
    }

    // MARK: - FileCheckpoint Migration

    private func migrateFileCheckpoints(
        context: NSManagedObjectContext,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
        fetchRequest.fetchBatchSize = 50

        let checkpoints = try await context.perform {
            try context.fetch(fetchRequest)
        }

        guard !checkpoints.isEmpty else { return }

        logger.info("Migrating \(checkpoints.count) FileCheckpoint entities")

        for (index, checkpoint) in checkpoints.enumerated() {
            try await migrateFileCheckpoint(checkpoint, context: context)
            progressHandler?(Double(index + 1) / Double(checkpoints.count))
        }
    }

    private func migrateFileCheckpoint(_ checkpoint: FileCheckpoint, context: NSManagedObjectContext) async throws {
        let objectID = checkpoint.objectID
        guard let content = checkpoint.content,
              let checkpointID = checkpoint.id else {
            logger.warning("Skipping checkpoint migration: missing content or ID")
            return
        }

        // Save to iCloud Drive
        let relativePath = try await fileManager.saveCheckpointContent(content, checkpointID: checkpointID)

        // Update CoreData entity using objectID
        await context.perform {
            guard let checkpoint = try? context.existingObject(with: objectID) as? FileCheckpoint else { return }
            checkpoint.filePath = relativePath
            // Keep content for now as fallback
            // checkpoint.content = nil // Uncomment after migration is stable
            try? context.save()
        }

        logger.debug("Migrated FileCheckpoint: \(checkpointID)")
    }

    // MARK: - Helper Methods

    private func getFilesMigrationCount(context: NSManagedObjectContext) async -> Int {
        await context.perform {
            let fetchRequest = NSFetchRequest<File>(entityName: "File")
            fetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
            return (try? context.count(for: fetchRequest)) ?? 0
        }
    }

    private func getMediaItemsMigrationCount(context: NSManagedObjectContext) async -> Int {
        await context.perform {
            let fetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            fetchRequest.predicate = NSPredicate(format: "dataURL != nil AND filePath == nil")
            return (try? context.count(for: fetchRequest)) ?? 0
        }
    }

    // MARK: - Cleanup

    /// Remove binary data from CoreData after successful migration
    /// Only call this after verifying the migration was successful
    func cleanupMigratedData(context: NSManagedObjectContext) async throws {
        logger.info("Cleaning up migrated data from CoreData")

        // Clean up File entities
        try await context.perform {
            let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
            fileFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath != nil")
            let files = try context.fetch(fileFetchRequest)

            for file in files {
                file.content = nil
            }

            try context.save()
            self.logger.info("Cleaned up \(files.count) File entities")
        }

        // Clean up MediaItem entities
        try await context.perform {
            let mediaFetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            mediaFetchRequest.predicate = NSPredicate(format: "dataURL != nil AND filePath != nil")
            let mediaItems = try context.fetch(mediaFetchRequest)

            for mediaItem in mediaItems {
                mediaItem.dataURL = nil
            }

            try context.save()
            self.logger.info("Cleaned up \(mediaItems.count) MediaItem entities")
        }

        // Clean up FileCheckpoint entities
        try await context.perform {
            let checkpointFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            checkpointFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath != nil")
            let checkpoints = try context.fetch(checkpointFetchRequest)

            for checkpoint in checkpoints {
                checkpoint.content = nil
            }

            try context.save()
            self.logger.info("Cleaned up \(checkpoints.count) FileCheckpoint entities")
        }

        logger.info("Cleanup completed successfully")
    }
}
