//
//  StaticGroupsView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//
//  List renderer for committed (non-streaming) chat rows. Equatable on
//  the group ID sequence so SwiftUI can skip re-rendering unrelated
//  history while partial assistant messages update during a turn.
//
//  Reveal state is owned per-`AssistantRoundView` via that view's own
//  `@State`; this layer just propagates LLMKit's per-message streaming
//  ids down so each round can decide whether a committed partial message
//  is still being streamed or is eligible for reveal.
//

import SwiftUI
import LLMCore
import LLMKit

struct StaticGroupsView: View, Equatable {
    let groups: [MessageGroup]
    /// Id of the round LLMKit's stream is currently driving (`nil`
    /// when no stream is active). Forwarded into each
    /// `AssistantRoundView`; the matching round's `init` starts with
    /// an empty `revealedIDs` so every message reveals individually.
    let activeRoundID: String?
    /// Committed assistant message ids that LLMKit still considers
    /// actively streaming.
    let streamingMessageIDs: Set<String>
    let onRegenerate: ((String) -> Void)?
    let onResumeGeneration: (() -> Void)?
    let isGenerationCancelled: Bool
    let revertRequiredUserMessageIDs: Set<String>
    let showsUserMessageActions: Bool
    let disablesUserMessageActions: Bool
    let onUserMessageAction: ((String) -> Void)?

    init(
        groups: [MessageGroup],
        activeRoundID: String? = nil,
        streamingMessageIDs: Set<String> = [],
        onRegenerate: ((String) -> Void)? = nil,
        onResumeGeneration: (() -> Void)? = nil,
        isGenerationCancelled: Bool = false,
        revertRequiredUserMessageIDs: Set<String> = [],
        showsUserMessageActions: Bool = true,
        disablesUserMessageActions: Bool = false,
        onUserMessageAction: ((String) -> Void)? = nil
    ) {
        self.groups = groups
        self.activeRoundID = activeRoundID
        self.streamingMessageIDs = streamingMessageIDs
        self.onRegenerate = onRegenerate
        self.onResumeGeneration = onResumeGeneration
        self.isGenerationCancelled = isGenerationCancelled
        self.revertRequiredUserMessageIDs = revertRequiredUserMessageIDs
        self.showsUserMessageActions = showsUserMessageActions
        self.disablesUserMessageActions = disablesUserMessageActions
        self.onUserMessageAction = onUserMessageAction
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groups.count == rhs.groups.count else { return false }
        return lhs.activeRoundID == rhs.activeRoundID
            && lhs.streamingMessageIDs == rhs.streamingMessageIDs
            && lhs.isGenerationCancelled == rhs.isGenerationCancelled
            && lhs.revertRequiredUserMessageIDs == rhs.revertRequiredUserMessageIDs
            && lhs.showsUserMessageActions == rhs.showsUserMessageActions
            && lhs.disablesUserMessageActions == rhs.disablesUserMessageActions
            && zip(lhs.groups, rhs.groups).allSatisfy {
                groupSignature($0, streamingMessageIDs: lhs.streamingMessageIDs)
                    == groupSignature($1, streamingMessageIDs: rhs.streamingMessageIDs)
            }
    }

    private static func groupSignature(
        _ group: MessageGroup,
        streamingMessageIDs: Set<String>
    ) -> String {
        switch group {
            case .assistantRound(let id, let messages):
                let messageSignature = messages.map { message -> String in
                    switch message {
                        case .content(let content):
                            return [
                                content.id,
                                String(describing: content.role),
                                contentSignature(content, streamingMessageIDs: streamingMessageIDs),
                                toolCallSignature(content, streamingMessageIDs: streamingMessageIDs)
                            ].joined(separator: ":")
                        case .loading(let id):
                            return "loading:\(id.uuidString)"
                        case .error(let id, let message):
                            return "error:\(id.uuidString):\(message)"
                    }
                }.joined(separator: "|")
                return "\(id)::\(messageSignature)"
            default:
                return group.id
        }
    }

    private static func contentSignature(
        _ content: ChatMessageContent,
        streamingMessageIDs: Set<String>
    ) -> String {
        guard content.role == .assistant,
              streamingMessageIDs.contains(content.id),
              shouldHideStreamingAssistantContent(content)
        else {
            return "c\(content.content?.count ?? 0)"
        }
        return "hidden-streaming-content"
    }

    private static func toolCallSignature(
        _ content: ChatMessageContent,
        streamingMessageIDs: Set<String>
    ) -> String {
        guard let calls = content.toolCalls else { return "nil" }
        let isHiddenStreamingAssistant = content.role == .assistant
            && streamingMessageIDs.contains(content.id)
        return calls.map { call in
            if isHiddenStreamingAssistant {
                return "\(call.id):\(call.name):hidden-streaming-args"
            }
            return "\(call.id):\(call.name):a\(call.arguments.count)"
        }.joined(separator: ",")
    }

    private static func shouldHideStreamingAssistantContent(_ content: ChatMessageContent) -> Bool {
        let hasFinalCall = content.toolCalls?.contains(where: { $0.name == "final_answer" }) == true
        if hasFinalCall { return true }
        let text = displayText(of: content)
        guard !text.isEmpty else { return false }
        let hasToolCallsStarted = content.toolCalls != nil
        return !hasToolCallsStarted
    }

    private static func displayText(of content: ChatMessageContent) -> String {
        if let finalCall = content.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return content.content ?? ""
    }

    var body: some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
            ChatScrollRow {
                renderGroup(group, at: index)
            }
        }
    }

    @MainActor @ViewBuilder
    private func renderGroup(_ group: MessageGroup, at index: Int) -> some View {
        switch group {
            case .user(let c):
                UserMessageBubble(
                    content: c,
                    actionKind: userMessageActionKind(for: c.id),
                    showsAction: showsUserMessageActions,
                    isActionDisabled: disablesUserMessageActions,
                    onAction: onUserMessageAction
                )
            case .loading:
                LoadingMessageRow()
            case .error(_, let msg):
                ErrorMessageRow(
                    error: msg,
                    onRetry: onResumeGeneration
                )
            case .assistantRound(let id, let messages):
                AssistantRoundView(
                    roundID: id,
                    messages: messages,
                    activeRoundID: activeRoundID,
                    streamingMessageIDs: streamingMessageIDs,
                    isRoundCancelled: isGenerationCancelled,
                    onRegenerate: onRegenerate
                )
            case .compactSummary(let c):
                CompactSummaryRow(content: c)
        }
    }

    private func userMessageActionKind(for id: String) -> UserMessageBubble.ActionKind? {
        guard onUserMessageAction != nil else { return nil }
        return revertRequiredUserMessageIDs.contains(id) ? .revert : .edit
    }

}
