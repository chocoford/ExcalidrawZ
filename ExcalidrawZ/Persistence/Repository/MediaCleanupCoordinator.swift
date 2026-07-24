//
//  MediaCleanupCoordinator.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/20.
//

import CoreData
import Foundation

struct MediaCleanupCandidate: Identifiable, Hashable, @unchecked Sendable {
    enum Kind: Hashable, Sendable {
        case orphaned
        case historyOnly
        case unverified
    }

    let id: NSManagedObjectID
    let mediaID: String
    let sourceName: String
    let kind: Kind
    let checkpointObjectIDs: [NSManagedObjectID]
}

struct MediaCleanupAnalysis: Sendable {
    let orphaned: [MediaCleanupCandidate]
    let historyOnly: [MediaCleanupCandidate]
    let trashedFiles: [MediaCleanupTrashedFileCandidate]
    let unverified: [MediaCleanupCandidate]
    let skippedCount: Int

    var isEmpty: Bool {
        orphaned.isEmpty && historyOnly.isEmpty && trashedFiles.isEmpty && unverified.isEmpty
    }
}

struct MediaCleanupTrashedFileCandidate: Identifiable, Hashable, @unchecked Sendable {
    enum Kind: Hashable, Sendable {
        case file
        case collaborationFile
    }

    let id: URL
    let objectID: NSManagedObjectID
    let kind: Kind
    let name: String
    let mediaObjectIDs: [NSManagedObjectID]
}

struct MediaCleanupResult: Sendable {
    let deletedMediaCount: Int
    let deletedCheckpointCount: Int
}

