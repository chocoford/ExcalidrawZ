//
//  AIChatState.swift
//  ExcalidrawZ
//
//  App-wide runtime state for the AI chat surfaces. Sibling of (not
//  merged into) `FileState`: while `FileState` is per-window — each
//  window has its own current file with its own `aiChatConversationID`
//  — the AI account, quota, and conversation list are app-global
//  resources, so the chat session state that floats around them
//  (queued sends, future drafts, etc.) lives at app scope too.
//
//  Owned at the App layer (`ExcalidrawZApp`) and injected via
//  `.environmentObject` on the `WindowGroup` root, alongside `LLMState`,
//  `Store`, and `AppPreference`. We keep DI rather than reach for a
//  global singleton: the only reasons to pick a singleton would be
//  cross-state references with no clean injection path or non-View call
//  sites that can't see the environment, and neither applies here.
//
//  Persistent settings (default model, per-conversation model overrides)
//  live in `AIChatPreferences` instead — that's user-tweakable preferences,
//  this is volatile session state.
//

import Foundation
import LLMCore
import LLMKit

enum AIChatEditError: LocalizedError {
    case unsupportedFile
    case missingRevertPoint

    var errorDescription: String? {
        switch self {
            case .unsupportedFile:
                "Revert is currently only supported for library files."
            case .missingRevertPoint:
                "No revert point found for this message."
        }
    }
}

@MainActor
final class AIChatState: ObservableObject {
    /// Messages typed while a reply was streaming. PromptInputView appends
    /// to this on mid-stream send, drains it FIFO when the in-flight reply
    /// finishes, and clears it on stop. Hosts read it to render the
    /// `PendingQueueView`. Shared at app scope so a message queued in
    /// the island still shows when the user docks back to the inspector
    /// (and vice versa) — and stays consistent across windows for the
    /// same reason the AI quota balance is.
    @Published var pendingQueue: [PendingQueueMessage] = []

    /// One-shot prefill request for `PromptInputView`'s input box. Driven
    /// by the per-user-message "Revert" action: the host sets this, the
    /// input view picks it up via `.onChange(of:)`, copies the text into
    /// its local `inputText` state, and refocuses. Token-based so two
    /// reverts with the same text still fire the second time.
    @Published var draftRequest: DraftRequest?
    @Published var editSession: EditSession?
    @Published var editCancelToken: Int = 0
    @Published var transientError: TransientError?
    @Published var promptDraftText: String = ""
    @Published var promptDraftImages: [PendingPastedImage] = []

    struct DraftRequest: Equatable {
        let text: String
        let files: [ChatMessageContent.File]
        let token: Int

        static func == (lhs: DraftRequest, rhs: DraftRequest) -> Bool {
            lhs.token == rhs.token
        }
    }

    struct EditSession: Equatable {
        enum Mode {
            case edit
        }

        let conversationID: String
        let userMessageID: String
        let mode: Mode
    }

    struct TransientError: Identifiable, Equatable {
        let id: UUID
        let conversationID: String
        let userMessageID: String
        let message: String
        let retryPrompt: String
        let retryFiles: [ChatMessageContent.File]

        init(
            id: UUID = UUID(),
            conversationID: String,
            userMessageID: String,
            message: String,
            retryPrompt: String,
            retryFiles: [ChatMessageContent.File]
        ) {
            self.id = id
            self.conversationID = conversationID
            self.userMessageID = userMessageID
            self.message = message
            self.retryPrompt = retryPrompt
            self.retryFiles = retryFiles
        }
    }

    private var draftTokenSeed: Int = 0

    /// Push a new draft text into the input box. Increments the internal
    /// token so SwiftUI sees a fresh value even if `text` is identical
    /// to the previous request.
    func requestDraft(_ text: String, files: [ChatMessageContent.File] = []) {
        draftTokenSeed += 1
        draftRequest = DraftRequest(text: text, files: files, token: draftTokenSeed)
    }

    func beginEditing(
        conversationID: String,
        userMessageID: String,
        text: String,
        files: [ChatMessageContent.File],
        mode: EditSession.Mode
    ) {
        editSession = EditSession(
            conversationID: conversationID,
            userMessageID: userMessageID,
            mode: mode
        )
        requestDraft(text, files: files)
    }

    func finishEditing() {
        editSession = nil
    }

    func cancelEditing() {
        editSession = nil
        editCancelToken += 1
    }

    func presentTransientError(
        _ error: Error,
        conversationID: String,
        userMessageID: String,
        retryPrompt: String,
        retryFiles: [ChatMessageContent.File]
    ) {
        guard !(error is CancellationError) else { return }
        transientError = TransientError(
            conversationID: conversationID,
            userMessageID: userMessageID,
            message: error.localizedDescription,
            retryPrompt: retryPrompt,
            retryFiles: retryFiles
        )
    }

    func clearTransientError(for conversationID: String) {
        guard transientError?.conversationID == conversationID else { return }
        transientError = nil
    }

    /// Conversations whose context is currently being compacted by
    /// LLMKit. Driven by `PromptInputView.compactCurrentContext()` —
    /// the prompt input flips a conversation id in here while the
    /// network call runs, and `AIChatView` reads it to render a
    /// transient "compacting…" indicator. A `Set` (rather than a
    /// single id) keeps state correct if the inspector and the
    /// floating island disagree on which conversation is foreground:
    /// each instance only watches its own conversation id.
    @Published var compactingConversationIDs: Set<String> = []

