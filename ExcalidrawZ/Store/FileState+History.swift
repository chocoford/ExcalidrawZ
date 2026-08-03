//
//  FileState+History.swift
//  ExcalidrawZ
//
//  Shared file-history restore helpers.
//

import Foundation
import CoreData

extension Notification.Name {
    static let activeCanvasFileDidRestore = Notification.Name("ActiveCanvasFileDidRestore")
}

extension FileState {
    @MainActor
    func restoreActiveCanvas(
        fromCheckpointContent content: Data,
        filename: String?
    ) async throws {
        switch currentActiveFile {
            case .file(let file):
                let activeFile = ActiveFile.file(file)
                var restoredFile = try ExcalidrawFile(data: content, id: activeFile.id)
                restoredFile.name = filename ?? file.name

                try await PersistenceController.shared.fileRepository.saveFileContentToStorage(
                    fileObjectID: file.objectID,
                    content: content
                )
                try saveRestoredLibraryFileMetadata(
                    file,
                    filename: filename
                )
                do {
                    _ = try await PersistenceController.shared.fileRepository.recordCheckpoint(
                        fileObjectID: file.objectID,
                        content: content,
                        source: .restorePost,
                        description: nil
                    )
                } catch {
                    logger.warning("Failed to record restore checkpoint for \(activeFile.id): \(error.localizedDescription)")
                }

                guard currentActiveFile?.id == activeFile.id else { return }
                await excalidrawWebCoordinator?.loadFile(from: restoredFile, force: true)
                NotificationCenter.default.post(
                    name: .activeCanvasFileDidRestore,
                    object: restoredFile
                )

            case .localFile(let fileURL):
                guard case .localFolder(let folder) = currentActiveGroup else {
                    throw AIChatEditError.unsupportedFile
                }

                let activeFile = ActiveFile.localFile(fileURL)
                let parsedFile = try ExcalidrawFile(data: content, id: activeFile.id)

                try await folder.withSecurityScopedURL { _ in
                    try await FileCoordinator.shared.coordinatedWrite(url: fileURL, data: content)
                    Self.touchLocalFileModificationDate(fileURL, logger: self.logger)
                }
                do {
                    try await recordLocalRestoreCheckpoint(
                        url: fileURL,
                        content: content
                    )
                } catch {
                    logger.warning("Failed to record local restore checkpoint for \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }

                guard currentActiveFile?.id == activeFile.id else { return }
                await excalidrawWebCoordinator?.loadFile(from: parsedFile, force: true)
                NotificationCenter.default.post(
                    name: .activeCanvasFileDidRestore,
                    object: parsedFile
                )

            case .collaborationFile(let collaborationFile):
                let activeFile = ActiveFile.collaborationFile(collaborationFile)
                var restoredFile = try ExcalidrawFile(data: content, id: activeFile.id)
                restoredFile.name = filename ?? collaborationFile.name
                restoredFile.roomID = collaborationFile.roomID

                // Collaboration rooms are server-authoritative; restore the live canvas
                // first and let the normal collaboration update path refresh local backup.
                guard currentActiveFile?.id == activeFile.id else { return }
                await excalidrawCollaborationWebCoordinator?.loadFile(from: restoredFile, force: true)
                NotificationCenter.default.post(
                    name: .activeCanvasFileDidRestore,
                    object: restoredFile
                )

            case .cloudStorageFile(let reference):
                let activeFile = ActiveFile.cloudStorageFile(reference)
                let parsedFile = try ExcalidrawFile(data: content, id: activeFile.id)
                try await CloudStorageDocumentStore.shared.save(content, to: reference)
                guard currentActiveFile?.id == activeFile.id else { return }
                await excalidrawWebCoordinator?.loadFile(from: parsedFile, force: true)
                NotificationCenter.default.post(
                    name: .activeCanvasFileDidRestore,
                    object: parsedFile
                )

            case .temporaryFile, nil:
                throw AIChatEditError.unsupportedFile
        }
    }

    @MainActor
    private func saveRestoredLibraryFileMetadata(
        _ file: File,
        filename: String?
    ) throws {
        guard let context = file.managedObjectContext else { return }
        if let filename {
            file.name = filename
        }
        file.updatedAt = .now
        if context.hasChanges {
            try context.save()
        }
    }

    private func recordLocalRestoreCheckpoint(
        url: URL,
        content: Data
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            let checkpoint = LocalFileCheckpoint(context: context)
            checkpoint.id = UUID()
            checkpoint.url = url
            checkpoint.updatedAt = .now
            checkpoint.content = content
            checkpoint.source = FileCheckpointSource.restorePost.rawValue
            context.insert(checkpoint)
            try context.save()
        }
    }
}
