//
//  StaticGroupsView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//
//  List renderer for committed (non-streaming) chat rows. Equatable on
//  the group ID sequence so SwiftUI can skip re-rendering the entire
//  history when only the in-flight stream content changes — a critical
//  perf knob given how often `stream.content` ticks during a turn.
//
//  Reveal state is owned per-`AssistantRoundView` via that view's own
//  `@State`; this layer just propagates the streaming context
//  (`streamingID` / `streamFinished`) down so each round can decide,
//  for each of its messages, whether the message is "complete" (and
//  therefore eligible for the reveal animation) or still being
//  streamed.
//

import SwiftUI
import LLMCore
import LLMKit

struct StaticGroupsView: View, Equatable {
    let groups: [MessageGroup]
    /// Id LLMKit is currently streaming, propagated from `AIChatView`.
    /// Each `AssistantRoundView` compares it against its own messages
    /// to find a streaming target.
    let streamingID: String?
    /// True when the in-flight stream is finished. Combined with
    /// `streamingID`: a round message whose id equals `streamingID`
    /// is "currently streaming" only while `!streamFinished`.
    let streamFinished: Bool
    /// Id of the round LLMKit's stream is currently driving (`nil`
    /// when no stream is active). Forwarded into each
    /// `AssistantRoundView`; the matching round's `init` starts with
    /// an empty `revealedIDs` so every message reveals individually.
    let activeRoundID: String?
    let onRegenerate: ((String) -> Void)?
    let revertRequiredUserMessageIDs: Set<String>
    let disablesUserMessageActions: Bool
    let onUserMessageAction: ((String) -> Void)?

    init(
        groups: [MessageGroup],
        streamingID: String? = nil,
        streamFinished: Bool = true,
        activeRoundID: String? = nil,
        onRegenerate: ((String) -> Void)? = nil,
        revertRequiredUserMessageIDs: Set<String> = [],
        disablesUserMessageActions: Bool = false,
        onUserMessageAction: ((String) -> Void)? = nil
    ) {
        self.groups = groups
        self.streamingID = streamingID
        self.streamFinished = streamFinished
        self.activeRoundID = activeRoundID
        self.onRegenerate = onRegenerate
        self.revertRequiredUserMessageIDs = revertRequiredUserMessageIDs
        self.disablesUserMessageActions = disablesUserMessageActions
        self.onUserMessageAction = onUserMessageAction
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groups.count == rhs.groups.count else { return false }
        return lhs.streamingID == rhs.streamingID
            && lhs.streamFinished == rhs.streamFinished
            && lhs.activeRoundID == rhs.activeRoundID
            && lhs.revertRequiredUserMessageIDs == rhs.revertRequiredUserMessageIDs
            && lhs.disablesUserMessageActions == rhs.disablesUserMessageActions
            && zip(lhs.groups, rhs.groups).allSatisfy { groupSignature($0) == groupSignature($1) }
    }

    private static func groupSignature(_ group: MessageGroup) -> String {
        switch group {
            case .assistantRound(let id, let messages):
                let messageSignature = messages.map { message -> String in
                    switch message {
                        case .content(let content):
                            let toolCallIDs = (content.toolCalls ?? []).map(\.id).joined(separator: ",")
                            return [
                                content.id,
                                String(describing: content.role),
                                "\(content.content?.count ?? 0)",
                                toolCallIDs
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
                    isActionDisabled: disablesUserMessageActions,
                    onAction: onUserMessageAction
                )
            case .loading:
                EmptyView()
            case .error(_, let msg):
                ErrorMessageRow(
                    error: msg,
                    onRetry: previousUserMessageID(before: index).flatMap { id in
                        onRegenerate.map { regen in { regen(id) } }
                    }
                )
            case .assistantRound(let id, let messages):
                AssistantRoundView(
                    roundID: id,
                    messages: messages,
                    streamingID: streamingID,
                    streamFinished: streamFinished,
                    activeRoundID: activeRoundID,
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

    private func previousUserMessageID(before index: Int) -> String? {
        var i = index - 1
        while i >= 0 {
            if case .user(let c) = groups[i] { return c.id }
            i -= 1
        }
        return nil
    }
}
