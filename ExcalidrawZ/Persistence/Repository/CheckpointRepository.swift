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
    private let encryptedCheckpointContentType = "fileCheckpoint"

    private struct RawCheckpointContentSnapshot {
        let objectID: NSManagedObjectID
        let checkpointID: UUID
        let fileObjectID: NSManagedObjectID?
        let filePath: String?
        let content: Data?
        let updatedAt: Date?
        let fileName: String?
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
        let context = PersistenceController.shared.newTaskContext()

        // Create checkpoint entity with content as fallback
        let checkpointObjectID = try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }

            let checkpoint = FileCheckpoint(context: context)
            checkpoint.id = UUID()
            checkpoint.content = content
            checkpoint.filename = filename
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
            checkpoint.filename = filename
            checkpoint.updatedAt = .now

            try context.save()

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
        let context = PersistenceController.shared.newTaskContext()

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
        let context = PersistenceController.shared.newTaskContext()

        // Extract checkpoint info before deletion
        let (filePath, checkpointID): (String?, UUID?) = try await context.perform {
            guard let checkpoint = context.object(with: checkpointObjectID) as? FileCheckpoint else {
                return (nil, nil)
            }
            let path = checkpoint.filePath
            let id = checkpoint.id

            // Delete database record first
            context.delete(checkpoint)
            try context.save()

            return (path, id)
        }

        // Delete physical file from storage (local + iCloud)
        if let relativePath = filePath, let fileID = checkpointID {
            do {
                try await FileStorageManager.shared.deleteContent(relativePath: relativePath, fileID: fileID.uuidString)
            } catch {
                // Log but don't throw - database record is already deleted
                logger.warning("Failed to delete checkpoint file from storage: \(error)")
            }
        }
    }

    // MARK: - Save Checkpoint

    /// Save checkpoint content to storage (local + auto iCloud sync)
    /// - Parameter checkpointObjectID: The checkpoint objectID
    func saveCheckpointToStorage(checkpointObjectID: NSManagedObjectID) async throws {
        try await saveCheckpointToStorage(
            checkpointObjectID: checkpointObjectID,
            recoveryKeyOverride: nil,
            forceProtected: false
        )
    }

    func saveCheckpointContentToStorage(
        checkpointObjectID: NSManagedObjectID,
        content: Data,
        updateMetadataWhenPathUnchanged: Bool = true
    ) async throws {
        let contentUpdatedAt = Date()
        let snapshot = try await rawCheckpointContentSnapshot(checkpointObjectID: checkpointObjectID)
        let contentToSave = try await encryptedCheckpointContentIfNeeded(
            content,
            snapshot: snapshot,
            recoveryKeyOverride: nil,
            forceProtected: false
        )
        try await saveRawCheckpointContentToStorage(
            snapshot: snapshot,
            content: contentToSave,
            updateMetadataWhenPathUnchanged: updateMetadataWhenPathUnchanged,
            updatedAtOverride: contentUpdatedAt
        )
    }

    func saveNewCheckpointContentToStorage(
        content: Data,
        checkpointID: UUID,
        fileObjectID: NSManagedObjectID?,
        updatedAt: Date?
    ) async throws -> String {
        let contentToSave = try await encryptedCheckpointContentIfNeeded(
            content,
            checkpointID: checkpointID,
            fileObjectID: fileObjectID,
            existingFilePath: nil,
            recoveryKeyOverride: nil,
            forceProtected: false
        )
        let relativePath = try await FileStorageManager.shared.saveContent(
            contentToSave,
            fileID: checkpointID.uuidString,
            type: .checkpoint,
            updatedAt: updatedAt
        )
        logger.debug("Saved checkpoint to storage: \(relativePath)")
        return relativePath
    }

    func encryptCheckpoints(
        for fileObjectID: NSManagedObjectID,
        recoveryKey: RecoveryKey
    ) async throws {
        let checkpointObjectIDs = try await checkpointObjectIDs(for: fileObjectID)
        for (index, checkpointObjectID) in checkpointObjectIDs.enumerated() {
            try await checkpointBatchCheckpoint(index)
            try await saveCheckpointToStorage(
                checkpointObjectID: checkpointObjectID,
                recoveryKeyOverride: recoveryKey,
                forceProtected: true
            )
        }
    }

    func removeCheckpointLocks(for fileObjectID: NSManagedObjectID) async throws {
        let checkpointObjectIDs = try await checkpointObjectIDs(for: fileObjectID)
        var unlockedCheckpoints: [(snapshot: RawCheckpointContentSnapshot, content: Data)] = []

        for (index, checkpointObjectID) in checkpointObjectIDs.enumerated() {
            try await checkpointBatchCheckpoint(index)
            let snapshot = try await rawCheckpointContentSnapshot(checkpointObjectID: checkpointObjectID)
            let rawContent = try await loadRawCheckpointContent(from: snapshot, preferFallbackContent: false)
            guard EncryptedContentService.isEncryptedEnvelope(rawContent) else {
                continue
            }

            let plaintext = try await LockedContentUnlockSession.shared.decrypt(
                rawContent,
                expectedContentType: encryptedCheckpointContentType,
                expectedContentID: snapshot.checkpointID.uuidString
            )
            unlockedCheckpoints.append((snapshot, plaintext))
        }

        for (index, checkpoint) in unlockedCheckpoints.enumerated() {
            try await checkpointBatchCheckpoint(index)
            try await savePlainCheckpointContentToStorage(
                snapshot: checkpoint.snapshot,
                content: checkpoint.content
            )
        }
    }

    func rewrapCheckpointsRecoveryKey(
        for fileObjectID: NSManagedObjectID,
        newRecoveryKey: RecoveryKey
    ) async throws {
        let checkpointObjectIDs = try await checkpointObjectIDs(for: fileObjectID)
        var rewrappedCheckpoints: [(snapshot: RawCheckpointContentSnapshot, content: Data)] = []

        for (index, checkpointObjectID) in checkpointObjectIDs.enumerated() {
            try await checkpointBatchCheckpoint(index)
            let snapshot = try await rawCheckpointContentSnapshot(checkpointObjectID: checkpointObjectID)
            let rawContent = try await loadRawCheckpointContent(from: snapshot, preferFallbackContent: false)
            guard EncryptedContentService.isEncryptedEnvelope(rawContent) else {
                continue
            }

            let rewrappedContent = try await LockedContentUnlockSession.shared.rewrapRecoveryKey(
                existingEnvelopeData: rawContent,
                newRecoveryKey: newRecoveryKey,
                expectedContentType: encryptedCheckpointContentType,
                expectedContentID: snapshot.checkpointID.uuidString
            )
            rewrappedCheckpoints.append((snapshot, rewrappedContent))
        }

        for (index, checkpoint) in rewrappedCheckpoints.enumerated() {
            try await checkpointBatchCheckpoint(index)
            try await saveRawCheckpointContentToStorage(
                snapshot: checkpoint.snapshot,
                content: checkpoint.content
            )
        }
    }

    func validateCheckpointsCanRewrapRecoveryKey(
        for fileObjectID: NSManagedObjectID,
        newRecoveryKey: RecoveryKey
    ) async throws {
        let checkpointObjectIDs = try await checkpointObjectIDs(for: fileObjectID)
        for (index, checkpointObjectID) in checkpointObjectIDs.enumerated() {
            try await checkpointBatchCheckpoint(index)
            let snapshot = try await rawCheckpointContentSnapshot(checkpointObjectID: checkpointObjectID)
            let rawContent = try await loadRawCheckpointContent(from: snapshot, preferFallbackContent: false)
            guard EncryptedContentService.isEncryptedEnvelope(rawContent) else {
                continue
            }

            _ = try await LockedContentUnlockSession.shared.rewrapRecoveryKey(
                existingEnvelopeData: rawContent,
                newRecoveryKey: newRecoveryKey,
                expectedContentType: encryptedCheckpointContentType,
                expectedContentID: snapshot.checkpointID.uuidString
            )
        }
    }

    private func checkpointBatchCheckpoint(_ index: Int) async throws {
        try Task.checkCancellation()
        if index > 0, index.isMultiple(of: 10) {
            await Task.yield()
        }
    }

    private func saveCheckpointToStorage(
        checkpointObjectID: NSManagedObjectID,
        recoveryKeyOverride: RecoveryKey?,
        forceProtected: Bool
    ) async throws {
        let snapshot = try await rawCheckpointContentSnapshot(checkpointObjectID: checkpointObjectID)
        let content = try await loadRawCheckpointContent(from: snapshot, preferFallbackContent: true)
        let contentToSave = try await encryptedCheckpointContentIfNeeded(
            content,
            snapshot: snapshot,
            recoveryKeyOverride: recoveryKeyOverride,
            forceProtected: forceProtected
        )
        try await saveRawCheckpointContentToStorage(snapshot: snapshot, content: contentToSave)
    }

    private func checkpointObjectIDs(for fileObjectID: NSManagedObjectID) async throws -> [NSManagedObjectID] {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }
            let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetchRequest.predicate = NSPredicate(format: "file == %@", file)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: true)]
            return try context.fetch(fetchRequest).map(\.objectID)
        }
    }

    private func rawCheckpointContentSnapshot(
        checkpointObjectID: NSManagedObjectID
    ) async throws -> RawCheckpointContentSnapshot {
        let context = PersistenceController.shared.newTaskContext()
        return try await context.perform {
            guard let checkpoint = context.object(with: checkpointObjectID) as? FileCheckpoint else {
                throw AppError.fileError(.notFound)
            }
            guard let checkpointID = checkpoint.id else {
                throw FileCheckpointError.missingID
            }
            return RawCheckpointContentSnapshot(
                objectID: checkpoint.objectID,
                checkpointID: checkpointID,
                fileObjectID: checkpoint.file?.objectID,
                filePath: checkpoint.filePath,
                content: checkpoint.content,
                updatedAt: checkpoint.updatedAt,
                fileName: checkpoint.file?.name
            )
        }
    }

    private func loadRawCheckpointContent(
        from snapshot: RawCheckpointContentSnapshot,
        preferFallbackContent: Bool
    ) async throws -> Data {
        if preferFallbackContent, let content = snapshot.content {
            return content
        }

        if let filePath = snapshot.filePath {
            do {
                return try await FileStorageManager.shared.loadContent(
                    relativePath: filePath,
                    fileID: snapshot.checkpointID.uuidString
                )
            } catch {
                logger.warning("Failed to load checkpoint content from storage: \(error.localizedDescription). Falling back to CoreData.")
            }
        }

        if let content = snapshot.content {
            return content
        }

        throw AppError.fileError(.contentNotAvailable(filename: snapshot.fileName ?? String(localizable: .generalUnknown)))
    }

    private func encryptedCheckpointContentIfNeeded(
        _ content: Data,
        snapshot: RawCheckpointContentSnapshot,
        recoveryKeyOverride: RecoveryKey?,
        forceProtected: Bool
    ) async throws -> Data {
        try await encryptedCheckpointContentIfNeeded(
            content,
            checkpointID: snapshot.checkpointID,
            fileObjectID: snapshot.fileObjectID,
            existingFilePath: snapshot.filePath,
            recoveryKeyOverride: recoveryKeyOverride,
            forceProtected: forceProtected
        )
    }

    private func encryptedCheckpointContentIfNeeded(
        _ content: Data,
        checkpointID: UUID,
        fileObjectID: NSManagedObjectID?,
        existingFilePath: String?,
        recoveryKeyOverride: RecoveryKey?,
        forceProtected: Bool
    ) async throws -> Data {
        let contentID = checkpointID.uuidString

        if EncryptedContentService.isEncryptedEnvelope(content) {
            let envelope = try EncryptedContentService.decodeEnvelope(content)
            guard envelope.contentType == encryptedCheckpointContentType,
                  envelope.contentID == contentID else {
                throw EncryptedContentError.contentIdentityMismatch(
                    expectedType: encryptedCheckpointContentType,
                    expectedID: contentID,
                    actualType: envelope.contentType,
                    actualID: envelope.contentID
                )
            }
            return content
        }

        if let existingEncryptedContent = try await existingEncryptedCheckpointContent(
            filePath: existingFilePath,
            checkpointID: checkpointID
        ) {
            return try await LockedContentUnlockSession.shared.resealPayload(
                content,
                existingEnvelopeData: existingEncryptedContent,
                expectedContentType: encryptedCheckpointContentType,
                expectedContentID: contentID
            )
        }

        let shouldProtect = if forceProtected {
            true
        } else {
            try await fileIsProtected(fileObjectID)
        }
        guard shouldProtect else {
            return content
        }

        let recoveryKey: RecoveryKey
        if let recoveryKeyOverride {
            recoveryKey = recoveryKeyOverride
        } else if let currentRecoveryKey = await RecoveryKeyVault.shared.currentRecoveryKey() {
            recoveryKey = currentRecoveryKey
        } else {
            throw EncryptedContentError.contentLocked(
                contentType: encryptedCheckpointContentType,
                contentID: contentID
            )
        }

        return try EncryptedContentService.encryptAndVerifyRecovery(
            content,
            contentType: encryptedCheckpointContentType,
            contentID: contentID,
            recoveryKey: recoveryKey
        )
    }

    private func existingEncryptedCheckpointContent(
        filePath: String?,
        checkpointID: UUID
    ) async throws -> Data? {
        guard let filePath else {
            return nil
        }
        do {
            let existingContent = try await FileStorageManager.shared.loadContent(
                relativePath: filePath,
                fileID: checkpointID.uuidString
            )
            return EncryptedContentService.isEncryptedEnvelope(existingContent) ? existingContent : nil
        } catch {
            logger.warning("Failed to inspect existing checkpoint content before save: \(error.localizedDescription).")
            return nil
        }
    }

    private func fileIsProtected(_ fileObjectID: NSManagedObjectID?) async throws -> Bool {
        guard let fileObjectID else { return false }
        return try await PersistenceController.shared.fileRepository
            .isFileContentProtected(fileObjectID: fileObjectID)
    }

    private func saveRawCheckpointContentToStorage(
        snapshot: RawCheckpointContentSnapshot,
        content: Data,
        updateMetadataWhenPathUnchanged: Bool = true,
        updatedAtOverride: Date? = nil
    ) async throws {
        let relativePath = try await FileStorageManager.shared.saveContent(
            content,
            fileID: snapshot.checkpointID.uuidString,
            type: .checkpoint,
            updatedAt: updatedAtOverride ?? snapshot.updatedAt
        )

        let context = PersistenceController.shared.newTaskContext()
        let didUpdateMetadata = try await context.perform {
            guard let checkpoint = context.object(with: snapshot.objectID) as? FileCheckpoint else { return false }
            if !updateMetadataWhenPathUnchanged,
               checkpoint.filePath == relativePath,
               checkpoint.content == nil {
                return false
            }
            checkpoint.updateAfterSavingToStorage(filePath: relativePath)
            if let updatedAtOverride {
                checkpoint.updatedAt = updatedAtOverride
            }
            try context.save()
            return true
        }
        if didUpdateMetadata {
            logger.debug("Saved checkpoint to storage: \(relativePath)")
        } else {
            logger.debug("Saved checkpoint to storage without CoreData metadata update: \(relativePath)")
        }
    }

    private func savePlainCheckpointContentToStorage(
        snapshot: RawCheckpointContentSnapshot,
        content: Data
    ) async throws {
        try await saveRawCheckpointContentToStorage(snapshot: snapshot, content: content)
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

        let context = PersistenceController.shared.newTaskContext()

        // Update file with checkpoint content in CoreData
        // Note: Caller is responsible for saving the file to storage if needed
        // by calling FileRepository.saveFileContentToStorage(fileObjectID:)
        try await context.perform {
            guard let file = context.object(with: fileObjectID) as? File,
                  let checkpoint = context.object(with: checkpointObjectID) as? FileCheckpoint else {
                throw AppError.fileError(.notFound)
            }

            file.content = content
            file.name = checkpoint.filename
            file.updatedAt = .now

            try context.save()
        }
    }
}