    func markCompacting(conversationID: String) {
        compactingConversationIDs.insert(conversationID)
    }

    func unmarkCompacting(conversationID: String) {
        compactingConversationIDs.remove(conversationID)
    }

    /// Convenience: is a specific conversation currently compacting?
    /// Used by the prompt input's per-instance gating and the
    /// chat view's indicator.
    func isCompacting(conversationID: String?) -> Bool {
        guard let conversationID else { return false }
        return compactingConversationIDs.contains(conversationID)
    }
}

// MARK: - Conversation content helpers

extension LLMKit.Conversation {
    /// True if this conversation carries at least one user or
    /// assistant message — i.e. someone actually chatted in it.
    /// LLMKit auto-injects a `.system` message into every fresh
    /// conversation, so a non-empty `messages` array isn't enough
    /// to know there was real activity. Used by the inspector and
    /// island views to skip "empty shells" when auto-resuming the
    /// most recent conversation on open.
    var hasUserOrAssistantMessage: Bool {
        messages.contains { msg in
            guard case .content(let content) = msg else { return false }
            return content.role == .user || content.role == .assistant
        }
    }
}

extension AIConversationSnapshot {
    /// Snapshot-side mirror of `Conversation.hasUserOrAssistantMessage`,
    /// used during file-load pre-selection. Skips the `.system`
    /// auto-injection so a freshly-minted conversation that never
    /// got a real user message doesn't look like resumable history.
    var hasUserOrAssistantMessage: Bool {
        messages.contains { msg in
            (msg.messageType ?? "content") == "content"
                && (msg.role == "user" || msg.role == "assistant")
        }
    }
}

// MARK: - File-scoped conversation loader

extension AIChatState {
    /// Refresh the global conversation cache and pre-select the most
    /// recent conversation tied to the current active file. Called on
    /// every file change (typically driven by a `.task(id:)` on
    /// `ContentView`), so by the time the user opens the chat panel
    /// the right conversation is already pinned.
    ///
    /// "Pre-select" writes to `fileState.aiChatConversationID`. If
    /// the active file has no persisted history, the id is set to
    /// nil and the next send creates a fresh conversation bound to
    /// the active file's unified scope.
    ///
    /// Library files, local URLs, temporary URLs, and collaboration
    /// files all participate. The repository keeps the lookup
    /// independent of Core Data relationships so URL-backed files can
    /// be scoped without first becoming Core Data entities.
    func loadConversationForActiveFile(
        in llmState: LLMStateObject,
        fileState: FileState
    ) async {
        let activeFile = fileState.currentActiveFile
        print("[AIChatDiag] loadConversationForActiveFile fired. activeFile=\(describe(activeFile))")

        // Always refresh first: the global cache also drives
        // AIChatView's rendering of the conversation we're about to
        // pin, so we want both pieces to land in the same render
        // pass. The snapshot path is fast (single Core Data fetch).
        await llmState.refreshConversations()
        print("[AIChatDiag] after refresh, conversations.value count=\(llmState.conversations.value?.count ?? -1)")

        let chosen = await pickLatestConversationID(forActiveFile: activeFile)
        print("[AIChatDiag] pickLatestConversationID -> \(chosen ?? "nil")")
        await MainActor.run {
            fileState.aiChatConversationID = chosen
        }
    }

    /// Returns the id of the most-recent file-bound conversation that
    /// has real activity (user or assistant message). Nil when:
    /// - there is no active file,
    /// - no conversations exist for that active-file scope, or
    /// - all of them are empty shells (system-only).
    private func pickLatestConversationID(
        forActiveFile activeFile: FileState.ActiveFile?
    ) async -> String? {
        guard let scope = activeFile?.aiConversationFileScope else {
            print("[AIChatDiag] pick: activeFile is nil, skipping")
            return nil
        }
        print("[AIChatDiag] pick: querying snapshots for scope=\(scope.kind.rawValue):\(scope.id)")
        let repo = PersistenceController.shared.aiConversationRepository
        let snapshots: [AIConversationSnapshot]
        do {
            snapshots = try await repo.fetchConversationSnapshots(forFileScope: scope)
        } catch {
            print("[AIChatDiag] pick: fetchConversationSnapshots(forFileScope:) threw \(error.localizedDescription)")
            return nil
        }
        print("[AIChatDiag] pick: got \(snapshots.count) snapshots for this file. \(snapshots.map { "[\(($0.conversationID ?? "?").prefix(8)) msgs=\($0.messages.count) ua=\($0.hasUserOrAssistantMessage)]" }.joined(separator: " "))")
        let candidates = snapshots.filter { $0.hasUserOrAssistantMessage }
        print("[AIChatDiag] pick: \(candidates.count) candidates after filter")
        let latest = candidates.max(by: { ($0.lastChatAt ?? .distantPast) < ($1.lastChatAt ?? .distantPast) })
        return latest?.conversationID
    }

    private func describe(_ activeFile: FileState.ActiveFile?) -> String {
        guard let activeFile else { return "nil" }
        switch activeFile {
            case .file(let f): return ".file(name=\(f.name ?? "?") id=\(f.id?.uuidString ?? "nil"))"
            case .localFile(let url): return ".localFile(\(url.lastPathComponent))"
            case .temporaryFile(let url): return ".temporaryFile(\(url.lastPathComponent))"
            case .collaborationFile(let f): return ".collaborationFile(\(f.name ?? "?"))"
        }
    }
}
