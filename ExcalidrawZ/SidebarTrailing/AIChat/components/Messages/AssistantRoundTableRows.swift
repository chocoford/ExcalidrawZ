//
//  AssistantRoundTableRows.swift
//  ExcalidrawZ
//

import SwiftUI
import ChocofordUI
import LLMCore
import SFSafeSymbols

struct AssistantRoundTableItem: Identifiable {
    enum Kind {
        case assistantContent(ChatMessageContent)
        case toolCall(messageID: String, call: ToolCall, isDenied: Bool)
        case toolResult(ChatMessageContent)
    }

    let id: String
    let signature: String
    let kind: Kind
}

struct AssistantRoundTableAction: Identifiable {
    let id: String
    let copyText: String
    let sourceID: String
    let usage: Double
}

struct AssistantRoundTableItemView: View {
    let item: AssistantRoundTableItem
    let streamingMessageIDs: Set<String>

    var body: some View {
        switch item.kind {
            case .assistantContent(let content):
                let text = AssistantRoundTableRows.displayText(of: content)
                if !text.isEmpty {
                    SmoothStreamingText(
                        target: text,
                        isStreaming: streamingMessageIDs.contains(content.id)
                    )
                    .padding(.bottom, 6)
                }
            case .toolCall(let messageID, let call, let isDenied):
                ToolCallCard(
                    call: call,
                    isActive: streamingMessageIDs.contains(messageID),
                    isDenied: isDenied
                )
            case .toolResult(let content):
                ToolResultCard(content: content)
        }
    }
}

struct AssistantRoundTableActionRow: View {
    let action: AssistantRoundTableAction
    let onRegenerate: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            CopyButton(text: action.copyText)
            if let onRegenerate {
                Button {
                    onRegenerate(action.sourceID)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .foregroundStyle(.secondary)
                .help("Regenerate response")
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemSymbol: .boltCircle)
                Text(action.usage.formatted(.number.precision(.fractionLength(2))))
            }
            .font(.footnote)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(.regularMaterial)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.text(size: .normal, square: true))
    }
}

enum AssistantRoundTableRows {
    static func items(
        in messages: [ChatMessage],
        streamingMessageIDs: Set<String>
    ) -> [AssistantRoundTableItem] {
        var result: [AssistantRoundTableItem] = []
        for message in messages {
            guard case .content(let content) = message else { continue }
            switch content.role {
                case .tool:
                    result.append(
                        AssistantRoundTableItem(
                            id: "\(content.id):toolResult",
                            signature: "toolResult:\(content.id):c\(content.content?.count ?? 0):files:\(content.files?.count ?? 0)",
                            kind: .toolResult(content)
                        )
                    )
                case .assistant:
                    let isStreaming = streamingMessageIDs.contains(content.id)
                    let text = displayText(of: content)
                    let hasFinalCall = hasFinalAnswerToolCall(in: content)
                    let hasToolCallsStarted = content.toolCalls != nil
                    let contentIsStable = !isStreaming
                        || (!hasFinalCall && hasToolCallsStarted && !text.isEmpty)

                    if !text.isEmpty {
                        guard contentIsStable else { return result }
                        result.append(
                            AssistantRoundTableItem(
                                id: "\(content.id):content",
                                signature: "assistantContent:\(content.id):c\(text.count):streaming:\(isStreaming ? "1" : "0")",
                                kind: .assistantContent(content)
                            )
                        )
                    }

                    let nonFinalCalls = nonFinalToolCalls(in: content)
                    if !nonFinalCalls.isEmpty {
                        result.append(
                            contentsOf: nonFinalCalls.map { call in
                                AssistantRoundTableItem(
                                    id: "\(content.id):toolCall:\(call.id)",
                                    signature: "toolCall:\(content.id):\(call.id):\(call.name):a\(isStreaming ? -1 : call.arguments.count)",
                                    kind: .toolCall(
                                        messageID: content.id,
                                        call: call,
                                        isDenied: isCallDenied(call, in: messages)
                                    )
                                )
                            }
                        )
                    } else if isStreaming {
                        return result
                    }
                default:
                    continue
            }
        }
        return result
    }

    static func action(
        roundID: String,
        messages: [ChatMessage],
        items: [AssistantRoundTableItem],
        isRoundCancelled: Bool
    ) -> AssistantRoundTableAction? {
        guard let content = lastActionableAssistantContent(in: items) else { return nil }
        guard hasTerminalActionableAssistantContent(content, isRoundCancelled: isRoundCancelled) else {
            return nil
        }
        let copyText = items
            .compactMap { item -> String? in
                guard case .assistantContent(let content) = item.kind else { return nil }
                let text = displayText(of: content)
                return text.isEmpty ? nil : text
            }
            .joined(separator: "\n\n")
        guard !copyText.isEmpty else { return nil }
        let usage = messages.reduce(0) { $0 + ($1.usage?.consumed ?? 0) }
        return AssistantRoundTableAction(
            id: "\(roundID):action",
            copyText: copyText,
            sourceID: content.id,
            usage: usage
        )
    }

    static func displayText(of content: ChatMessageContent) -> String {
        if let finalCall = content.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return content.content ?? ""
    }

    private static func isCallDenied(_ call: ToolCall, in messages: [ChatMessage]) -> Bool {
        messages.contains { msg in
            guard case .content(let content) = msg,
                  content.role == .tool,
                  content.toolCallId == call.id else { return false }
            return content.content?.hasPrefix("User denied execution of") == true
        }
    }

    private static func lastActionableAssistantContent(
        in items: [AssistantRoundTableItem]
    ) -> ChatMessageContent? {
        for item in items.reversed() {
            guard case .assistantContent(let content) = item.kind,
                  !displayText(of: content).isEmpty else {
                continue
            }
            return content
        }
        return nil
    }

    private static func hasTerminalActionableAssistantContent(
        _ content: ChatMessageContent,
        isRoundCancelled: Bool
    ) -> Bool {
        if isRoundCancelled { return true }
        if hasFinalAnswerToolCall(in: content) { return true }
        return nonFinalToolCalls(in: content).isEmpty
    }

    private static func nonFinalToolCalls(in content: ChatMessageContent) -> [ToolCall] {
        (content.toolCalls ?? []).filter { $0.name != "final_answer" }
    }

    private static func hasFinalAnswerToolCall(in content: ChatMessageContent) -> Bool {
        content.toolCalls?.contains(where: { $0.name == "final_answer" }) == true
    }
}
