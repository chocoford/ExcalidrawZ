//
//  ContextUsageRing.swift
//  ExcalidrawZ
//
//  Small ring gauge that lives next to the prompt input's attachment
//  menu and visualizes "how full is the conversation's context window."
//
//  Token counting is provided by LLMKit so the gauge and auto-compact
//  trigger share the same active-context estimate. The denominator is
//  the model context window exposed by LLMCore.
//
//  Click action is reserved for a future "compact context" command.
//  v1 just shows the indicator; the button is there so the layout
//  doesn't shift when we wire it up later.
//

import SwiftUI
import LLMCore
import LLMKit

struct ContextUsageRing: View {
    @EnvironmentObject var llmState: LLMStateObject

    /// The conversation we're measuring. Nil when no chat is open yet.
    let conversationID: String?

    /// Model whose context window we compare against. Driven by the
    /// active model from `PromptInputView` so the denominator follows
    /// the user's tier choice.
    let model: SupportedModel

    /// Hook for the future compact-context action. v1 leaves this nil
    /// and the button just shows the gauge — keeping the API in place
    /// so the next iteration can drop in a closure without touching
    /// callers.
    var onTap: (() -> Void)? = nil

    private var maxTokens: Int { model.maxContextTokens ?? 0 }

    private var usedTokens: Int {
        guard let conversationID else { return 0 }
        return llmState.estimatedTokenUsage(in: conversationID)
    }

    private var fraction: Double {
        guard maxTokens > 0 else { return 0 }
        return min(1, Double(usedTokens) / Double(maxTokens))
    }

    /// Color shifts as the ring fills. Stays quiet until the user is
    /// over halfway so it doesn't add visual noise on every fresh chat.
    private var ringColor: Color {
        switch fraction {
            case ..<0.5: return .secondary
            case ..<0.8: return .yellow
            default: return .orange
        }
    }

    var body: some View {
        ZStack {
            if fraction > 0.5 {
                Button {
                    onTap?()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.secondary.opacity(0.25), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.25), value: fraction)
                    }
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
                }
                .help(helpText)
                .accessibilityLabel("Context usage")
                .accessibilityValue(Text(helpText))
            }
        }
        .animation(.smooth, value: fraction < 0.5)
    }
    

    private var helpText: String {
        let pct = Int((fraction * 100).rounded())
        return String(format: "%d%% of context used before auto-compact.\nClick to compact now", pct)
    }
}
