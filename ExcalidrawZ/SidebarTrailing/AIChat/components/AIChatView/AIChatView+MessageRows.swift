//
//  AIChatView+MessageRows.swift
//  ExcalidrawZ
//

import LLMCore
import LLMKit
import SwiftUI

extension AIChatView {
    func chatScrollRows(
        hiddenGroupCount: Int,
        visibleGroups: [MessageGroup],
        assistantLoadingSlot: ChatAssistantLoadingSlot,
        activeRoundID: String?,
        transientError: AIChatState.TransientError?,
        streamingMessageIDs: Set<String>,
        isGenerationCancelled: Bool,
        assistantRoundRowMode: ChatScrollAssistantRoundRowMode
    ) -> [ChatScrollRowModel] {
        var rows: [ChatScrollRowModel] = []

        if hiddenGroupCount > 0 {
            rows.append(
                ChatScrollRowModel(
                    id: "hidden-history",
                    kind: .hiddenHistory(
                        hiddenGroupCount: hiddenGroupCount,
                        isLoading: messageWindow.isLoadingMore
                    )
                )
            )
        }

        for group in visibleGroups {
            if case .loading = group {
                continue
            }

            if assistantRoundRowMode == .splitSettledRows,
               case .assistantRound(let roundID, let messages) = group,
               roundID != activeRoundID {
                let items = AssistantRoundTableRows.items(
                    in: messages,
                    streamingMessageIDs: streamingMessageIDs
                )
                rows.append(
                    contentsOf: items.map { item in
                        ChatScrollRowModel(
                            id: "\(roundID):\(item.id)",
                            kind: .assistantItem(item)
                        )
                    }
                )
                if let action = AssistantRoundTableRows.action(
                    roundID: roundID,
                    messages: messages,
                    items: items
                ) {
                    rows.append(
                        ChatScrollRowModel(
                            id: action.id,
                            kind: .assistantAction(action)
                        )
                    )
                }
            } else {
                rows.append(
                    ChatScrollRowModel(
                        id: group.id,
                        kind: .group(group)
                    )
                )
            }
        }

        rows.append(
            ChatScrollRowModel(
                id: assistantLoadingSlot.id,
                kind: .assistantLoadingSlot(
                    isVisible: assistantLoadingSlot.isVisible
                )
            )
        )

        if let transientError {
            rows.append(
                ChatScrollRowModel(
                    id: "transient-error:\(transientError.id.uuidString)",
                    kind: .transientError(
                        id: transientError.id,
                        message: transientError.message
                    )
                )
            )
        }

        return rows
    }

    func assistantLoadingSlot(
        visibleGroups: [MessageGroup],
        activeRoundID: String?,
        streamingMessageIDs: Set<String>,
        isRunActive: Bool,
        isGenerationCancelled: Bool
    ) -> ChatAssistantLoadingSlot {
        let hasTimelineLoading = visibleGroups.contains { group in
            if case .loading = group { return true }
            return false
        }
        let hasActiveRoundInflight = activeRoundHasInflightMessage(
            visibleGroups: visibleGroups,
            activeRoundID: activeRoundID,
            streamingMessageIDs: streamingMessageIDs
        )
        let isWaitingForFirstAssistant = isRunActive && activeRoundID == nil
        let isReserved = hasTimelineLoading
            || hasActiveRoundInflight
            || isRunActive
            || streamScrollFollowTail

        return ChatAssistantLoadingSlot(
            id: "assistant-loading-slot:\(messageListSwitchID)",
            isVisible: !isGenerationCancelled
                && isReserved
                && (
                    hasTimelineLoading
                    || hasActiveRoundInflight
                    || isWaitingForFirstAssistant
                )
        )
    }

    func activeRoundHasInflightMessage(
        visibleGroups: [MessageGroup],
        activeRoundID: String?,
        streamingMessageIDs: Set<String>
    ) -> Bool {
        guard let activeRoundID else { return false }
        for group in visibleGroups {
            guard case .assistantRound(let id, let messages) = group,
                  id == activeRoundID
            else {
                continue
            }
            return messages.contains { message in
                guard case .content(let content) = message else { return false }
                guard content.role == .assistant else { return false }
                return streamingMessageIDs.contains(content.id)
            }
        }
        return false
    }

    func chatScrollRowRenderKey(
        _ row: ChatScrollRowModel,
        activeRoundID: String?,
        streamingMessageIDs: Set<String>,
        isGenerationCancelled: Bool,
        suppressedUserActionMessageID: String?
    ) -> String {
        switch row.kind {
            case .hiddenHistory(let hiddenGroupCount, let isLoading):
                return "hidden:\(hiddenGroupCount):loading:\(isLoading ? "1" : "0")"

            case .group(let group):
                return chatScrollGroupRenderKey(
                    group,
                    activeRoundID: activeRoundID,
                    streamingMessageIDs: streamingMessageIDs,
                    isGenerationCancelled: isGenerationCancelled,
                    suppressedUserActionMessageID: suppressedUserActionMessageID
                )

            case .assistantLoadingSlot(let isVisible):
                return "assistantLoadingSlot:visible:\(isVisible ? "1" : "0")"

            case .assistantItem(let item):
                return item.signature

            case .assistantAction(let action):
                return [
                    "assistantAction",
                    action.id,
                    "source:\(action.sourceID)",
                    "usage:\(action.usage)",
                    "copy:\(action.copyText.count)"
                ].joined(separator: ":")

            case .transientError(let id, let message):
                return "transient:\(id.uuidString):\(message)"
        }
    }

