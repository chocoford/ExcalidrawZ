//
//  ApprovalPromptView.swift
//  ExcalidrawZ
//
//  Renders the LLMKit `pendingApprovalRequest` as an in-place prompt above
//  the input box. Self-gating: when there's no pending request the view
//  collapses to `EmptyView` so the host doesn't need conditionals — drop
//  it in any chat layout above `PromptInputView` and forget about it.
//
//  Wiring: LLMKit raises a `ToolApprovalRequest` whenever a tool with
//  `alwaysRequiresApproval = true` (or a non-`.autoApprove` `approvalPolicy(input:)`)
//  is about to run. The tool's `execute` is paused on a continuation;
//  `respondToApproval(_:)` resumes it with the user's choice. We expose
//  three buttons: Allow once / Always / Deny.
//

import SwiftUI
import LLMCore
import LLMKit
import SFSafeSymbols

struct ApprovalPromptView: View {
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var aiChatState: AIChatState

    var body: some View {
        // Two-step gate:
        // 1. There must be a pending approval request from LLMKit.
        // 2. The orchestrator (`AssistantRoundView`'s
        //    `RoundRevealOrchestrator`) must have already revealed the
        //    matching tool-call card, tracked via
        //    `aiChatState.revealedToolCallIDs`. Without this, an
        //    approval prompt can pop up while the orchestrator is
        //    still pacing through prior elements — the user sees
        //    "approve X?" but X's card hasn't appeared yet.
        //
        // Tool execution is paused on a continuation in LLMKit
        // regardless of when *we* show the UI; we just delay the
        // visual prompt. `respondToApproval(_:)` resumes execution
        // whenever the user actually answers.
        if let request = llmState.pendingApprovalRequest,
           aiChatState.revealedToolCallIDs.contains(request.toolCallID) {
            ApprovalCard(request: request) { decision in
                llmState.respondToApproval(decision)
            }
            .transition(.opacity)
        }
    }
}

// MARK: - Card

private struct ApprovalCard: View {
    let request: ToolApprovalRequest
    let onDecide: (ToolApprovalDecision) -> Void

    /// Details panel collapsed by default — the reason line is usually
    /// enough; raw arguments are for power users / debugging.
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            
            reasonLine
                                    
            actionsView
        }
        .padding(16)
        .background(background)

    }

    // MARK: Subviews

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemSymbol: .exclamationmarkShieldFill)
                .foregroundStyle(.orange)
            Text("Approval required")
                .font(.callout.weight(.semibold))
            Spacer()
            // Tool name pill — uses the tool's `displayName` (friendly,
            // title-cased) rather than the snake_case machine `name`,
            // which would look hostile to the user. Falls back to the
            // machine name automatically when a tool hasn't overridden
            // `displayName` (LLMKit's default impl returns `name`).
            Text(request.toolDisplayName)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(.regularMaterial))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var reasonLine: some View {
        DisclosureGroup(request.reason) {
            // Pretty-print JSON if we can; fall back to raw string. Mono
            // font + selectable so users can copy-inspect.
            ScrollView {
                Text(prettyArguments(request.arguments))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .font(.caption)
            }
            .frame(maxHeight: 120)
            .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        }
        .disclosureGroupStyle(.leadingChevron)
    }


    @ViewBuilder
    private var actionsView: some View {
        VStack(spacing: 6) {
            Button {
                onDecide(.approve)
            } label: {
                Text("Allow once")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modernButtonStyle(style: .glass, size: .regular, shape: .modern)

            Button {
                onDecide(.approveAlways)
            } label: {
                Text("Always")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modernButtonStyle(style: .glassProminent, size: .regular, shape: .modern)
            
            
            Button(role: .destructive) {
                onDecide(.deny(reason: nil))
            } label: {
                Text("Deny")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modernButtonStyle(style: .glass, size: .regular, shape: .modern)

        }
    }

    // MARK: Background

    @ViewBuilder
    private var background: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 20)
                .fill(.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.separator, lineWidth: 0.5)
                }
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.separator, lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.orange.opacity(0.5), lineWidth: 1)
    }

    // MARK: Helpers

    /// Best-effort pretty-printer: parses the raw arguments string as JSON
    /// and re-encodes with sorted keys + indentation. Falls back to the
    /// raw input if it's not valid JSON (LLM output can be janky).
    private func prettyArguments(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let str = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return str
    }
}
