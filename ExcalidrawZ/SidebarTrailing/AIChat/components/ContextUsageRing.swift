//
//  ContextUsageRing.swift
//  ExcalidrawZ
//
//  Small ring gauge that lives next to the prompt input's attachment
//  menu and visualizes "how full is the conversation's context window."
//
//  Token counting is a heuristic — we don't ship a real tokenizer
//  client-side. Per-message char count divided by 4 (rough English
//  average) plus tool-call argument size; close enough for a "you're
//  near the limit" warning, not a billing oracle. The denominator is
//  the model's vendor-published context window, exposed via
//  `SupportedModel.approximateContextWindowTokens`.
//
//  Click action is reserved for a future "compact context" command.
//  v1 just shows the indicator; the button is there so the layout
//  doesn't shift when we wire it up later.
//

import SwiftUI
import LLMCore
import LLMKit

struct ContextUsageRing: View {
    /// The conversation we're measuring. Nil when no chat is open yet —
    /// the ring renders empty and the help text says "0 / Nk".
    let conversation: Conversation?

    /// Model whose context window we compare against. Driven by the
    /// active model from `PromptInputView` so the denominator follows
    /// the user's tier choice.
    let model: SupportedModel

    /// Hook for the future compact-context action. v1 leaves this nil
    /// and the button just shows the gauge — keeping the API in place
    /// so the next iteration can drop in a closure without touching
    /// callers.
    var onTap: (() -> Void)? = nil

    private var maxTokens: Int { model.approximateContextWindowTokens }

    private var usedTokens: Int {
        Self.estimateTokens(for: conversation)
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
    

    private var helpText: String {
        let usedK = Double(usedTokens) / 1000.0
        let maxK = Double(maxTokens) / 1000.0
        let pct = Int((fraction * 100).rounded())
        return String(format: "Context: %.1fk / %.0fk tokens (%d%%)", usedK, maxK, pct)
    }

    // MARK: - Heuristic token counter

    /// Rough char-count → tokens mapping. We don't ship a tokenizer
    /// client-side; the ring just needs "are we approaching the cap?"
    /// granularity. ~4 chars/token is the canonical English heuristic.
    /// Tool-call arguments and tool-result observations both count —
    /// they all consume the same context budget on the next round.
    static func estimateTokens(for conversation: Conversation?) -> Int {
        guard let conversation else { return 0 }
        var totalChars = 0
        for msg in conversation.messages {
            guard case .content(let c) = msg else { continue }
            totalChars += (c.content?.count ?? 0)
            for tc in c.toolCalls ?? [] {
                totalChars += tc.name.count + tc.arguments.count
            }
        }
        return totalChars / 4
    }
}
