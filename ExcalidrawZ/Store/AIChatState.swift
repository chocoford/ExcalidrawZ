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

    struct DraftRequest: Equatable {
        let text: String
        let token: Int
    }

    private var draftTokenSeed: Int = 0

    /// Push a new draft text into the input box. Increments the internal
    /// token so SwiftUI sees a fresh value even if `text` is identical
    /// to the previous request.
    func requestDraft(_ text: String) {
        draftTokenSeed += 1
        draftRequest = DraftRequest(text: text, token: draftTokenSeed)
    }

    /// Tool-call ids that any active `RoundRevealOrchestrator` has
    /// already revealed in the UI. Used by `ApprovalPromptView` to gate
    /// itself: an approval card should appear only after its matching
    /// tool-call card has been paced into view, so the user sees what
    /// the AI is asking to run before being asked to approve it.
    /// Without this gate, a pending approval can pop up while the
    /// orchestrator is still waiting on prior content's settle delay
    /// — confusing because the tool-call card isn't visible yet.
    ///
    /// Append-only: ids stay in the set even after the round commits,
    /// since approvals reference historical tool-call ids and we don't
    /// want the gate to flip closed retroactively. Memory cost is
    /// trivial (just UUID strings).
    @Published var revealedToolCallIDs: Set<String> = []

    /// Mark a tool-call id as revealed in the UI. Idempotent — Set
    /// dedupes naturally. Caller is `AssistantRoundView` watching its
    /// orchestrator's `revealedIDs` and extracting the call-id portion
    /// of `"toolcall:<msgID>:<callID>"` element ids.
    func markToolCallRevealed(_ callID: String) {
        revealedToolCallIDs.insert(callID)
    }
}
