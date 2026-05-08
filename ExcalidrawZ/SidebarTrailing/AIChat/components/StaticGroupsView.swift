//
//  StaticGroupsView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 5/4/26.
//
//  List renderer for committed (non-streaming) chat rows. Equatable on the
//  group ID sequence so SwiftUI can skip re-rendering the entire history when
//  only the in-flight stream content changes — a critical perf knob given how
//  often `stream.content` ticks during a turn.
//

import SwiftUI
import LLMCore
import LLMKit

struct StaticGroupsView: View, Equatable {
    let groups: [MessageGroup]
    let revealingAssistantRoundID: String?
    let pendingLoadingRowID: String?
    let onRegenerate: ((String) -> Void)?
    let revertableUserMessageIDs: Set<String>
    /// Per-user-message edit/revert callback. Equatable ignores closure
    /// identity, but includes `revertableUserMessageIDs` so a message can
    /// flip from edit pencil to revert affordance without changing history.
    let onUserMessageAction: ((String) -> Void)?

    init(
        groups: [MessageGroup],
        revealingAssistantRoundID: String? = nil,
        pendingLoadingRowID: String? = nil,
        onRegenerate: ((String) -> Void)? = nil,
        revertableUserMessageIDs: Set<String> = [],
        onUserMessageAction: ((String) -> Void)? = nil
    ) {
        self.groups = groups
        self.revealingAssistantRoundID = revealingAssistantRoundID
        self.pendingLoadingRowID = pendingLoadingRowID
        self.onRegenerate = onRegenerate
        self.revertableUserMessageIDs = revertableUserMessageIDs
        self.onUserMessageAction = onUserMessageAction
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groups.count == rhs.groups.count else { return false }
        return lhs.revealingAssistantRoundID == rhs.revealingAssistantRoundID
            && lhs.pendingLoadingRowID == rhs.pendingLoadingRowID
            && lhs.revertableUserMessageIDs == rhs.revertableUserMessageIDs
            && zip(lhs.groups, rhs.groups).allSatisfy { $0.id == $1.id }
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
                    onAction: onUserMessageAction
                )
            case .loading:
                EmptyView()
//                LoadingMessageRow()
//                    .transition(.opacity.animation(.smooth))
            case .error(_, let msg):
                // Retry re-runs the most recent user message preceding the
                // error. We only surface the button when both a target exists
                // *and* the parent provided a regenerate callback.
                ErrorMessageRow(
                    error: msg,
                    onRetry: previousUserMessageID(before: index).flatMap { id in
                        onRegenerate.map { regen in { regen(id) } }
                    }
                )
            case .assistantRound(let id, let messages):
                let shouldReveal = isRevealingAssistantRound(id: id, messages: messages)
                AssistantRoundView(
                    messages: messages,
                    isActive: isAssistantRoundActive(at: index),
                    revealsCommittedMessages: shouldReveal,
                    playsInitialReveal: shouldReveal,
                    keepsLoadingPlaceholderDuringReveal: shouldReveal,
                    onRegenerate: onRegenerate
                )
            case .compactSummary(let c):
                CompactSummaryRow(content: c)
        }
    }

    private func userMessageActionKind(for id: String) -> UserMessageBubble.ActionKind? {
        guard onUserMessageAction != nil else { return nil }
        return revertableUserMessageIDs.contains(id) ? .revert : .edit
    }

    /// Walks back from `index` to find the most recent user message id.
    /// Used by error rows to know *which* turn to retry.
    private func previousUserMessageID(before index: Int) -> String? {
        var i = index - 1
        while i >= 0 {
            if case .user(let c) = groups[i] { return c.id }
            i -= 1
        }
        return nil
    }

    private func previousGroupIsPendingLoading(at index: Int) -> Bool {
        guard index > 0 else { return false }
        return isLoadingRowBeforeRevealingAssistant(at: index - 1)
    }

    private func isAssistantRoundActive(at index: Int) -> Bool {
        guard index < groups.count - 1 else { return false }
        if case .loading = groups[index + 1] {
            return true
        }
        return false
    }

    private func isRevealingAssistantRound(id: String, messages: [ChatMessage]) -> Bool {
        guard let revealingAssistantRoundID else { return false }
        return id == revealingAssistantRoundID
            || messages.contains { $0.id == revealingAssistantRoundID }
    }

    private func isLoadingRowBeforeRevealingAssistant(at index: Int) -> Bool {
        guard index >= 0,
              index < groups.count - 1,
              case .loading = groups[index],
              case .assistantRound(let nextID, let nextMessages) = groups[index + 1]
        else {
            return false
        }
        guard let pendingLoadingRowID else {
            return isRevealingAssistantRound(id: nextID, messages: nextMessages)
        }
        return groups[index].id == pendingLoadingRowID
            && isRevealingAssistantRound(id: nextID, messages: nextMessages)
    }
}