/// Provider-neutral history for Cloud Storage documents. Checkpoint payloads
/// remain device-managed just like Linked Folder history; provider APIs only
/// synchronize the current document and are not treated as the history SoT.
enum CloudStorageCheckpointStore {
    static func recordUserEdit(
        content: Data,
        for reference: CloudStorageDocumentReference,
        newCheckpoint: Bool
    ) async throws {
        try await LocalFileCheckpointStore.recordUserEdit(
            content: content,
            for: reference.checkpointURL,
            newCheckpoint: newCheckpoint
        )
    }

    @discardableResult
    static func record(
        content: Data,
        for reference: CloudStorageDocumentReference,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> UUID {
        let checkpointURL = reference.checkpointURL
        let context = PersistenceController.shared.container.newBackgroundContext()
        return try await context.perform {
            let checkpoint = LocalFileCheckpoint(context: context)
            let checkpointID = UUID()
            checkpoint.id = checkpointID
            checkpoint.url = checkpointURL
            checkpoint.updatedAt = .now
            checkpoint.content = content
            checkpoint.source = source.rawValue
            checkpoint.historyDescription = description
            context.insert(checkpoint)
            try context.save()
            return checkpointID
        }
    }

    static func migrateIdentities(
        _ change: CloudStorageItemIdentityChange
    ) async throws {
        let migrations = change.replacements.compactMap { oldItemID, item -> (URL, URL)? in
            guard oldItemID != item.id else { return nil }
            return (
                CloudStorageDocumentReference.checkpointURL(
                    locationID: change.location.id,
                    itemID: oldItemID
                ),
                CloudStorageDocumentReference.checkpointURL(
                    locationID: change.location.id,
                    itemID: item.id
                )
            )
        }
        guard !migrations.isEmpty else { return }

        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            for (oldURL, newURL) in migrations {
                let request: NSFetchRequest<LocalFileCheckpoint> = LocalFileCheckpoint.fetchRequest()
                request.predicate = NSPredicate(format: "url == %@", oldURL as NSURL)
                try context.fetch(request).forEach { $0.url = newURL }
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }

    static func deleteCheckpoints(
        for references: [CloudStorageDocumentReference]
    ) async throws {
        let checkpointURLs = references.map { $0.checkpointURL as NSURL }
        guard !checkpointURLs.isEmpty else { return }

        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<LocalFileCheckpoint> = LocalFileCheckpoint.fetchRequest()
            request.predicate = NSPredicate(format: "url IN %@", checkpointURLs)
            try context.fetch(request).forEach { context.delete($0) }
            if context.hasChanges {
                try context.save()
            }
        }
    }
}