actor MediaCleanupCoordinator {
    static let shared = MediaCleanupCoordinator()

    private enum StoredContentKind: Sendable {
        case file
        case collaboration
        case checkpoint

        var encryptedContentType: String? {
            switch self {
                case .file:
                    "file"
                case .checkpoint:
                    "fileCheckpoint"
                case .collaboration:
                    nil
            }
        }
    }

    private struct StoredContentSnapshot: Sendable {
        let filePath: String?
        let contentID: String?
        let fallbackContent: Data?
        let kind: StoredContentKind
    }

    private struct CurrentFileSnapshot: Sendable {
        let content: StoredContentSnapshot
    }

    private struct MediaSnapshot: @unchecked Sendable {
        let objectID: NSManagedObjectID
        let mediaID: String?
        let sourceName: String
        let ownerObjectID: NSManagedObjectID?
        let ownerKind: MediaCleanupTrashedFileCandidate.Kind?
        let ownerIsInTrash: Bool
    }

    private struct CheckpointSnapshot: @unchecked Sendable {
        let objectID: NSManagedObjectID
        let content: StoredContentSnapshot
    }

    private struct ScanSnapshot: Sendable {
        let medias: [MediaSnapshot]
        let currentFiles: [CurrentFileSnapshot]
        let checkpoints: [CheckpointSnapshot]
    }

    private init() {}

    func scan() async throws -> MediaCleanupAnalysis {
        let context = PersistenceController.shared.newTaskContext()
        let snapshot = try await makeScanSnapshot(context: context)

        var currentReferences: Set<String> = []
        var hasUnreadableCurrentContent = false
        for file in snapshot.currentFiles {
            do {
                let data = try await loadContent(file.content)
                currentReferences.formUnion(try referencedMediaIDs(in: data))
            } catch {
                hasUnreadableCurrentContent = true
            }
        }

        var checkpointReferences: [String: Set<NSManagedObjectID>] = [:]
        var hasUnreadableCheckpointContent = false
        for checkpoint in snapshot.checkpoints {
            do {
                let data = try await loadContent(checkpoint.content)
                let mediaIDs = try referencedMediaIDs(in: data)
                for mediaID in mediaIDs {
                    checkpointReferences[mediaID, default: []].insert(checkpoint.objectID)
                }
            } catch {
                hasUnreadableCheckpointContent = true
            }
        }

        var orphaned: [MediaCleanupCandidate] = []
        var historyOnly: [MediaCleanupCandidate] = []
        var unverified: [MediaCleanupCandidate] = []

        var trashedMedia: [URL: [MediaSnapshot]] = [:]
        for media in snapshot.medias where media.ownerIsInTrash {
            guard let ownerObjectID = media.ownerObjectID,
                  media.ownerKind != nil else {
                continue
            }
            trashedMedia[ownerObjectID.uriRepresentation(), default: []].append(media)
        }
        let trashedFiles = trashedMedia.compactMap { objectURI, medias -> MediaCleanupTrashedFileCandidate? in
            guard let first = medias.first,
                  let objectID = first.ownerObjectID,
                  let kind = first.ownerKind else {
                return nil
            }
            return MediaCleanupTrashedFileCandidate(
                id: objectURI,
                objectID: objectID,
                kind: kind,
                name: first.sourceName,
                mediaObjectIDs: medias.map(\.objectID)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let trashedMediaObjectIDs = Set(trashedFiles.flatMap(\.mediaObjectIDs))

        for media in snapshot.medias {
            guard !trashedMediaObjectIDs.contains(media.objectID) else {
                continue
            }

            guard let mediaID = media.mediaID, !mediaID.isEmpty else {
                orphaned.append(
                    MediaCleanupCandidate(
                        id: media.objectID,
                        mediaID: media.mediaID ?? "",
                        sourceName: media.sourceName,
                        kind: .orphaned,
                        checkpointObjectIDs: []
                    )
                )
                continue
            }
            if currentReferences.contains(mediaID) {
                continue
            }

            // Media IDs are stored globally and injected into every canvas.
            // If any content could not be inspected, it may still reference
            // this ID even when the MediaItem relationship points elsewhere.
            guard !hasUnreadableCurrentContent,
                  !hasUnreadableCheckpointContent else {
                unverified.append(
                    MediaCleanupCandidate(
                        id: media.objectID,
                        mediaID: mediaID,
                        sourceName: media.sourceName,
                        kind: .unverified,
                        checkpointObjectIDs: []
                    )
                )
                continue
            }

            let checkpointIDs = Array(
                checkpointReferences[mediaID] ?? []
            ).sorted {
                $0.uriRepresentation().absoluteString < $1.uriRepresentation().absoluteString
            }
            let kind: MediaCleanupCandidate.Kind = checkpointIDs.isEmpty ? .orphaned : .historyOnly
            let candidate = MediaCleanupCandidate(
                id: media.objectID,
                mediaID: mediaID,
                sourceName: media.sourceName,
                kind: kind,
                checkpointObjectIDs: checkpointIDs
            )

            switch kind {
                case .orphaned:
                    orphaned.append(candidate)
                case .historyOnly:
                    historyOnly.append(candidate)
                case .unverified:
                    break
            }
        }

        return MediaCleanupAnalysis(
            orphaned: orphaned.sorted { $0.sourceName < $1.sourceName },
            historyOnly: historyOnly.sorted { $0.sourceName < $1.sourceName },
            trashedFiles: trashedFiles,
            unverified: unverified.sorted { $0.sourceName < $1.sourceName },
            skippedCount: unverified.count
        )
    }

    func clean(_ candidates: [MediaCleanupCandidate]) async throws -> MediaCleanupResult {
        let checkpointObjectIDs = Set(
            candidates.flatMap(\.checkpointObjectIDs)
        )

        for checkpointObjectID in checkpointObjectIDs {
            try await PersistenceController.shared.checkpointRepository.deleteCheckpoint(
                checkpointObjectID: checkpointObjectID
            )
        }
        for candidate in candidates {
            try await PersistenceController.shared.mediaItemRepository.deleteMediaItem(
                mediaItemObjectID: candidate.id
            )
        }

        return MediaCleanupResult(
            deletedMediaCount: candidates.count,
            deletedCheckpointCount: checkpointObjectIDs.count
        )
    }

    /// Removes media that belonged to a permanently deleted file only when
    /// no remaining current file or checkpoint references the global media ID.
    func cleanOrphanedMedia(withObjectURIs objectURIs: [URL]) async throws -> Int {
        guard !objectURIs.isEmpty else { return 0 }

        let targetURIs = Set(objectURIs)
        let candidates = try await scan().orphaned.filter {
            targetURIs.contains($0.id.uriRepresentation())
        }
        for candidate in candidates {
            try await PersistenceController.shared.mediaItemRepository.deleteMediaItem(
                mediaItemObjectID: candidate.id
            )
        }
        return candidates.count
    }

    private func makeScanSnapshot(context: NSManagedObjectContext) async throws -> ScanSnapshot {
        try await context.perform {
            let mediaRequest: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            let mediaItems = try context.fetch(mediaRequest)

            var currentFiles: [CurrentFileSnapshot] = []

            let fileRequest: NSFetchRequest<File> = File.fetchRequest()
            for file in try context.fetch(fileRequest) {
                currentFiles.append(CurrentFileSnapshot(
                    content: StoredContentSnapshot(
                        filePath: file.filePath,
                        contentID: file.id?.uuidString,
                        fallbackContent: file.content,
                        kind: .file
                    )
                ))
            }

            let collaborationRequest: NSFetchRequest<CollaborationFile> = CollaborationFile.fetchRequest()
            for file in try context.fetch(collaborationRequest) {
                currentFiles.append(CurrentFileSnapshot(
                    content: StoredContentSnapshot(
                        filePath: file.filePath,
                        contentID: file.id?.uuidString,
                        fallbackContent: file.content,
                        kind: .collaboration
                    )
                ))
            }

            let medias = mediaItems.map { mediaItem in
                let sourceName: String
                let ownerObjectID: NSManagedObjectID?
                let ownerKind: MediaCleanupTrashedFileCandidate.Kind?
                let ownerIsInTrash: Bool

                if let file = mediaItem.file {
                    sourceName = file.name ?? String(localizable: .generalUnknown)
                    ownerObjectID = file.objectID
                    ownerKind = .file
                    ownerIsInTrash = file.inTrash
                } else if let file = mediaItem.collaborationFile {
                    sourceName = file.name ?? String(localizable: .generalUnknown)
                    ownerObjectID = file.objectID
                    ownerKind = .collaborationFile
                    ownerIsInTrash = file.inTrash
                } else {
                    sourceName = String(localizable: .generalUnknown)
                    ownerObjectID = nil
                    ownerKind = nil
                    ownerIsInTrash = false
                }

                return MediaSnapshot(
                    objectID: mediaItem.objectID,
                    mediaID: mediaItem.id,
                    sourceName: sourceName,
                    ownerObjectID: ownerObjectID,
                    ownerKind: ownerKind,
                    ownerIsInTrash: ownerIsInTrash
                )
            }

            let checkpointRequest: NSFetchRequest<FileCheckpoint> = FileCheckpoint.fetchRequest()
            let checkpoints = try context.fetch(checkpointRequest).map { checkpoint in
                return CheckpointSnapshot(
                    objectID: checkpoint.objectID,
                    content: StoredContentSnapshot(
                        filePath: checkpoint.filePath,
                        contentID: checkpoint.id?.uuidString,
                        fallbackContent: checkpoint.content,
                        kind: .checkpoint
                    )
                )
            }

            return ScanSnapshot(
                medias: medias,
                currentFiles: currentFiles,
                checkpoints: checkpoints
            )
        }
    }

    private func loadContent(_ snapshot: StoredContentSnapshot) async throws -> Data {
        let data: Data
        if let filePath = snapshot.filePath,
           let contentID = snapshot.contentID {
            // Destructive cleanup must not classify references from a stale
            // local cache when a newer iCloud Drive copy may exist.
            data = try await FileStorageManager.shared.loadContent(
                relativePath: filePath,
                fileID: contentID
            )
        } else if let filePath = snapshot.filePath {
            data = try await FileStorageManager.shared.loadContent(relativePath: filePath)
        } else if let fallbackContent = snapshot.fallbackContent {
            data = fallbackContent
        } else {
            throw AppError.fileError(.notFound)
        }

        guard EncryptedContentService.isEncryptedEnvelope(data),
              let encryptedContentType = snapshot.kind.encryptedContentType,
              let contentID = snapshot.contentID else {
            return data
        }

        try LockedContentReadPolicy.ensureProtectedContentAccessAllowed()
        return try await LockedContentUnlockSession.shared.decrypt(
            data,
            expectedContentType: encryptedContentType,
            expectedContentID: contentID
        )
    }

    private func referencedMediaIDs(in data: Data) throws -> Set<String> {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let elements = root["elements"] as? [[String: Any]] else {
            return []
        }

        return elements.reduce(into: Set<String>()) { result, element in
            guard element["isDeleted"] as? Bool != true,
                  let fileID = element["fileId"] as? String,
                  !fileID.isEmpty else {
                return
            }
            result.insert(fileID)
        }
    }
}
