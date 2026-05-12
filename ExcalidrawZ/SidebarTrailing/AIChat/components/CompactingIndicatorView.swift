//
//  CompactingIndicatorView.swift
//  ExcalidrawZ
//
//  Transient banner shown while LLMKit's `compactConversation` is in
//  flight. Sits in `AIChatView`'s bottom stack between the pending
//  queue and the approval card. The user sees:
//
//   - A small spinner + "Compacting context…" label so it's clear
//     why the send is being held.
//   - When the call completes, the banner disappears and the queued
//     user message fires through `drainQueueIfNeeded()` (set up by
//     `PromptInputView+Send.swift`).
//
//  No state of its own — visibility is driven by
//  `AIChatState.compactingConversationIDs` which `AIChatView`
//  watches via `isCompactingThisConversation`. The compact-finished
//  summary message itself is real (lives in the conversation), so
//  this banner is *only* for the in-flight window; nothing to
//  preserve afterward.
//

import SwiftUI
import SFSafeSymbols

struct CompactingIndicatorView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(localizable: .aiChatCompactIndicatorLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        }
    }
}
