//
//  FileState+AIChatSession.swift
//  ExcalidrawZ
//
//  AI chat session begin/end hooks. Drives the new AI-history checkpoint
//  flow:
//
//  - `beginAIChatSession` runs right before a user message hits the LLM:
//    snapshots the current active file's content as a `.aiPre` checkpoint
//    and links it to the user message id, then sets `aiChatSession` so
//    all subsequent `updateFile` / `updateLocalFile` calls within the
//    run suppress checkpoint writes.
//
//  - `endAIChatSession(success:)` runs from the LLM completion handler:
//    on success, snapshots the post-AI state as `.aiPost` and links it
//    to the assistant final-answer message id; clears `aiChatSession`
//    either way.
//
//  We require the caller to supply the user / assistant message ids
//  explicitly — they live in LLMKit's conversation state and FileState
//  shouldn't reach into that to fish them out.
//

import Foundation
import CoreData

extension FileState {
    /// Records `.aiPre` snapshot + opens the suppression window.
    /// Throws (and leaves `aiChatSession` nil) if the active file isn't
    /// snapshot-capable (temporary file → no history; collaboration file
    /// → out of scope for now).
    @MainActor
    func beginAIChatSession(
        conversationID: String,
        userMessageID: String
    ) async throws {
        let active = currentActiveFile

        // Open the session first so suppression kicks in *before* the
        // snapshot read — without this, a concurrent updateFile from a
        // WebKit autosave could squeeze a user checkpoint in between.
        self.aiChatSession = AIChatSessionState(
            conversationID: conversationID,
            userMessageID: userMessageID,
            anchorFile: active
        )

        // No active file → no `.aiPre` to write. The session still opens
        // so that if the AI creates a new file mid-run, that file's
        // updates won't pollute history; the post snapshot at session
        // end will pick up whatever the active file is by then.
        guard let active else { return }

        // If snapshotting fails, roll the session back. Otherwise the
        // suppression flag would dangle and silently swallow later
        // checkpoints until something else clears it.
        do {
            if let checkpoint = try await snapshot(
                file: active,
                source: .aiPre,
                description: nil
            ) {
                if var session = self.aiChatSession,
                   session.conversationID == conversationID,
                   session.userMessageID == userMessageID {
                    session.preCheckpointID = checkpoint.id
                    session.preCheckpointKind = checkpoint.kind
                    self.aiChatSession = session
                }
                try await recordCheckpointLink(
                    file: active,
                    checkpoint: checkpoint,
                    conversationID: conversationID,
                    messageID: userMessageID,
                    role: .revertAnchor
                )
            }
        } catch {
            self.aiChatSession = nil
            throw error
        }
    }

    /// Closes the session. Three branches:
    ///
    /// 1. **success && canvasModified** — write `.aiPost` snapshot
    ///    linked to the assistant final-answer message id. The
    ///    `.aiPre` written at session start stays as the matching
    ///    "before" snapshot of the round.
    ///
    /// 2. **success && !canvasModified** — the AI's reply didn't run
    ///    any canvas-mutating tools, so the round produced nothing
    ///    visually different from the pre-state. If an earlier
    ///    checkpoint exists, rebind this user message's revert anchor
    ///    to it and drop the duplicate `.aiPre`; otherwise keep the
    ///    `.aiPre` so revert still has a concrete target.
    ///
    /// 3. **!success** — failure / cancel. The canvas may be in a
    ///    half-modified state (a tool ran partway). Keep the `.aiPre`
    ///    so the user can revert via it; don't write `.aiPost`.
    ///
    /// `canvasModified` is computed by the caller (typically by
    /// scanning the round's tool calls against
    /// `ExcalidrawAgentConfig.canvasModifyingToolNames`). We don't
    /// reach into LLMKit here because FileState shouldn't depend on
    /// the agent config / chat state directly.
    @MainActor
    func endAIChatSession(
        success: Bool,
        canvasModified: Bool,
        assistantMessageID: String?,
        description: String?
    ) async {
        defer { self.aiChatSession = nil }

        guard let session = self.aiChatSession else { return }

        // Failure path: nothing to do; `.aiPre` stays as the revert
        // anchor.
        guard success else { return }

        // Anchor file resolution: prefer the file the session opened on,
        // but fall back to current active file if the session opened
        // without one (AI may have just created a new file).
        let target = session.anchorFile ?? currentActiveFile

        if canvasModified {
            guard let target, let assistantMessageID else { return }
            do {
                if let checkpoint = try await snapshot(
                    file: target,
                    source: .aiPost,
                    description: description
                ) {
                    try await recordCheckpointLink(
                        file: target,
                        checkpoint: checkpoint,
                        conversationID: session.conversationID,
                        messageID: assistantMessageID,
                        role: .resultSnapshot
                    )
                }
            } catch {
                logger.error("Failed to record .aiPost checkpoint: \(error)")
            }
        } else {
            // Read-only round — clean up the `.aiPre` row only after
            // rebinding this user message to an existing checkpoint.
            // If no replacement exists, keep the `.aiPre` as the only
            // available revert anchor.
            guard let target else { return }
            do {
                if let replacement = try await latestReusableCheckpoint(
                    file: target,
                    excludingCheckpointID: session.preCheckpointID
                ) {
                    try await recordCheckpointLink(
                        file: target,
                        checkpoint: replacement,
                        conversationID: session.conversationID,
                        messageID: session.userMessageID,
                        role: .revertAnchor
                    )
                    if let preCheckpoint = recordedPreCheckpoint(from: session) {
                        try await deleteCheckpoint(
                            preCheckpoint,
                            file: target
                        )
                    }
                }
            } catch {
                logger.error("Failed to clean up unused .aiPre checkpoint: \(error)")
            }
        }
    }

