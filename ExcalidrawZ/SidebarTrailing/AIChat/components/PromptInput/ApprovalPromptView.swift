//
//  ApprovalPromptView.swift
//  ExcalidrawZ
//
//  Renders the LLMKit `pendingApprovalRequest` as an in-place prompt above
//  the input box. Self-gating: when there's no pending request the view
//  collapses to `EmptyView` so the host doesn't need conditionals — drop
//  it in any chat layout above `PromptInputView` and forget about it.
//
//  Wiring: LLMKit raises a `ToolApprovalRequest` whenever a tool's
//  `approvalRequirement` / `approvalPolicy(input:)` asks for approval.
//  The tool's `execute` is paused on a continuation;
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
        if let request = llmState.pendingApprovalRequest {
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
    
    @State private var denyReason = ""
    @FocusState private var isFocused: Bool
    
    
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
            Text(localizable: .aiChatApprovalPanelTitle)
                .font(.callout.weight(.semibold))
            Spacer()
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
                Text(localizable: .aiChatApprovalPanelButtonAllowOnce)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modernButtonStyle(style: .glass, size: .regular, shape: .modern)
            .overlay {
                Capsule().stroke(.separator, lineWidth: 0.5)
            }

            Button {
                onDecide(.approveAlways)
            } label: {
                Text(localizable: .aiChatApprovalPanelButtonAllowAlways)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modernButtonStyle(style: .glassProminent, size: .regular, shape: .modern)
            .overlay {
                Capsule().stroke(.separator, lineWidth: 0.5)
            }
            
            Button(role: .destructive) {
                onDecide(.deny(reason: nil))
            } label: {
                Text(localizable: .aiChatApprovalPanelButtonDeny)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modernButtonStyle(style: .glass, size: .regular, shape: .modern)
            .overlay {
                Capsule().stroke(.separator, lineWidth: 0.5)
            }
            .keyboardShortcut(.escape)
            
            TextField(.localizable(.aiChatApprovalPanelDenyTextFieldPlaceholder), text: $denyReason)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(Color.controlBackgroundColor)
                    Capsule().stroke(.separator, lineWidth: 0.5)
                }
                .onSubmit {
                    submitDenyReason()
                }
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(1e+9))
                        isFocused = true
                    }
                }
            
            HStack {
                Text(localizable: .aiChatApprovalPanelCancelTips).font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
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

    /// User pressed Enter in the deny-reason field. We deny with the
    /// trimmed reason if the user typed something, otherwise with `nil`
    /// — same as clicking the bare "Deny" button. LLMKit feeds the
    /// reason into the synthesised tool result observation
    /// (`"User denied execution of '<tool>'. Reason: <reason>"`), so
    /// the model sees it on its next turn and can adjust strategy.
    private func submitDenyReason() {
        let trimmed = denyReason.trimmingCharacters(in: .whitespacesAndNewlines)
        onDecide(.deny(reason: trimmed.isEmpty ? nil : trimmed))
    }

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
