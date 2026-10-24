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
final class AIChatPromptDraftState: ObservableObject {
    @Published var text: String = "" {
        didSet {
            AIChatRenderDebug.hit("publish.promptDraft.text")
        }
    }
    @Published var images: [PendingPastedImage] = [] {
        didSet {
            AIChatRenderDebug.hit("publish.promptDraft.images")
        }
    }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    var hasImages: Bool {
        !images.isEmpty
    }

    private var handledDraftRequestToken: Int?
    private var handledDraftImageAppendRequestToken: Int?
    private var handledEditCancelToken: Int?

    func shouldHandleDraftRequest(token: Int) -> Bool {
        guard handledDraftRequestToken != token else { return false }
        handledDraftRequestToken = token
        return true
    }

    func shouldHandleDraftImageAppendRequest(token: Int) -> Bool {
        guard handledDraftImageAppendRequestToken != token else { return false }
        handledDraftImageAppendRequestToken = token
        return true
    }

    func shouldHandleEditCancel(token: Int) -> Bool {
        guard handledEditCancelToken != token else { return false }
        handledEditCancelToken = token
        return true
    }
}

@MainActor
final class AIChatState: ObservableObject {
    nonisolated static let selectedConversationRefreshDelay: UInt64 = 350_000_000

    /// Messages typed while a reply was streaming. PromptInputView appends
    /// to this on mid-stream send, drains it FIFO when the in-flight reply
    /// finishes, and clears it on stop. Hosts read it to render the
    /// `PendingQueueView`. Shared at app scope so a message queued in
    /// the island still shows when the user docks back to the inspector
    /// (and vice versa) — and stays consistent across windows for the
    /// same reason the AI quota balance is.
    @Published var pendingQueue: [PendingQueueMessage] = []

    /// One-shot prefill request for the prompt draft owner. Driven by the
    /// per-user-message "Revert" action: the host sets this, the input
    /// field picks it up via `.onChange(of:)`, copies the text/files into
    /// its local draft state, and refocuses. Token-based so two reverts
    /// with the same text still fire the second time.
    @Published var draftRequest: DraftRequest?
    @Published var draftImageAppendRequest: DraftImageAppendRequest?
    @Published var editSession: EditSession?
    @Published var editCancelRequest: EditCancelRequest?
    @Published var transientError: TransientError?
    @Published private var cancelledGenerationTokens: [String: Int] = [:]

    struct DraftRequest: Equatable {
        let text: String
        let files: [ChatMessageContent.File]
        let draftKey: String?
        let token: Int

        static func == (lhs: DraftRequest, rhs: DraftRequest) -> Bool {
            lhs.token == rhs.token
        }
    }

    struct DraftImageAppendRequest: Equatable {
        let images: [PendingPastedImage]
        let draftKey: String?
        let token: Int

        static func == (lhs: DraftImageAppendRequest, rhs: DraftImageAppendRequest) -> Bool {
            lhs.token == rhs.token
        }
    }

    struct EditCancelRequest: Equatable {
        let draftKey: String?
        let token: Int

        static func == (lhs: EditCancelRequest, rhs: EditCancelRequest) -> Bool {
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
        let retryModelProfileID: String?

        init(
            id: UUID = UUID(),
            conversationID: String,
            userMessageID: String,
            message: String,
            retryPrompt: String,
            retryFiles: [ChatMessageContent.File],
            retryModelProfileID: String? = nil
        ) {
            self.id = id
            self.conversationID = conversationID
            self.userMessageID = userMessageID
            self.message = message
            self.retryPrompt = retryPrompt
            self.retryFiles = retryFiles
            self.retryModelProfileID = retryModelProfileID
        }
    }

    private var draftTokenSeed: Int = 0
    private var draftImageAppendTokenSeed: Int = 0
    private var editCancelTokenSeed: Int = 0
    private var promptDraftStates: [String: AIChatPromptDraftState] = [:]

    func promptDraftState(
        conversationID: String?,
        fileScope: AIConversationFileScope?
    ) -> AIChatPromptDraftState {
        let key = promptDraftKey(conversationID: conversationID, fileScope: fileScope)
        return promptDraftState(forKey: key)
    }

    func promptDraftState(forKey key: String) -> AIChatPromptDraftState {
        if let existing = promptDraftStates[key] {
            return existing
        }
        let state = AIChatPromptDraftState()
        promptDraftStates[key] = state
        return state
    }

    func promptDraftKey(
        conversationID: String?,
        fileScope: AIConversationFileScope?
    ) -> String {
        if let conversationID, !conversationID.isEmpty {
            return "conversation:\(conversationID)"
        }
        if let fileScope {
            return "file:\(fileScope.kind.rawValue):\(fileScope.id)"
        }
        return "unscoped"
    }