    // MARK: - Internal snapshot

    private struct RecordedAICheckpoint {
        let id: UUID
        let kind: AIMessageCheckpointKind
    }

    private func recordedPreCheckpoint(
        from session: AIChatSessionState
    ) -> RecordedAICheckpoint? {
        guard let id = session.preCheckpointID,
              let kind = session.preCheckpointKind
        else {
            return nil
        }
        return RecordedAICheckpoint(id: id, kind: kind)
    }

    /// Force-write a checkpoint of the file's current on-disk content
    /// with explicit metadata. Bypasses the user-edit "first creates,
    /// subsequent updates" semantics — every call creates a fresh row.
    private func snapshot(
        file: ActiveFile,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> RecordedAICheckpoint? {
        switch file {
            case .file(let f):
                let content = try await f.loadContent()
                // DIAG: snapshot read — verify whether content has elements
                // at the moment we record the checkpoint. If `.aiPost` lands
                // here with `hasElements=false`, the JS-side debounced
                // onStateChanged hasn't flushed back to disk yet (race).
                let elementsHint: String = {
                    guard let s = String(data: content, encoding: .utf8) else { return "?" }
                    return s.contains("\"elements\":[{") ? "true" : "false"
                }()
                print("[aiDiag] snapshot source=\(source.rawValue) file=\(f.name ?? "?") content.bytes=\(content.count) hasElements=\(elementsHint)")
                let checkpointID = try await PersistenceController.shared.fileRepository.recordCheckpoint(
                    fileObjectID: f.objectID,
                    content: content,
                    source: source,
                    description: description
                )
                return RecordedAICheckpoint(id: checkpointID, kind: .file)

            case .localFile(let url):
                let checkpointID = try await snapshotLocalFile(
                    url: url,
                    source: source,
                    description: description
                )
                return RecordedAICheckpoint(id: checkpointID, kind: .local)

            case .temporaryFile, .collaborationFile:
                // Temporary files don't have history at all; collaboration
                // files have shared history that's a different beast (and
                // out of scope for this iteration). Skip silently — the
                // suppression flag still kicks in for the duration of the
                // session, which is the safe default.
                return nil
        }
    }

    private func recordCheckpointLink(
        file: ActiveFile,
        checkpoint: RecordedAICheckpoint,
        conversationID: String,
        messageID: String,
        role: AIMessageCheckpointLinkRole
    ) async throws {
        try await PersistenceController.shared.aiMessageCheckpointLinkRepository.upsertLink(
            conversationID: conversationID,
            messageID: messageID,
            role: role,
            checkpointID: checkpoint.id,
            checkpointKind: checkpoint.kind,
            fileScope: file.aiConversationFileScope
        )
    }

    /// For a successful read-only round, keep the user message revertable
    /// by pointing it at an existing checkpoint before deleting the
    /// duplicate `.aiPre`. If there is no previous checkpoint, keep the
    /// `.aiPre` and its link.
    private func latestReusableCheckpoint(
        file: ActiveFile,
        excludingCheckpointID checkpointID: UUID?
    ) async throws -> RecordedAICheckpoint? {
        switch file {
            case .file(let f):
                return try await latestReusableFileCheckpoint(
                    fileObjectID: f.objectID,
                    excludingCheckpointID: checkpointID
                )

            case .localFile(let url):
                return try await latestReusableLocalCheckpoint(
                    url: url,
                    excludingCheckpointID: checkpointID
                )

            case .temporaryFile, .collaborationFile:
                return nil
        }
    }

    /// Delete the exact checkpoint previously created for this session.
    private func deleteCheckpoint(
        _ checkpoint: RecordedAICheckpoint,
        file: ActiveFile
    ) async throws {
        switch (file, checkpoint.kind) {
            case (.file(let f), .file):
                try await deleteFileCheckpoint(
                    fileObjectID: f.objectID,
                    checkpointID: checkpoint.id
                )

            case (.localFile(let url), .local):
                try await deleteLocalCheckpoint(
                    url: url,
                    checkpointID: checkpoint.id
                )

            case (.temporaryFile, _), (.collaborationFile, _), (.file, .local), (.localFile, .file):
                return
        }
    }

    private func deleteFileCheckpoint(
        fileObjectID: NSManagedObjectID,
        checkpointID: UUID
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let checkpointObjectID: NSManagedObjectID? = try await context.perform {
            guard let file = try context.existingObject(with: fileObjectID) as? File else {
                return nil
            }

            let request: NSFetchRequest<FileCheckpoint> = FileCheckpoint.fetchRequest()
            request.predicate = NSPredicate(
                format: "file == %@ AND id == %@",
                file,
                checkpointID as CVarArg
            )
            request.fetchLimit = 1
            return try context.fetch(request).first?.objectID
        }
        guard let checkpointObjectID else { return }
        try await PersistenceController.shared.checkpointRepository
            .deleteCheckpoint(checkpointObjectID: checkpointObjectID)
    }

    private func latestReusableFileCheckpoint(
        fileObjectID: NSManagedObjectID,
        excludingCheckpointID checkpointID: UUID?
    ) async throws -> RecordedAICheckpoint? {
        let context = PersistenceController.shared.container.newBackgroundContext()
        return try await context.perform {
            guard let file = try context.existingObject(with: fileObjectID) as? File else {
                return nil
            }

            let request: NSFetchRequest<FileCheckpoint> = FileCheckpoint.fetchRequest()
            if let checkpointID {
                request.predicate = NSPredicate(
                    format: "file == %@ AND id != %@",
                    file,
                    checkpointID as CVarArg
                )
            } else {
                request.predicate = NSPredicate(format: "file == %@", file)
            }
            request.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
            request.fetchLimit = 1

            guard let checkpoint = try context.fetch(request).first,
                  let id = checkpoint.id
            else {
                return nil
            }
            return RecordedAICheckpoint(id: id, kind: .file)
        }
    }

    private func deleteLocalCheckpoint(
        url: URL,
        checkpointID: UUID
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<LocalFileCheckpoint> = LocalFileCheckpoint.fetchRequest()
            request.predicate = NSPredicate(
                format: "url == %@ AND id == %@",
                url as CVarArg,
                checkpointID as CVarArg
            )
            request.fetchLimit = 1
            if let row = try context.fetch(request).first {
                context.delete(row)
                try context.save()
            }
        }
    }

