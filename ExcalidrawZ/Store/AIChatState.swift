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
}
