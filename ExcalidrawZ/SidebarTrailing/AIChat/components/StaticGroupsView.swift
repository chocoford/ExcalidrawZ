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

struct StaticGroupsView: View, Equatable {
    let groups: [MessageGroup]
    let onRegenerate: ((String) -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.groups.count == rhs.groups.count else { return false }
        return zip(lhs.groups, rhs.groups).allSatisfy { $0.id == $1.id }
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
                UserMessageBubble(content: c)
            case .loading:
                LoadingMessageRow()
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
            case .assistantRound(_, let messages):
                AssistantRoundView(messages: messages, onRegenerate: onRegenerate)
        }
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
}