    private func latestReusableLocalCheckpoint(
        url: URL,
        excludingCheckpointID checkpointID: UUID?
    ) async throws -> RecordedAICheckpoint? {
        let context = PersistenceController.shared.container.newBackgroundContext()
        return try await context.perform {
            let request: NSFetchRequest<LocalFileCheckpoint> = LocalFileCheckpoint.fetchRequest()
            if let checkpointID {
                request.predicate = NSPredicate(
                    format: "url == %@ AND id != %@",
                    url as CVarArg,
                    checkpointID as CVarArg
                )
            } else {
                request.predicate = NSPredicate(format: "url == %@", url as CVarArg)
            }
            request.sortDescriptors = [.init(key: "updatedAt", ascending: false)]
            request.fetchLimit = 1

            guard let checkpoint = try context.fetch(request).first,
                  let id = checkpoint.id
            else {
                return nil
            }
            return RecordedAICheckpoint(id: id, kind: .local)
        }
    }

    /// Local-file analogue of `FileRepository.recordCheckpoint`. There's
    /// no dedicated repository for local files — checkpoint creation is
    /// inlined inside `updateLocalFile` — so we replicate the minimal
    /// shape here.
    @MainActor
    private func snapshotLocalFile(
        url: URL,
        source: FileCheckpointSource,
        description: String?
    ) async throws -> UUID {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)

        let context = PersistenceController.shared.container.newBackgroundContext()
        return try await context.perform {
            let checkpoint = LocalFileCheckpoint(context: context)
            let checkpointID = UUID()
            checkpoint.id = checkpointID
            checkpoint.url = url
            checkpoint.content = data
            checkpoint.updatedAt = .now
            checkpoint.source = source.rawValue
            checkpoint.historyDescription = description
            context.insert(checkpoint)
            try context.save()
            return checkpointID
        }
    }
}