    /// Push a new draft text into the input box. Increments the internal
    /// token so SwiftUI sees a fresh value even if `text` is identical
    /// to the previous request.
    func requestDraft(
        _ text: String,
        files: [ChatMessageContent.File] = [],
        draftKey: String? = nil
    ) {
        if let draftKey {
            let state = promptDraftState(forKey: draftKey)
            state.text = text
            state.images = PastedImageHelpers.pendingImages(from: files)
        }
        draftTokenSeed += 1
        draftRequest = DraftRequest(
            text: text,
            files: files,
            draftKey: draftKey,
            token: draftTokenSeed
        )
    }

    func requestAppendDraftImages(
        _ images: [PendingPastedImage],
        draftKey: String? = nil
    ) {
        guard !images.isEmpty else { return }
        if let draftKey {
            promptDraftState(forKey: draftKey).images.append(contentsOf: images)
            return
        }
        draftImageAppendTokenSeed += 1
        draftImageAppendRequest = DraftImageAppendRequest(
            images: images,
            draftKey: draftKey,
            token: draftImageAppendTokenSeed
        )
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
        requestDraft(
            text,
            files: files,
            draftKey: promptDraftKey(conversationID: conversationID, fileScope: nil)
        )
    }

    func finishEditing() {
        editSession = nil
    }

    func cancelEditing(conversationID: String? = nil) {
        let draftKey = conversationID.map {
            promptDraftKey(conversationID: $0, fileScope: nil)
        }
        if let draftKey {
            let state = promptDraftState(forKey: draftKey)
            state.text = ""
            state.images = []
        }
        editSession = nil
        editCancelTokenSeed += 1
        editCancelRequest = EditCancelRequest(
            draftKey: draftKey,
            token: editCancelTokenSeed
        )
    }

    func presentTransientError(
        _ error: Error,
        conversationID: String,
        userMessageID: String,
        retryPrompt: String,
        retryFiles: [ChatMessageContent.File],
        retryModelProfileID: String? = nil
    ) {
        guard !(error is CancellationError) else { return }
        transientError = TransientError(
            conversationID: conversationID,
            userMessageID: userMessageID,
            message: (AIInferenceErrorMessage.localizedError(for: error) ?? error).localizedDescription,
            retryPrompt: retryPrompt,
            retryFiles: retryFiles,
            retryModelProfileID: retryModelProfileID
        )
    }

    func clearTransientError(for conversationID: String) {
        guard transientError?.conversationID == conversationID else { return }
        transientError = nil
    }

    func markGenerationCancelled(conversationID: String) {
        cancelledGenerationTokens[conversationID, default: 0] += 1
    }

    func clearGenerationCancellation(for conversationID: String) {
        cancelledGenerationTokens[conversationID] = nil
    }

    func generationCancelToken(for conversationID: String) -> Int {
        cancelledGenerationTokens[conversationID] ?? 0
    }

    func isGenerationCancelled(conversationID: String) -> Bool {
        cancelledGenerationTokens[conversationID] != nil
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
    /// Pre-select the most recent conversation tied to the current active
    /// file. Called on every file change (typically driven by a `.task(id:)`
    /// on `ContentView`), so by the time the user opens an AI surface the
    /// right conversation id is already pinned.
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
        fileState: FileState
    ) async {
        let activeFile = fileState.currentActiveFile
        let activeFileScope = activeFile?.aiConversationFileScope
        guard activeFileScope != nil else {
            await MainActor.run {
                guard fileState.currentActiveFile == nil else { return }
                fileState.aiChatConversationID = nil
                fileState.isAIChatConversationLoading = false
            }
            return
        }

        let chosen = await pickLatestConversationID(forActiveFile: activeFile)
        await MainActor.run {
            guard fileState.currentActiveFile?.aiConversationFileScope == activeFileScope else {
                return
            }
            fileState.aiChatConversationID = chosen
            fileState.isAIChatConversationLoading = false
        }
    }

    /// Restore the global LLMKit conversation cache only when an AI surface
    /// actually needs to render or send against the selected conversation.
    /// File switching only pins the id; doing the full restore there can
    /// resolve every historical attachment and make canvas transitions stutter.
    func refreshSelectedConversationCacheIfNeeded(
        in llmState: LLMStateObject,
        fileState: FileState
    ) async {
        guard let conversationID = fileState.aiChatConversationID else { return }
        guard llmState.getConversation(by: conversationID) == nil else { return }
        await llmState.refreshConversations()
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
            return nil
        }
        let repo = PersistenceController.shared.aiConversationRepository
        do {
            return try await repo.fetchLatestConversationIDWithActivity(forFileScope: scope)
        } catch {
            return nil
        }
    }

}
