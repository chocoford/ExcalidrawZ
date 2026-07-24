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
                logger.debug("Saved media item to storage: \(relativePath)")
            } catch {
                logger.warning("Failed to save media item to iCloud Drive: \(error.localizedDescription)")
                continue
            }
        }

        return (fileObjectID, mediaItemPairs)
    }

    // MARK: - Update File

    /// Update file elements with new data and write a checkpoint per the
    /// supplied policy.
    ///
    /// The `checkpoint` parameter replaces the older `newCheckpoint: Bool`
    /// argument. Three modes:
    ///
    /// - `.suppress` — content saves to storage and Core Data, but **no**
    ///   FileCheckpoint row is touched. Used during AI-chat sessions where
    ///   all canvas mutations must NOT pollute user history.
    /// - `.userEdit(newCheckpoint:)` — the historical "first edit creates,
    ///   subsequent edits update latest" semantic, plus the latest-update
    ///   path now ignores AI-tagged rows so it can't accidentally overwrite
    ///   an `ai_pre` / `ai_post` snapshot.
    /// - `.explicit(...)` — force-create a checkpoint with explicit
    ///   source / description fields. Used by the AI session begin/end
    ///   hooks. Message ownership is stored in `AIMessageCheckpointLink`.
    func updateElements(
        fileObjectID: NSManagedObjectID,
        fileData: Data,
        checkpoint: CheckpointWriteOptions,
        updateMetadataWhenPathUnchanged: Bool = true
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        let contentData = try await prepareContentDataForUpdate(
            fileObjectID: fileObjectID,
            fileData: fileData,
            context: context
        )

        try await saveFileContentToStorage(
            fileObjectID: fileObjectID,
            content: contentData,
            updateMetadataWhenPathUnchanged: updateMetadataWhenPathUnchanged
        )

        // Step 2: Write checkpoint per policy.
        switch checkpoint {
        case .suppress:
            // Caller is in an AI chat session — content saved, history skipped.
            return

        case .userEdit(let newCheckpoint):
            if newCheckpoint {
                self.logger.info("Creating new user checkpoint for file")
                _ = try await createCheckpoint(
                    fileObjectID: fileObjectID,
                    content: contentData,
                    source: .user,
                    description: nil
                )
            } else {
                try await updateLatestUserCheckpoint(
                    fileObjectID: fileObjectID,
                    content: contentData
                )
            }

        case .explicit(let source, let description):
            self.logger.info("Creating explicit \(source.rawValue) checkpoint for file")
            _ = try await createCheckpoint(
                fileObjectID: fileObjectID,
                content: contentData,
                source: source,
                description: description
            )
        }
    }

    private func prepareContentDataForUpdate(
        fileObjectID: NSManagedObjectID,
        fileData: Data,
        context: NSManagedObjectContext
    ) async throws -> Data {
        guard var fileDataJson = try JSONSerialization.jsonObject(with: fileData) as? [String : Any] else {
            let fileName = await context.perform {
                (context.object(with: fileObjectID) as? File)?.name
            }
            throw AppError.fileError(.contentNotAvailable(filename: fileName ?? String(localizable: .generalUnknown)))
        }

        if Self.isCompleteExcalidrawFileContent(fileDataJson) {
            fileDataJson.removeValue(forKey: "files")
            return try JSONSerialization.data(withJSONObject: fileDataJson)
        }

        // Legacy callers may still pass only the canvas payload. In that case
        // preserve the existing file envelope and replace the scene fields.
        let file = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }
            return file
        }
        let data = try await file.loadContent()
        var contentObject = try JSONSerialization.jsonObject(with: data) as! [String : Any]
        contentObject["elements"] = fileDataJson["elements"]
        contentObject["appState"] = fileDataJson["appState"]
        contentObject.removeValue(forKey: "files")
        return try JSONSerialization.data(withJSONObject: contentObject)
    }

    private static func isCompleteExcalidrawFileContent(_ object: [String : Any]) -> Bool {
        object["elements"] != nil
            && object["appState"] != nil
            && object["type"] != nil
            && object["version"] != nil
    }

    /// Force-write an explicitly tagged checkpoint for the current state of a
    /// file without going through the elements-update path. Used by automated
    /// integrations such as AI chat and MCP to create precise pre/post
    /// rollback anchors. This bypasses the "first edit creates, subsequent
    /// updates" semantics — every call creates a fresh row tagged with the
    /// supplied metadata.
    func recordCheckpoint(
        fileObjectID: NSManagedObjectID,
        content: Data,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> UUID {
        return try await createCheckpoint(
            fileObjectID: fileObjectID,
            content: content,
            source: source,
            description: description
        )
    }

    /// Save file content to storage (local + auto iCloud sync)
    /// - Parameters:
    ///   - fileObjectID: The file objectID
    ///   - content: The content data to save
    func saveFileContentToStorage(
        fileObjectID: NSManagedObjectID,
        content: Data,
        updateMetadataWhenPathUnchanged: Bool = true
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        // Step 1: Get file ID and metadata
        let (fileID, existingFilePath, updatedAt) = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }
            guard let fileID = file.id else {
                throw AppError.fileError(.contentNotAvailable(filename: file.name ?? String(localizable: .generalUnknown)))
            }
            return (fileID, file.filePath, file.updatedAt)
        }

        let contentToSave = try await encryptedContentIfNeeded(
            content,
            existingFilePath: existingFilePath,
            fileID: fileID
        )

        // Step 2: Save to storage (local + iCloud sync)
        let relativePath = try await FileStorageManager.shared.saveContent(
            contentToSave,
            fileID: fileID.uuidString,
            type: .file,
            updatedAt: updatedAt
        )

        // Step 3: Update after successful save
        let didUpdateMetadata = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else { return false }
            if !updateMetadataWhenPathUnchanged,
               file.filePath == relativePath,
               file.content == nil {
                return false
            }
            file.updateAfterSavingToStorage(filePath: relativePath)
            try context.save()
            return true
        }
        if didUpdateMetadata {
            logger.debug("Saved file to storage: \(relativePath)")
            await PersistenceController.shared.spotlightIndexingService.indexFile(fileObjectID: fileObjectID)
        } else {
            logger.debug("Saved file to storage without CoreData metadata update: \(relativePath)")
        }
    }

    private func saveFileContentFallback(
        fileObjectID: NSManagedObjectID,
        content: Data
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()
        try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else { return }
            file.updateContentFallback(data: content)
            try context.save()
        }
    }

    private func encryptedContentIfNeeded(
        _ content: Data,
        existingFilePath: String?,
        fileID: UUID
    ) async throws -> Data {
        let contentID = fileID.uuidString

        if EncryptedContentService.isEncryptedEnvelope(content) {
            let envelope = try EncryptedContentService.decodeEnvelope(content)
            guard envelope.contentType == "file", envelope.contentID == contentID else {
                throw EncryptedContentError.contentIdentityMismatch(
                    expectedType: "file",
                    expectedID: contentID,
                    actualType: envelope.contentType,
                    actualID: envelope.contentID
                )
            }
            return content
        }

        guard let existingFilePath else {
            return content
        }

        let existingContent: Data
        do {
            existingContent = try await FileStorageManager.shared.loadContent(
                relativePath: existingFilePath,
                fileID: contentID
            )
        } catch {
            logger.warning("Failed to inspect existing file content before save: \(error.localizedDescription). Saving plain content.")
            return content
        }

        guard EncryptedContentService.isEncryptedEnvelope(existingContent) else {
            return content
        }

        return try await LockedContentUnlockSession.shared.resealPayload(
            content,
            existingEnvelopeData: existingContent,
            expectedContentType: "file",
            expectedContentID: contentID
        )
    }

    /// Create a new checkpoint for the file with explicit metadata.
    /// Source/description default to user-edit semantics when the call
    /// site is the historical user-edit path.
    private func createCheckpoint(
        fileObjectID: NSManagedObjectID,
        content: Data,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> UUID {
        let context = PersistenceController.shared.newTaskContext()

        let (checkpointID, checkpointUpdatedAt) = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }

            let checkpoint = FileCheckpoint(context: context)
            let checkpointID = UUID()
            checkpoint.id = checkpointID
            checkpoint.filename = file.name
            checkpoint.updatedAt = .now
            // New AI-history fields. For pure user edits we still write
            // `source = "user"` (instead of leaving nil) so query predicates
            // can match either nil-as-legacy or explicit "user" uniformly
            // via OR clauses.
            checkpoint.source = source.rawValue
            checkpoint.historyDescription = description
            file.addToCheckpoints(checkpoint)

            try context.save()

            // Clean up old checkpoints if needed
            if let checkpoints = try? PersistenceController.shared.fetchFileCheckpoints(of: file, viewContext: context),
               checkpoints.count > 50 {
                file.removeFromCheckpoints(checkpoints.last!)
            }

            return (checkpointID, checkpoint.updatedAt)
        }

        let relativePath = try await PersistenceController.shared.checkpointRepository
            .saveNewCheckpointContentToStorage(
                content: content,
                checkpointID: checkpointID,
                fileObjectID: fileObjectID,
                updatedAt: checkpointUpdatedAt
            )

        try await context.perform {
            let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetchRequest.predicate = NSPredicate(format: "id == %@", checkpointID as CVarArg)
            fetchRequest.fetchLimit = 1
            guard let checkpoint = try context.fetch(fetchRequest).first else {
                throw AppError.fileError(.notFound)
            }
            checkpoint.updateAfterSavingToStorage(filePath: relativePath)
            try context.save()
        }
        return checkpointID
    }

    /// Update the latest **user-source** checkpoint for the file. AI-tagged
    /// rows (`ai_pre` / `ai_post`) are immutable snapshots — they're meant
    /// to capture a specific moment in the AI conversation, so subsequent
    /// user edits must not overwrite their content. If no user checkpoint
    /// exists (e.g. the latest is an AI row), this falls back to creating
    /// a new user checkpoint.
    private func updateLatestUserCheckpoint(
        fileObjectID: NSManagedObjectID,
        content: Data
    ) async throws {
        let context = PersistenceController.shared.newTaskContext()

        struct LatestLookup {
            let foundUserCheckpoint: NSManagedObjectID?
            let shouldCreateNewCheckpoint: Bool
        }

        let lookup: LatestLookup = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                return LatestLookup(
                    foundUserCheckpoint: nil,
                    shouldCreateNewCheckpoint: true
                )
            }

            // Match user-source rows OR legacy rows (source == nil).
            // Anything tagged ai_pre / ai_post is excluded.
            let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetchRequest.predicate = NSPredicate(
                format: "file == %@ AND (source == nil OR source == %@)",
                file,
                FileCheckpointSource.user.rawValue
            )
            fetchRequest.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
            guard let checkpoint = try context.fetch(fetchRequest).first else {
                return LatestLookup(
                    foundUserCheckpoint: nil,
                    shouldCreateNewCheckpoint: true
                )
            }

            return LatestLookup(
                foundUserCheckpoint: checkpoint.objectID,
                shouldCreateNewCheckpoint: UserCheckpointRolloverPolicy.shouldCreateNewCheckpoint(
                    latestUpdatedAt: checkpoint.updatedAt
                )
            )
        }

        if let checkpointObjectID = lookup.foundUserCheckpoint,
           !lookup.shouldCreateNewCheckpoint {
            self.logger.info("Updating latest user checkpoint")
            try await PersistenceController.shared.checkpointRepository.saveCheckpointContentToStorage(
                checkpointObjectID: checkpointObjectID,
                content: content,
                updateMetadataWhenPathUnchanged: false
            )
        } else {
            // Start a new checkpoint when there is no user row to update,
            // or when the current editing run has exceeded the rollover
            // interval. This keeps long sessions from having a single
            // restore point that can be overwritten by a bad save.
            _ = try await createCheckpoint(
                fileObjectID: fileObjectID,
                content: content,
                source: .user,
                description: nil
            )
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

    private struct DeletedFileStorageInfo: Sendable {
        let relativePath: String
        let fileID: UUID
    }

    private struct DeletedCheckpointStorageInfo: Sendable {
        let relativePath: String
        let checkpointID: UUID
    }

    private struct FileDeletionSideEffects: Sendable {
        var files: [DeletedFileStorageInfo] = []
        var checkpoints: [DeletedCheckpointStorageInfo] = []
        var mediaObjectURIs: [URL] = []
        var spotlightFileIDs: [UUID] = []
        var fileScopeIDs: [String] = []
    }

    /// Delete multiple files in one Core Data transaction.
    ///
    /// This keeps multi-selection delete as an actual batch operation instead
    /// of repeatedly creating contexts and saving once per file.
    func delete(
        fileObjectIDs: [NSManagedObjectID],
        forcePermanently: Bool = false,
        save: Bool = true
    ) async throws {
        guard !fileObjectIDs.isEmpty else { return }

        let context = PersistenceController.shared.newTaskContext()

        let sideEffects: FileDeletionSideEffects = try await context.perform {
            var sideEffects = FileDeletionSideEffects()
            var checkpointObjectIDsToDelete: [NSManagedObjectID] = []

            for fileObjectID in fileObjectIDs {
                guard let file = context.object(with: fileObjectID) as? File else {
                    continue
                }

                if file.inTrash || forcePermanently {
                    let mediaItems = (file.medias?.allObjects as? [MediaItem]) ?? []
                    sideEffects.mediaObjectURIs.append(
                        contentsOf: mediaItems.map { $0.objectID.uriRepresentation() }
                    )

                    let checkpointsFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
                    checkpointsFetchRequest.predicate = NSPredicate(format: "file = %@", file)
                    let fileCheckpoints = try context.fetch(checkpointsFetchRequest)

                    for checkpoint in fileCheckpoints {
                        checkpointObjectIDsToDelete.append(checkpoint.objectID)
                        guard let path = checkpoint.filePath,
                              let id = checkpoint.id else { continue }
                        sideEffects.checkpoints.append(
                            DeletedCheckpointStorageInfo(
                                relativePath: path,
                                checkpointID: id
                            )
                        )
                    }

                    if let path = file.filePath,
                       let id = file.id {
                        sideEffects.files.append(
                            DeletedFileStorageInfo(
                                relativePath: path,
                                fileID: id
                            )
                        )
                    }

                    if let id = file.id {
                        sideEffects.spotlightFileIDs.append(id)
                        sideEffects.fileScopeIDs.append(id.uuidString)
                    } else {
                        sideEffects.fileScopeIDs.append(file.objectID.uriRepresentation().absoluteString)
                    }

                    context.delete(file)
                } else {
                    if let id = file.id {
                        sideEffects.spotlightFileIDs.append(id)
                    }
                    file.inTrash = true
                    file.deletedAt = .now
                }
            }

            if !checkpointObjectIDsToDelete.isEmpty {
                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: checkpointObjectIDsToDelete)
                try context.executeAndMergeChanges(using: batchDeleteRequest)
            }

            if save {
                try context.save()
            }

            return sideEffects
        }

        await runDeletionSideEffects(sideEffects)
    }

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
        try await delete(
            fileObjectIDs: [fileObjectID],
            forcePermanently: forcePermanently,
            save: save
        )
    }

    private func runDeletionSideEffects(_ sideEffects: FileDeletionSideEffects) async {
        for spotlightFileID in sideEffects.spotlightFileIDs {
            await PersistenceController.shared.spotlightIndexingService.deleteFile(id: spotlightFileID)
        }

        for checkpoint in sideEffects.checkpoints {
            do {
                try await FileStorageManager.shared.deleteContent(
                    relativePath: checkpoint.relativePath,
                    fileID: checkpoint.checkpointID.uuidString
                )
            } catch {
                logger.warning("Failed to delete checkpoint file from storage: \(error)")
            }
        }

        for file in sideEffects.files {
            do {
                try await FileStorageManager.shared.deleteContent(
                    relativePath: file.relativePath,
                    fileID: file.fileID.uuidString
                )
            } catch {
                logger.warning("Failed to delete file from storage: \(error)")
            }
        }

        for fileScopeID in sideEffects.fileScopeIDs {
            let scope = AIConversationFileScope(
                kind: .libraryFile,
                id: fileScopeID
            )
            do {
                try await PersistenceController.shared.aiConversationRepository
                    .deleteConversations(
                        forFileScope: scope
                    )
                await AIChatPreferences.shared.deleteFileAccessOverride(for: scope)
            } catch {
                logger.warning("Failed to delete AI conversations for file \(fileScopeID): \(error)")
            }
        }

        do {
            let deletedMediaCount = try await MediaCleanupCoordinator.shared.cleanOrphanedMedia(
                withObjectURIs: sideEffects.mediaObjectURIs
            )
            if deletedMediaCount > 0 {
                logger.debug("Deleted \(deletedMediaCount) unreferenced media item(s) after permanent file deletion")
            }
        } catch {
            logger.warning("Failed to clean media after permanent file deletion: \(error)")
        }
    }
}
