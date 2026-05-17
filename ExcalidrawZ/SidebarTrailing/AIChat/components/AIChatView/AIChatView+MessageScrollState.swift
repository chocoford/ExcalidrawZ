//
//  AIChatView+MessageScrollState.swift
//  ExcalidrawZ
//

import LLMCore
import LLMKit
import SwiftUI

extension AIChatView {
    /// Bridge from the active chat scroll host's scroll-animation-complete
    /// callback into our continuation map. The reveal controller awaits
    /// the matching token before fading the next message in.
    ///
    /// We resume **every** pending continuation, not just the one
    /// keyed by `token`. When two reveal tasks overlap, the second
    /// scroll request overrides the first inside the host coordinator
    /// (it tracks one in-flight token). The first task's continuation
    /// would otherwise sit unresumed until its safety timer fires —
    /// adding a visible ~0.5 s delay to its reveal. Visually, once any
    /// scroll has landed at bottom, all earlier "scroll to bottom"
    /// intents are fulfilled, so unblocking everyone is correct.
    func handleScrollAnimationComplete(token: Int) {
        guard !scrollCompletionContinuations.isEmpty else { return }
        let pending = scrollCompletionContinuations
        scrollCompletionContinuations.removeAll()
        isAutoScrollingToBottom = false
        for (_, cont) in pending {
            cont.resume()
        }
    }

    func messageWindowReconcileKey(
        scopeID: String,
        groups: [MessageGroup]
    ) -> String {
        [
            scopeID,
            groups.map(\.id).joined(separator: "|")
        ].joined(separator: "::")
    }

    func reconcileMessageWindow(groups: [MessageGroup]) {
        messageWindow.reconcile(groups: groups, scopeID: messageListSwitchID)
    }

    func loadMoreMessageGroups(from groups: [MessageGroup]) {
        guard messageWindow.hiddenGroupCount(in: groups, scopeID: messageListSwitchID) > 0 else {
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            messageWindow.loadMore(groups: groups, scopeID: messageListSwitchID)
        }
    }

    func settleMessageListAfterSwitch() {
        messageListSettleTask?.cancel()
        messageListSettleTask = Task { @MainActor in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isMessageListInitiallySettled = false
                isPinnedToBottom = true
                lastBottomID = nil
                messageWindow.reset(scopeID: messageListSwitchID)
            }

            requestScrollToBottom(animated: false)
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            requestScrollToBottom(animated: false)
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            requestScrollToBottom(animated: false)
            isMessageListInitiallySettled = true
            if !fileState.isAIChatConversationLoading {
                isHoldingConversationLoadingPlaceholder = false
            }
            messageListSettleTask = nil
        }
    }

    func messagesForCurrentEditSession(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard let editSession = activeEditSession,
              let index = messages.firstIndex(where: { message in
                  guard case .content(let content) = message else { return false }
                  return content.id == editSession.userMessageID
              })
        else {
            return messages
        }
        return Array(messages[..<index])
    }

    func scrollToBottomAsync(animated: Bool) async {
        let token = scrollToBottomRequest.token + 1
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // Store before publishing the token so a synchronous host callback
            // cannot miss the continuation.
            scrollCompletionContinuations[token] = cont
            if animated {
                isAutoScrollingToBottom = true
            }
            scrollToBottomRequest = ScrollToBottomRequest(
                token: token,
                animated: animated
            )
            Task { @MainActor in
                try? await Task.sleep(
                    for: .seconds(ChatScrollAnimation.scrollDuration + 0.5)
                )
                // Safety net for disappearing/unmounted hosts; reveal must not
                // deadlock if no completion callback arrives.
                if let pending = scrollCompletionContinuations.removeValue(forKey: token) {
                    if animated { isAutoScrollingToBottom = false }
                    pending.resume()
                }
            }
        }
    }
}
