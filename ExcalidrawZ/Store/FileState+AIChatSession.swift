//
//  FileState+AIChatSession.swift
//  ExcalidrawZ
//
//  AI chat session begin/end hooks. Drives the new AI-history checkpoint
//  flow:
//
//  - `beginAIChatSession` runs right before a user message hits the LLM:
//    snapshots the current active file's content as a `.aiPre` checkpoint
//    anchored to the user message id, then sets `aiChatSession` so all
//    subsequent `updateFile` / `updateLocalFile` calls within the run
//    suppress checkpoint writes.
//
//  - `endAIChatSession(success:)` runs from the LLM completion handler:
//    on success, snapshots the post-AI state as `.aiPost` anchored to the
//    assistant final-answer message id; clears `aiChatSession` either way.
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
            try await snapshot(
                file: active,
                source: .aiPre,
                messageID: userMessageID,
                description: nil
            )
        } catch {
            self.aiChatSession = nil
            throw error
        }
    }

    /// Closes the session. Three branches:
    ///
    /// 1. **success && canvasModified** — write `.aiPost` snapshot
    ///    anchored to the assistant final-answer message id. The
    ///    `.aiPre` written at session start stays as the matching
    ///    "before" snapshot of the round.
    ///
    /// 2. **success && !canvasModified** — the AI's reply didn't run
    ///    any canvas-mutating tools, so the round produced nothing
    ///    visually different from the pre-state. The `.aiPre` we
    ///    eagerly recorded would just be a duplicate of the user's
    ///    last on-disk state with no `.aiPost` to pair with it. Drop
    ///    the `.aiPre` row to keep history clean.
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
                try await snapshot(
                    file: target,
                    source: .aiPost,
                    messageID: assistantMessageID,
                    description: description
                )
            } catch {
                logger.error("Failed to record .aiPost checkpoint: \(error)")
            }
        } else {
            // Read-only round — clean up the `.aiPre` row so it
            // doesn't show up in history with no matching `.aiPost`.
            // Best-effort: log on failure but don't throw, the
            // session is already winding down.
            guard let target else { return }
            do {
                try await deleteAiPreCheckpoint(
                    file: target,
                    messageID: session.userMessageID
                )
            } catch {
                logger.error("Failed to clean up unused .aiPre checkpoint: \(error)")
            }
        }
    }

    // MARK: - Internal snapshot

    /// Force-write a checkpoint of the file's current on-disk content
    /// with explicit metadata. Bypasses the user-edit "first creates,
    /// subsequent updates" semantics — every call creates a fresh row.
    private func snapshot(
        file: ActiveFile,
        source: FileCheckpointSource,
        messageID: String?,
        description: String?
    ) async throws {
        switch file {
            case .file(let f):
                let content = try await f.loadContent()
                try await PersistenceController.shared.fileRepository.recordCheckpoint(
                    fileObjectID: f.objectID,
                    content: content,
                    source: source,
                    messageID: messageID,
                    description: description
                )

            case .localFile(let url):
                try await snapshotLocalFile(
                    url: url,
                    source: source,
                    messageID: messageID,
                    description: description
                )

            case .temporaryFile, .collaborationFile:
                // Temporary files don't have history at all; collaboration
                // files have shared history that's a different beast (and
                // out of scope for this iteration). Skip silently — the
                // suppression flag still kicks in for the duration of the
                // session, which is the safe default.
                return
        }
    }

    /// Find and delete the `.aiPre` checkpoint anchored to this
    /// `userMessageID` for the given file. Used when the round
    /// finishes without any canvas-mutating tool calls — the eagerly-
    /// recorded `.aiPre` has nothing to pair with and would just clutter
    /// the file's history list. No-op if no matching row exists.
    private func deleteAiPreCheckpoint(
        file: ActiveFile,
        messageID: String
    ) async throws {
        switch file {
            case .file(let f):
                try await deleteAiPreFileCheckpoint(
                    fileObjectID: f.objectID,
                    messageID: messageID
                )

            case .localFile(let url):
                try await deleteAiPreLocalCheckpoint(
                    url: url,
                    messageID: messageID
                )

            case .temporaryFile, .collaborationFile:
                // We never write `.aiPre` for these in `snapshot(...)`,
                // so there's nothing to delete.
                return
        }
    }

    private func deleteAiPreFileCheckpoint(
        fileObjectID: NSManagedObjectID,
        messageID: String
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let checkpointObjectID: NSManagedObjectID? = try await context.perform {
            let request: NSFetchRequest<FileCheckpoint> = FileCheckpoint.fetchRequest()
            request.predicate = NSPredicate(
                format: "file == %@ AND source == %@ AND messageID == %@",
                fileObjectID,
                FileCheckpointSource.aiPre.rawValue,
                messageID
            )
            request.fetchLimit = 1
            return try context.fetch(request).first?.objectID
        }
        guard let checkpointObjectID else { return }
        try await PersistenceController.shared.checkpointRepository
            .deleteCheckpoint(checkpointObjectID: checkpointObjectID)
    }

    private func deleteAiPreLocalCheckpoint(
        url: URL,
        messageID: String
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<LocalFileCheckpoint> = LocalFileCheckpoint.fetchRequest()
            request.predicate = NSPredicate(
                format: "url == %@ AND source == %@ AND messageID == %@",
                url as CVarArg,
                FileCheckpointSource.aiPre.rawValue,
                messageID
            )
            request.fetchLimit = 1
            if let row = try context.fetch(request).first {
                context.delete(row)
                try context.save()
            }
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
        messageID: String?,
        description: String?
    ) async throws {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)

        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            let checkpoint = LocalFileCheckpoint(context: context)
            checkpoint.id = UUID()
            checkpoint.url = url
            checkpoint.content = data
            checkpoint.updatedAt = .now
            checkpoint.source = source.rawValue
            checkpoint.messageID = messageID
            checkpoint.historyDescription = description
            context.insert(checkpoint)
            try context.save()
        }
    }
}
