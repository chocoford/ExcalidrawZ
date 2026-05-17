//
//  AIChatView+Messages.swift
//  ExcalidrawZ
//

import ChocofordUI
import LLMCore
import LLMKit
import SFSafeSymbols
import SwiftUI

extension AIChatView {
    @ViewBuilder
    func messageList(messages: [ChatMessage]) -> some View {
        let _ = AIChatRenderDebug.hit("AIChatView.messageList")

        let transientError = currentTransientError
        let displayMessages = messagesForCurrentEditSession(messages)
        let allGroups = groupMessages(displayMessages)
        let scrollConfiguration = ChatScrollConfiguration.automatic
        let visibleGroups = scrollConfiguration.usesMessageWindowing
            ? messageWindow.visibleGroups(
                from: allGroups,
                scopeID: messageListSwitchID
            )
            : allGroups
        let hiddenGroupCount = scrollConfiguration.usesMessageWindowing
            ? messageWindow.hiddenGroupCount(
                in: allGroups,
                scopeID: messageListSwitchID
            )
            : 0
        let visibleTransientError: AIChatState.TransientError? = {
            guard let transientError else { return nil }
            guard !containsErrorMessage(in: allGroups, matching: transientError.message) else {
                return nil
            }
            return transientError
        }()
        let isRunActive = fileState.aiChatConversationID.map {
            llmState.isRunning(conversationID: $0)
        } ?? false
        let generationCancelToken = fileState.aiChatConversationID.map {
            aiChatState.generationCancelToken(for: $0)
        } ?? 0
        let isGenerationCancelled = fileState.aiChatConversationID.map {
            aiChatState.isGenerationCancelled(conversationID: $0)
        } ?? false
        let bottomID = visibleTransientError?.id.uuidString
        ?? (isRunActive ? streamingState?.id : nil)
        ?? messages.last?.id
        let isRoundLifecycleActive = !isGenerationCancelled
        && (isRunActive || streamScrollFollowTail)
        // The active round (if any) must be the timeline tail. Right
        // after the user sends a new message, the latest assistant round
        // is still the previous turn; marking that historical round active
        // would remount it in reveal mode and replay all of its rows.
        let tailRoundID: String? = {
            guard case .assistantRound(let id, _) = allGroups.last else { return nil }
            return id
        }()
        let activeRoundID: String? = isRoundLifecycleActive ? tailRoundID : nil
        let streamingMessageIDs = streamingAssistantMessageIDs(
            in: allGroups,
            conversationID: fileState.aiChatConversationID
        )
        let suppressedUserActionMessageID = fileState.aiChatSession?.userMessageID
        let loadingSlot = assistantLoadingSlot(
            visibleGroups: visibleGroups,
            activeRoundID: activeRoundID,
            streamingMessageIDs: streamingMessageIDs,
            isRunActive: isRunActive,
            isGenerationCancelled: isGenerationCancelled
        )
        let scrollRows = chatScrollRows(
            hiddenGroupCount: hiddenGroupCount,
            visibleGroups: visibleGroups,
            assistantLoadingSlot: loadingSlot,
            activeRoundID: activeRoundID,
            transientError: visibleTransientError,
            streamingMessageIDs: streamingMessageIDs,
            isGenerationCancelled: isGenerationCancelled,
            assistantRoundRowMode: scrollConfiguration.assistantRoundRowMode
        )
        let isScrollStreaming = !isGenerationCancelled
            && (isRunActive || streamScrollFollowTail)

        SwiftUI.Group {
            ChatScrollView(
                rows: scrollRows,
                isPinnedToBottom: $isPinnedToBottom,
                scrollToBottomRequest: $scrollToBottomRequest,
                isStreaming: isScrollStreaming,
                configuration: scrollConfiguration,
                rowRenderKey: { row in
                    chatScrollRowRenderKey(
                        row,
                        activeRoundID: activeRoundID,
                        streamingMessageIDs: streamingMessageIDs,
                        isGenerationCancelled: isGenerationCancelled,
                        suppressedUserActionMessageID: suppressedUserActionMessageID
                    )
                },
                onReachTop: {
                    guard scrollConfiguration.usesMessageWindowing else { return }
                    loadMoreMessageGroups(from: allGroups)
                },
                onScrollAnimationComplete: { token in
                    handleScrollAnimationComplete(token: token)
                }
            ) { row in
                chatScrollRowContent(
                    row,
                    activeRoundID: activeRoundID,
                    streamingMessageIDs: streamingMessageIDs,
                    isGenerationCancelled: isGenerationCancelled,
                    suppressedUserActionMessageID: suppressedUserActionMessageID
                )
                .environment(\.chatScrollToBottom) { animated in
                    await scrollToBottomAsync(animated: animated)
                }
            }
        }
        .environment(\.chatScrollToBottom) { animated in
            await scrollToBottomAsync(animated: animated)
        }
        .overlay(alignment: .bottom) {
            if !isPinnedToBottom && !isAutoScrollingToBottom {
                Button {
                    requestScrollToBottom(animated: true)
                    isPinnedToBottom = true
                } label: {
                    Image(systemSymbol: .arrowDown)
                }
                .modernButtonStyle(style: .glass, shape: .circle)
                .transition(.opacity)
                .padding()
            }
        }
        .onAppear {
            requestScrollToBottomIfNeeded(bottomID)
        }
        .onChange(of: bottomID) { _ in
            requestScrollToBottomIfNeeded(bottomID)
        }
        .onChange(of: isRunActive) { nowRunning in
            if nowRunning {
                // A run begins after the user's message is already inserted;
                // keep the new tail visible even if the user was previously mid-list.
                isPinnedToBottom = true
                requestScrollToBottom(animated: true)
                return
            }
            // After the final token/tool result, reveal tasks may still be
            // placing rows. Keep tail-following armed briefly for that cleanup.
            streamScrollFollowTail = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                streamScrollFollowTail = false
            }
        }
        .task(id: revertRequirementRefreshKey(groups: visibleGroups)) {
            await refreshRevertRequiredUserMessageIDs(groups: visibleGroups)
        }
        .task(id: messageWindowReconcileKey(scopeID: messageListSwitchID, groups: allGroups)) {
            guard scrollConfiguration.usesMessageWindowing else { return }
            reconcileMessageWindow(groups: allGroups)
        }
    }
}