    func chatScrollGroupRenderKey(
        _ group: MessageGroup,
        activeRoundID: String?,
        streamingMessageIDs: Set<String>,
        isGenerationCancelled: Bool,
        suppressedUserActionMessageID: String?
    ) -> String {
        switch group {
            case .user(let content):
                let actionKind = userMessageActionKind(
                    for: content.id,
                    suppressedUserActionMessageID: suppressedUserActionMessageID
                )
                return [
                    messageGroupPresentationSignature(
                        group,
                        streamingMessageIDs: streamingMessageIDs
                    ),
                    "action:\(actionKind.map { String(describing: $0) } ?? "none")"
                ].joined(separator: "::")

            case .assistantRound(let id, _):
                let isActiveRound = activeRoundID == id
                return [
                    messageGroupPresentationSignature(
                        group,
                        streamingMessageIDs: streamingMessageIDs
                    ),
                    "active:\(isActiveRound ? "1" : "0")",
                    "cancel:\(isActiveRound && isGenerationCancelled ? "1" : "0")"
                ].joined(separator: "::")

            default:
                return messageGroupPresentationSignature(
                    group,
                    streamingMessageIDs: streamingMessageIDs
                )
        }
    }

    @MainActor @ViewBuilder
    func chatScrollRowContent(
        _ row: ChatScrollRowModel,
        activeRoundID: String?,
        streamingMessageIDs: Set<String>,
        isGenerationCancelled: Bool,
        suppressedUserActionMessageID: String?
    ) -> some View {
        switch row.kind {
            case .hiddenHistory(let hiddenGroupCount, let isLoading):
                ChatScrollRow {
                    HiddenHistoryIndicator(
                        hiddenGroupCount: hiddenGroupCount,
                        isLoading: isLoading
                    )
                }
            case .group(let group):
                ChatScrollRow {
                    chatScrollGroupContent(
                        group,
                        activeRoundID: activeRoundID,
                        streamingMessageIDs: streamingMessageIDs,
                        isGenerationCancelled: isGenerationCancelled,
                        suppressedUserActionMessageID: suppressedUserActionMessageID
                    )
                }
            case .assistantLoadingSlot(let isVisible):
                LoadingMessageSlot(isVisible: isVisible)
            case .assistantItem(let item):
                ChatScrollRow {
                    AssistantRoundTableItemView(
                        item: item,
                        streamingMessageIDs: streamingMessageIDs
                    )
                }
            case .assistantAction(let action):
                ChatScrollRow {
                    AssistantRoundTableActionRow(
                        action: action,
                        onRegenerate: regenerateMessage
                    )
                }
            case .transientError(_, let message):
                ChatScrollRow {
                    ErrorMessageRow(
                        error: message,
                        onRetry: {
                            guard let transientError = currentTransientError else { return }
                            retryTransientError(transientError)
                        }
                    )
                }
        }
    }

    @MainActor @ViewBuilder
    func chatScrollGroupContent(
        _ group: MessageGroup,
        activeRoundID: String?,
        streamingMessageIDs: Set<String>,
        isGenerationCancelled: Bool,
        suppressedUserActionMessageID: String?
    ) -> some View {
        switch group {
            case .user(let content):
                UserMessageBubble(
                    content: content,
                    actionKind: userMessageActionKind(
                        for: content.id,
                        suppressedUserActionMessageID: suppressedUserActionMessageID
                    ),
                    showsAction: true,
                    isActionDisabled: false,
                    onAction: beginEditingUserMessage
                )
            case .loading:
                LoadingMessageRow()
            case .error(_, let message):
                ErrorMessageRow(
                    error: message,
                    onRetry: { resumeGeneration() }
                )
            case .assistantRound(let id, let messages):
                AssistantRoundView(
                    roundID: id,
                    messages: messages,
                    activeRoundID: activeRoundID,
                    streamingMessageIDs: streamingMessageIDs,
                    isRoundCancelled: isGenerationCancelled,
                    usesExternalLoadingSlot: true,
                    onRegenerate: regenerateMessage
                )
                .equatable()
            case .compactSummary(let content):
                CompactSummaryRow(content: content)
        }
    }

    func userMessageActionKind(
        for id: String,
        suppressedUserActionMessageID: String? = nil
    ) -> UserMessageBubble.ActionKind? {
        guard id != suppressedUserActionMessageID else { return nil }
        return revertRequiredUserMessageIDs.contains(id) ? .revert : .edit
    }
}
