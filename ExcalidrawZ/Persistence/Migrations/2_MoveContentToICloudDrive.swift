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
    static var name: String = String(localizable: .migrationMoveContentToICloudDriveName)
    static var description: String = String(localizable: .migrationMoveContentToICloudDriveDescription)
    
    let logger = Logger(label: "Migration_MoveContentToICloudDrive")
    var context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    func checkIfShouldMigrate() async throws -> Bool {
        return try await context.perform {
            // Check if there are any File entities with content but no filePath
            let fileFetchRequest = File.fetchRequest()
            fileFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
            // Check if there are any MediaItem entities with dataURL but no filePath
            let mediaFetchRequest = MediaItem.fetchRequest()
            mediaFetchRequest.predicate = NSPredicate(format: "dataURL != nil AND filePath == nil")
            // Check if there are any FileCheckpoint entities with content but no filePath
            let checkpointFetchRequest = FileCheckpoint.fetchRequest()
            checkpointFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
            // Check if there are any CollaborationFile entities with content but no filePath
            let collaborationFileFetchRequest = CollaborationFile.fetchRequest()
            collaborationFileFetchRequest.predicate = NSPredicate(format: "content != nil AND filePath == nil")
#if !DEBUG
            fileFetchRequest.fetchLimit = 1
            mediaFetchRequest.fetchLimit = 1
            checkpointFetchRequest.fetchLimit = 1
            collaborationFileFetchRequest.fetchLimit = 1
#endif
            let fileCount = try context.count(for: fileFetchRequest)
            let mediaCount = try context.count(for: mediaFetchRequest)
            let checkpointCount = try context.count(for: checkpointFetchRequest)
            let collaborationFileCount = try context.count(for: collaborationFileFetchRequest)
            logger.info("checkIfShouldMigrate...")
            logger.info("Need migrate files: \(fileCount)")
            logger.info("Need migrate media: \(mediaCount)")
            logger.info("Need migrate checkpointCount: \(checkpointCount)")
            logger.info("Need migrate collaboration files: \(collaborationFileCount)")
            if fileCount > 0 || mediaCount > 0 || checkpointCount > 0 || collaborationFileCount > 0 {
                return true
            }
            return false
        }
    }
    
    /// V2: Move File.content from CoreData to File Storage (local + iCloud sync)
    func migrate(
        autoResolveErrors: Bool,
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws -> [MigrationFailedItem] {
        logger.info("🔧 Starting migration: CoreData content → File Storage (autoResolve: \(autoResolveErrors))")
        let start = Date()
        var allFailedItems: [MigrationFailedItem] = []
        
        // Migrate Files (0 - 1/4)
        let failedFiles = try await migrateFiles(autoResolveErrors: autoResolveErrors) { description, progress in
            await progressHandler(description, progress / 4)
        }
        allFailedItems.append(contentsOf: failedFiles)
        
        // Migrate CollaborationFiles (1/4 - 2/4)
        let failedCollabFiles = try await migrateCollaborationFiles(autoResolveErrors: autoResolveErrors) { description, progress in
            await progressHandler(description, 1.0 / 4.0 + progress / 4)
        }
        allFailedItems.append(contentsOf: failedCollabFiles)
        
        // Migrate MediaItems (2/4 - 3/4)
        let failedMedia = try await migrateMediaItems(autoResolveErrors: autoResolveErrors) { description, progress in
            await progressHandler(description, 2.0 / 4.0 + progress / 4)
        }
        allFailedItems.append(contentsOf: failedMedia)
        
        // Migrate FileCheckpoints (3/4 - 1)
        let failedCheckpoints = try await migrateCheckpoints(autoResolveErrors: autoResolveErrors) { description, progress in
            await progressHandler(description, 3.0 / 4.0 + progress / 4)
        }
        allFailedItems.append(contentsOf: failedCheckpoints)
        
        let timeCost = -start.timeIntervalSinceNow
        if allFailedItems.isEmpty {
            logger.info("🎉 Migration completed successfully. Time cost: \(timeCost) s")
        } else {
            logger.warning("⚠️ Migration completed with \(allFailedItems.count) failures. Time cost: \(timeCost) s")
        }
        
        return allFailedItems
    }
    
    // MARK: - Private Migration Methods
    
    private func migrateFiles(
        autoResolveErrors: Bool,
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws -> [MigrationFailedItem] {
        let fetchRequest = NSFetchRequest<File>(entityName: "File")
        fetchRequest.predicate = NSPredicate(format: "filePath == nil AND content != nil")
        
        // 严重错误 - throw
        let files = try await context.perform {
            try self.context.fetch(fetchRequest)
        }
        
        guard !files.isEmpty else {
            logger.info("No files to migrate")
            return []
        }
        
        let waitingInterval: TimeInterval = 2 / Double(files.count)
        var failedItems: [MigrationFailedItem] = []
        
        logger.info("Migrating \(files.count) files to file storage")
        
        for (i, file) in files.enumerated() {
            await progressHandler(
                "Migration file '\(file.name ?? String(localizable: .generalUntitled))'",
                Double(i) / Double(files.count)
            )
            
            let objectID = file.objectID
            
            
            struct MigrationFileError: LocalizedError {
                var errorDescription: String?
            }
            
            // 处理单个文件 - 可恢复错误用Result
            let result = await context.perform { () -> Result<(content: Data, fileID: UUID, fileName: String?, updatedAt: Date?), Error> in
                guard let file = self.context.object(with: objectID) as? File else {
                    return .failure(MigrationFileError(errorDescription: "File not found in context"))
                }
                guard let fileID = file.id else {
                    return .failure(MigrationFileError(errorDescription: "File ID is missing"))
                }
                
                var content = file.content
                if content == nil {
                    if autoResolveErrors {
                        content = ExcalidrawFile().content
                        file.content = content
                        do {
                            try self.context.save()
                            self.logger.info("Auto-resolved missing content for file: \(file.name ?? "Unnamed")")
                        } catch {
                            return .failure(MigrationFileError(errorDescription: "Failed to save auto-resolved content: \(error.localizedDescription)"))
                        }
                    } else {
                        return .failure(MigrationFileError(errorDescription: "Content is missing"))
                    }
                }
                
                return .success((content: content!, fileID: fileID, fileName: file.name, updatedAt: file.updatedAt))
            }
            
            switch result {
                case .success(let (content, fileID, fileName, updatedAt)):
                    
                    do {
                        // Save to FileStorageManager
                        let relativePath = try await FileStorageManager.shared.saveContent(
                            content,
                            fileID: fileID.uuidString,
                            type: .file,
                            updatedAt: updatedAt
                        )
                        
                        // Update entity
                        try await context.perform {
                            guard let file = self.context.object(with: objectID) as? File else { return }
                            file.updateAfterSavingToStorage(filePath: relativePath)
                            try self.context.save()
                        }
                        
                        logger.info("\(i+1)/\(files.count) | Migrated file: \(fileName ?? "Unnamed") → \(relativePath)")
                    } catch {
                        logger.error("Failed saving file '\(fileName ?? "Unnamed")': \(error.localizedDescription)")
                        failedItems.append(
                            MigrationFailedItem(
                                id: fileID.uuidString,
                                name: fileName ?? "Unnamed",
                                error: "Failed to save: \(error.localizedDescription)"
                            )
                        )
                    }
                    
                case .failure(let error):
                    let fileName = await context.perform {
                        (self.context.object(with: objectID) as? File)?.name
                    }
                    logger.error("Failed processing file '\(fileName ?? "Unknown")': \(error)")
                    failedItems.append(
                        MigrationFailedItem(
                            id: objectID.uriRepresentation().absoluteString,
                            name: fileName ?? "Unknown",
                            error: error.localizedDescription
                        )
                    )
            }
            
            if waitingInterval > 0.02 {
                try await Task.sleep(nanoseconds: UInt64(waitingInterval * 1e+9))
            }
        }
        
        return failedItems
    }
    
    private func migrateCollaborationFiles(
        autoResolveErrors: Bool,
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws -> [MigrationFailedItem] {
        let fetchRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
        fetchRequest.predicate = NSPredicate(format: "filePath == nil AND content != nil")
        
        // 严重错误 - throw
        let collaborationFiles = try await context.perform {
            try self.context.fetch(fetchRequest)
        }
        
        guard !collaborationFiles.isEmpty else {
            logger.info("No collaboration files to migrate")
            return []
        }
        
        let waitingInterval: TimeInterval = 2 / Double(collaborationFiles.count)
        var failedItems: [MigrationFailedItem] = []
        
        logger.info("Migrating \(collaborationFiles.count) collaboration files to file storage")
        
        for (i, collaborationFile) in collaborationFiles.enumerated() {
            await progressHandler(
                "Migrating collaboration file '\(collaborationFile.name ?? String(localizable: .generalUntitled))'",
                Double(i) / Double(collaborationFiles.count)
            )
            
            let objectID = collaborationFile.objectID
            
            struct MigrationCollborationFileError: LocalizedError {
                var errorDescription: String?
            }
            
            // 处理单个文件 - 可恢复错误用Result
            let result = await context.perform { () -> Result<(content: Data, fileID: UUID, fileName: String?, updatedAt: Date?), Error> in
                guard let file = self.context.object(with: objectID) as? CollaborationFile else {
                    return .failure(MigrationCollborationFileError(errorDescription: "Collaboration file not found in context"))
                }
                guard let fileID = file.id else {
                    return .failure(MigrationCollborationFileError(errorDescription: "File ID is missing"))
                }
                
                var content = file.content
                if content == nil {
                    if autoResolveErrors {
                        content = ExcalidrawFile().content
                        file.content = content
                        do {
                            try self.context.save()
                            self.logger.info("Auto-resolved missing content for collaboration file: \(file.name ?? "Unnamed")")
                        } catch {
                            return .failure(
                                MigrationCollborationFileError(errorDescription: "Failed to save auto-resolved content: \(error.localizedDescription)")
                            )
                        }
                    } else {
                        return .failure(MigrationCollborationFileError(errorDescription: "Content is missing"))
                    }
                }
                
                return .success((content: content!, fileID: fileID, fileName: file.name, updatedAt: file.updatedAt))
            }
            
            switch result {
                case .success(let (content, fileID, fileName, updatedAt)):
                    do {
                        // Save to FileStorageManager
                        let relativePath = try await FileStorageManager.shared.saveContent(
                            content,
                            fileID: fileID.uuidString,
                            type: .collaborationFile,
                            updatedAt: updatedAt
                        )

                        // Update entity
                        try await context.perform {
                            guard let file = self.context.object(with: objectID) as? CollaborationFile else { return }
                            file.updateAfterSavingToStorage(filePath: relativePath)
                            try self.context.save()
                        }

                        logger.info("\(i+1)/\(collaborationFiles.count) | Migrated collaboration file: \(fileName ?? "Unnamed") → \(relativePath)")
                    } catch {
                        logger.error("Failed saving collaboration file '\(fileName ?? "Unnamed")': \(error.localizedDescription)")
                        failedItems.append(
                            MigrationFailedItem(
                                id: fileID.uuidString,
                                name: fileName ?? "Unnamed (Collaboration)",
                                error: "Failed to save: \(error.localizedDescription)"
                            )
                        )
                    }
                    
                case .failure(let error):
                    let fileName = await context.perform {
                        (self.context.object(with: objectID) as? CollaborationFile)?.name
                    }
                    logger.warning("Failed processing collaboration file '\(fileName ?? "Unknown")': \(error)")
                    failedItems.append(
                        MigrationFailedItem(
                            id: objectID.uriRepresentation().absoluteString,
                            name: fileName ?? "Unknown (Collaboration)",
                            error: error.localizedDescription
                        )
                    )
            }
            
            if waitingInterval > 0.02 {
                try await Task.sleep(nanoseconds: UInt64(waitingInterval * 1e+9))
            }
        }
        
        return failedItems
    }
    
    private func migrateMediaItems(
        autoResolveErrors: Bool,
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws -> [MigrationFailedItem] {
        let fetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
        fetchRequest.predicate = NSPredicate(format: "filePath == nil AND dataURL != nil")
        
        // 严重错误 - throw
        let mediaItems = try await context.perform {
            try self.context.fetch(fetchRequest)
        }
        
        guard !mediaItems.isEmpty else {
            logger.info("No media items to migrate")
            return []
        }
        
        let waitingInterval: TimeInterval = 2 / Double(mediaItems.count)
        var failedItems: [MigrationFailedItem] = []
        
        logger.info("Migrating \(mediaItems.count) media items to file storage")
        
        for (i, mediaItem) in mediaItems.enumerated() {
            await progressHandler(
                "Migrating media item",
                Double(i) / Double(mediaItems.count)
            )
            
            let objectID = mediaItem.objectID
            
            struct MigrationMediaItemError: LocalizedError {
                var errorDescription: String?
            }
            
            // 处理单个媒体项 - 可恢复错误用Result (注意：MediaItem 无 auto-resolve)
            let result = await context.perform { () -> Result<(dataURL: String, mediaID: String, updatedAt: Date?), Error> in
                guard let mediaItem = self.context.object(with: objectID) as? MediaItem else {
                    return .failure(MigrationMediaItemError(errorDescription: "Media item not found in context"))
                }
                guard let dataURL = mediaItem.dataURL else {
                    return .failure(MigrationMediaItemError(errorDescription: "dataURL is missing"))
                }
                guard let mediaID = mediaItem.id else {
                    return .failure(MigrationMediaItemError(errorDescription: "Media ID is missing"))
                }
                let timestamp = mediaItem.createdAt ?? Date()
                return .success((dataURL: dataURL, mediaID: mediaID, updatedAt: timestamp))
            }
            
            switch result {
                case .success(let (dataURL, mediaID, updatedAt)):
                    do {
                        // Save to FileStorageManager
                        let relativePath = try await FileStorageManager.shared.saveMediaItem(
                            dataURL: dataURL,
                            mediaID: mediaID,
                            updatedAt: updatedAt
                        )
                        
                        // Update entity
                        try await context.perform {
                            guard let mediaItem = self.context.object(with: objectID) as? MediaItem else {
                                return
                            }
                            mediaItem.updateAfterSavingToStorage(filePath: relativePath)
                            try self.context.save()
                        }
                        
                        logger.info("\(i+1)/\(mediaItems.count) | Migrated media item: \(mediaID) → \(relativePath)")
                    } catch {
                        logger.error("Failed saving media item \(mediaID): \(error.localizedDescription)")
                        failedItems.append(
                            MigrationFailedItem(
                                id: mediaID,
                                name: "Media: \(mediaID.prefix(8))",
                                error: "Failed to save: \(error.localizedDescription)"
                            )
                        )
                    }
                    
                case .failure(let error):
                    let mediaID = await context.perform {
                        (self.context.object(with: objectID) as? MediaItem)?.id
                    }
                    logger.error("Failed processing media item '\(mediaID ?? "Unknown")': \(error)")
                    failedItems.append(
                        MigrationFailedItem(
                            id: mediaID ?? objectID.uriRepresentation().absoluteString,
                            name: "Media: \(mediaID?.prefix(8) ?? "Unknown")",
                            error: error.localizedDescription
                        )
                    )
            }
            
            if waitingInterval > 0.02 {
                try await Task.sleep(nanoseconds: UInt64(waitingInterval * 1e+9))
            }
        }
        
        return failedItems
    }
    
    private func migrateCheckpoints(
        autoResolveErrors: Bool,
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws -> [MigrationFailedItem] {
        let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        fetchRequest.predicate = NSPredicate(format: "filePath == nil AND content != nil")
        
        // 严重错误 - throw
        let checkpoints = try await context.perform {
            try self.context.fetch(fetchRequest)
        }
        
        guard !checkpoints.isEmpty else {
            logger.info("No checkpoints to migrate")
            return []
        }
        
        let waitingInterval: TimeInterval = 2 / Double(checkpoints.count)
        var failedItems: [MigrationFailedItem] = []
        
        logger.info("Migrating \(checkpoints.count) checkpoints to file storage")
        
        for (i, checkpoint) in checkpoints.enumerated() {
            await progressHandler(
                "Migrating checkpoint",
                Double(i) / Double(checkpoints.count)
            )
            
            let objectID = checkpoint.objectID
            
            
            struct MigrationCheckpointError: LocalizedError {
                var errorDescription: String?
            }
            
            // 处理单个检查点 - 可恢复错误用Result
            let result = await context.perform { () -> Result<(content: Data, checkpointID: UUID, updatedAt: Date?), Error> in
                guard let checkpoint = self.context.object(with: objectID) as? FileCheckpoint else {
                    return .failure(MigrationCheckpointError(errorDescription: "Checkpoint not found in context"))
                }
                guard let checkpointID = checkpoint.id else {
                    return .failure(MigrationCheckpointError(errorDescription: "Checkpoint ID is missing"))
                }
                
                var content = checkpoint.content
                if content == nil {
                    if autoResolveErrors {
                        content = ExcalidrawFile().content
                        checkpoint.content = content
                        do {
                            try self.context.save()
                            self.logger.info("Auto-resolved missing content for checkpoint: \(checkpointID)")
                        } catch {
                            return .failure(MigrationCheckpointError(errorDescription: "Failed to save auto-resolved content: \(error.localizedDescription)"))
                        }
                    } else {
                        return .failure(MigrationCheckpointError(errorDescription: "Content is missing"))
                    }
                }
                
                return .success((content: content!, checkpointID: checkpointID, updatedAt: checkpoint.updatedAt))
            }
            
            switch result {
                case .success(let (content, checkpointID, updatedAt)):
                    do {
                        // Save to FileStorageManager
                        let relativePath = try await FileStorageManager.shared.saveContent(
                            content,
                            fileID: checkpointID.uuidString,
                            type: .checkpoint,
                            updatedAt: updatedAt
                        )
                        
                        // Update entity
                        try await context.perform {
                            guard let checkpoint = self.context.object(with: objectID) as? FileCheckpoint
                            else { return }
                            checkpoint.updateAfterSavingToStorage(filePath: relativePath)
                            try self.context.save()
                        }
                        
                        logger.info("\(i+1)/\(checkpoints.count) | Migrated checkpoint: \(checkpointID) → \(relativePath)")
                    } catch {
                        logger.error("Failed saving checkpoint \(checkpointID): \(error.localizedDescription)")
                        failedItems.append(
                            MigrationFailedItem(
                                id: checkpointID.uuidString,
                                name: "Checkpoint: \(checkpointID.uuidString.prefix(8))",
                                error: "Failed to save: \(error.localizedDescription)"
                            )
                        )
                    }
                    
                case .failure(let error):
                    let checkpointID = await context.perform {
                        (self.context.object(with: objectID) as? FileCheckpoint)?.id
                    }
                    logger.error("Failed processing checkpoint '\(checkpointID?.uuidString ?? "Unknown")': \(error)")
                    failedItems.append(
                        MigrationFailedItem(
                            id: checkpointID?.uuidString ?? objectID.uriRepresentation().absoluteString,
                            name: "Checkpoint: \(checkpointID?.uuidString.prefix(8) ?? "Unknown")",
                            error: error.localizedDescription
                        )
                    )
            }
            
            if waitingInterval > 0.02 {
                try await Task.sleep(nanoseconds: UInt64(waitingInterval * 1e+9))
            }
        }
        
        return failedItems
    }
}
