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

    /// Closes the session. On success, writes the matching `.aiPost`
    /// snapshot anchored to the assistant final-answer message id.
    /// On failure / cancel, just drops the session (no post snapshot —
    /// nothing meaningful changed, or changes are partial and the user
    /// can revert via the `.aiPre` row).
    @MainActor
    func endAIChatSession(
        success: Bool,
        assistantMessageID: String?,
        description: String?
    ) async {
        defer { self.aiChatSession = nil }

        guard success,
              let assistantMessageID,
              let session = self.aiChatSession else { return }

        // Anchor file resolution: prefer the file the session opened on,
        // but fall back to current active file if the session opened
        // without one (AI may have just created a new file).
        guard let target = session.anchorFile ?? currentActiveFile else { return }

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
