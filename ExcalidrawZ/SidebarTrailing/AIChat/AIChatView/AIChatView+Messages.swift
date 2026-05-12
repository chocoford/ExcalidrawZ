//
//  AIChatView+Messages.swift
//  ExcalidrawZ
//

import ChocofordUI
import Foundation
import LLMCore
import LLMKit
import SFSafeSymbols
import SwiftUI

#if DEBUG
final class AIChatRenderDebugState: ObservableObject {
    @Published var isEnabled = false

    func reset() {
        isEnabled = false
    }
}

enum AIChatRenderDebug {
    static let state = AIChatRenderDebugState()

    static var isEnabled: Bool {
        state.isEnabled
    }

    private static let counterStore = CounterStore()

    static func hit(_ name: String) {
        guard isEnabled else { return }
        counterStore.hit(name)
    }

    private final class CounterStore: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var lastFlush = CFAbsoluteTimeGetCurrent()

        func hit(_ name: String) {
            lock.lock()
            counts[name, default: 0] += 1

            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastFlush >= 1 else {
                lock.unlock()
                return
            }

            let snapshot = counts
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(20)
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " | ")

            counts.removeAll(keepingCapacity: true)
            lastFlush = now
            lock.unlock()

            print("[AIChatRender] \(snapshot)")
        }
    }
}
#else
enum AIChatRenderDebug {
    static func hit(_ name: String) {}
}
#endif

extension AIChatView {
    @ViewBuilder
    func emptyPlaceholder() -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemSymbol: .bubbleLeftAndBubbleRight)
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 10) {
                Text("AI Chat Assistant")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                Text("Ask questions about your diagrams or get help with Excalidraw features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    func messageList(messages: [ChatMessage]) -> some View {
        let transientError = currentTransientError
        let displayMessages = messagesForCurrentEditSession(messages)
        let allGroups = groupMessages(displayMessages)
        let visibleGroups = visibleMessageGroups(from: allGroups)
        let visibleTransientError: AIChatState.TransientError? = {
            guard let transientError else { return nil }
            guard !containsErrorMessage(in: allGroups, matching: transientError.message) else {
                return nil
            }
            return transientError
        }()
        let isStreamingActive: Bool = {
            guard let stream = streamingState else { return false }
            return shouldShowStreamingMessage(stream)
        }()
        let bottomID = visibleTransientError?.id.uuidString
            ?? (isStreamingActive ? streamingState?.id : nil)
            ?? messages.last?.id
        let isRoundLifecycleActive = streamingState != nil || streamScrollFollowTail
        // The active round (if any) is the latest assistantRound while
        // the stream is in flight. This is the round whose
        // AssistantRoundView mounts in "drive every message through the
        // reveal pipeline" mode — even if multiple commits coalesce
        // before its first render, none of them are pre-marked revealed.
        let latestRoundID: String? = allGroups.last { group in
            if case .assistantRound = group { return true }
            return false
        }?.id
        let activeRoundID: String? = isStreamingActive ? latestRoundID : nil
        let streamingMessageIDs = streamingAssistantMessageIDs(
            in: allGroups,
            conversationID: fileState.aiChatConversationID
        )
        let showsUserMessageActions = !isRoundLifecycleActive
        let disablesUserMessageActions = isStreamingActive || streamScrollFollowTail
        let contentRevision = messageListContentRevision(
            allGroups: allGroups,
            visibleGroups: visibleGroups,
            activeRoundID: activeRoundID,
            transientError: visibleTransientError,
            streamingMessageIDs: streamingMessageIDs,
            showsUserMessageActions: showsUserMessageActions,
            disablesUserMessageActions: disablesUserMessageActions
        )
        NativeChatScrollView(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreamingActive || streamScrollFollowTail,
            contentRevision: contentRevision,
            onReachTop: {
                loadMoreMessageGroupsIfNeeded(totalGroupCount: allGroups.count)
            },
            onScrollAnimationComplete: { token in
                handleScrollAnimationComplete(token: token)
            }
        ) {
            messageListRows(
                allGroups: allGroups,
                visibleGroups: visibleGroups,
                activeRoundID: activeRoundID,
                transientError: visibleTransientError,
                streamingMessageIDs: streamingMessageIDs,
                showsUserMessageActions: showsUserMessageActions,
                disablesUserMessageActions: disablesUserMessageActions
            )
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
            guard !isStreamingActive else { return }
            requestScrollToBottomIfNeeded(bottomID)
        }
        .onChange(of: isStreamingActive) { nowStreaming in
            if nowStreaming {
                resetVisibleMessageWindowIfNeeded()
                // Just kicked off a new round (user sent / regenerate).
                // Force-pin and request an explicit scroll-to-bottom:
                // the host's growth-driven follow can race against
                // `isStreaming` reaching the Coordinator (the user-
                // message frame may land before SwiftUI has propagated
                // the new streaming state through `updateNSView`), so
                // without this nudge the user's message + the loading
                // dots can appear without the viewport tracking them.
                isPinnedToBottom = true
                requestScrollToBottom(animated: true)
                return
            }
            // Tail window: the per-round reveal pipeline (place →
            // scroll → wipe in) needs the scroll host's growth-driven
            // follow to stay armed past the stream end so pending
            // placeheld rows can keep pinning the viewport while they
            // fade in.
            streamScrollFollowTail = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                streamScrollFollowTail = false
            }
        }
        .task(id: revertRequirementRefreshKey(groups: visibleGroups)) {
            await refreshRevertRequiredUserMessageIDs(groups: visibleGroups)
        }
        .onChange(of: fileState.aiChatConversationID) { _ in
            resetVisibleMessageWindow()
        }
    }

    func containsErrorMessage(
        in groups: [MessageGroup],
        matching message: String
    ) -> Bool {
        groups.contains { group in
            guard case .error(_, let existingMessage) = group else { return false }
            return existingMessage == message
        }
    }

    func streamingAssistantMessageIDs(
        in groups: [MessageGroup],
        conversationID: String?
    ) -> Set<String> {
        guard let conversationID else { return [] }
        var result: Set<String> = []
        for group in groups {
            guard case .assistantRound(_, let messages) = group else { continue }
            for message in messages {
                guard case .content(let content) = message,
                      content.role == .assistant
                else {
                    continue
                }
                if llmState.isStreaming(messageID: content.id, in: conversationID) {
                    result.insert(content.id)
                }
            }
        }
        return result
    }

    func messageListContentRevision(
        allGroups: [MessageGroup],
        visibleGroups: [MessageGroup],
        activeRoundID: String?,
        transientError: AIChatState.TransientError?,
        streamingMessageIDs: Set<String>,
        showsUserMessageActions: Bool,
        disablesUserMessageActions: Bool
    ) -> String {
        let hiddenGroupCount = max(0, allGroups.count - visibleGroups.count)
        let groupSignature = visibleGroups
            .map { messageGroupPresentationSignature($0, streamingMessageIDs: streamingMessageIDs) }
            .joined(separator: "|")
        let transientErrorSignature = transientError.map {
            "\($0.id.uuidString):\($0.message)"
        } ?? "nil"
        return [
            "hidden:\(hiddenGroupCount)",
            "loadingOlder:\(isLoadingOlderMessages ? "1" : "0")",
            "activeRound:\(activeRoundID ?? "nil")",
            "streaming:\(streamingMessageIDs.sorted().joined(separator: ","))",
            "transient:\(transientErrorSignature)",
            "revert:\(revertRequiredUserMessageIDs.sorted().joined(separator: ","))",
            "userActions:\(showsUserMessageActions ? "1" : "0")",
            "disabledActions:\(disablesUserMessageActions ? "1" : "0")",
            "groups:\(groupSignature)"
        ].joined(separator: "::")
    }

    func messageGroupPresentationSignature(
        _ group: MessageGroup,
        streamingMessageIDs: Set<String>
    ) -> String {
        switch group {
            case .user(let content):
                return [
                    "user",
                    content.id,
                    "\(content.content?.count ?? 0)",
                    "files:\(content.files?.count ?? 0)"
                ].joined(separator: ":")
            case .assistantRound(let id, let messages):
                let messageSignature = messages.map { message -> String in
                    switch message {
                        case .content(let content):
                            return [
                                content.id,
                                String(describing: content.role),
                                messageContentPresentationSignature(
                                    content,
                                    streamingMessageIDs: streamingMessageIDs
                                ),
                                toolCallPresentationSignature(
                                    content,
                                    streamingMessageIDs: streamingMessageIDs
                                ),
                                "toolCallID:\(content.toolCallId ?? "nil")",
                                "files:\(content.files?.count ?? 0)"
                            ].joined(separator: ":")
                        case .loading(let id):
                            return "loading:\(id.uuidString)"
                        case .error(let id, let message):
                            return "error:\(id.uuidString):\(message)"
                    }
                }.joined(separator: "|")
                return "assistantRound:\(id)::\(messageSignature)"
            case .loading(let id):
                return "loading:\(id.uuidString)"
            case .error(let id, let message):
                return "error:\(id.uuidString):\(message)"
            case .compactSummary(let content):
                return [
                    "compactSummary",
                    content.id,
                    "\(content.content?.count ?? 0)"
                ].joined(separator: ":")
        }
    }

    func messageContentPresentationSignature(
        _ content: ChatMessageContent,
        streamingMessageIDs: Set<String>
    ) -> String {
        guard content.role == .assistant,
              streamingMessageIDs.contains(content.id),
              shouldHideStreamingAssistantContent(content)
        else {
            return "content:\(content.content?.count ?? 0)"
        }
        return "hidden-streaming-content"
    }

    func toolCallPresentationSignature(
        _ content: ChatMessageContent,
        streamingMessageIDs: Set<String>
    ) -> String {
        guard let calls = content.toolCalls else { return "toolCalls:nil" }
        let isHiddenStreamingAssistant = content.role == .assistant
            && streamingMessageIDs.contains(content.id)
        let callSignature = calls.map { call in
            if isHiddenStreamingAssistant {
                return "\(call.id):\(call.name):hidden-streaming-args"
            }
            return "\(call.id):\(call.name):args:\(call.arguments.count)"
        }.joined(separator: ",")
        return "toolCalls:\(callSignature)"
    }

    func shouldHideStreamingAssistantContent(_ content: ChatMessageContent) -> Bool {
        let hasFinalCall = content.toolCalls?.contains(where: { $0.name == "final_answer" }) == true
        if hasFinalCall { return true }
        let text = displayText(of: content)
        guard !text.isEmpty else { return false }
        let hasToolCallsStarted = content.toolCalls != nil
        return !hasToolCallsStarted
    }

    func displayText(of content: ChatMessageContent) -> String {
        if let finalCall = content.toolCalls?.first(where: { $0.name == "final_answer" }) {
            return parseFinalAnswerArgs(finalCall.arguments)
        }
        return content.content ?? ""
    }

    @ViewBuilder
    func messageListRows(
        allGroups: [MessageGroup],
        visibleGroups: [MessageGroup],
        activeRoundID: String?,
        transientError: AIChatState.TransientError?,
        streamingMessageIDs: Set<String>,
        showsUserMessageActions: Bool,
        disablesUserMessageActions: Bool
    ) -> some View {
        let hiddenGroupCount = max(0, allGroups.count - visibleGroups.count)

        if hiddenGroupCount > 0 {
            HiddenHistoryIndicator(
                hiddenGroupCount: hiddenGroupCount,
                isLoading: isLoadingOlderMessages
            )
        }

        StaticGroupsView(
            groups: visibleGroups,
            activeRoundID: activeRoundID,
            streamingMessageIDs: streamingMessageIDs,
            onRegenerate: regenerateMessage,
            revertRequiredUserMessageIDs: revertRequiredUserMessageIDs,
            showsUserMessageActions: showsUserMessageActions,
            disablesUserMessageActions: disablesUserMessageActions,
            onUserMessageAction: beginEditingUserMessage
        )

        if let transientError {
            ChatScrollRow {
                ErrorMessageRow(
                    error: transientError.message,
                    onRetry: {
                        retryTransientError(transientError)
                    }
                )
            }
            .transition(.opacity)
        }
    }

    /// Bridge from `NativeChatScrollView`'s scroll-animation-complete
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

    func visibleMessageGroups(from groups: [MessageGroup]) -> [MessageGroup] {
        guard groups.count > visibleMessageGroupLimit else { return groups }
        return Array(groups.suffix(visibleMessageGroupLimit))
    }

    func loadMoreMessageGroupsIfNeeded(totalGroupCount: Int) {
        guard !suppressOlderMessageLoading else { return }
        guard visibleMessageGroupLimit < totalGroupCount else { return }
        guard loadOlderMessagesTask == nil else { return }
        isLoadingOlderMessages = true
        loadOlderMessagesTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            loadOlderMessageGroupsNow(totalGroupCount: totalGroupCount)
            try? await Task.sleep(for: .milliseconds(120))
            isLoadingOlderMessages = false
            loadOlderMessagesTask = nil
        }
    }

    func loadOlderMessageGroupsNow(totalGroupCount: Int) {
        guard visibleMessageGroupLimit < totalGroupCount else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleMessageGroupLimit = min(
                totalGroupCount,
                visibleMessageGroupLimit + messageGroupLoadIncrement
            )
        }
    }

    func resetVisibleMessageWindowIfNeeded() {
        guard visibleMessageGroupLimit != initialVisibleMessageGroupLimit else { return }
        resetVisibleMessageWindow()
    }

    func resetVisibleMessageWindow() {
        suppressOlderMessageLoadingTemporarily()
        loadOlderMessagesTask?.cancel()
        loadOlderMessagesTask = nil
        isLoadingOlderMessages = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleMessageGroupLimit = initialVisibleMessageGroupLimit
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
                resetVisibleMessageWindow()
            }

            requestScrollToBottom(animated: false)
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            requestScrollToBottom(animated: false)
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            requestScrollToBottom(animated: false)
            isMessageListInitiallySettled = true
            messageListSettleTask = nil
        }
    }

    func suppressOlderMessageLoadingTemporarily() {
        suppressOlderMessageLoadingTask?.cancel()
        suppressOlderMessageLoading = true
        suppressOlderMessageLoadingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(ChatScrollAnimation.scrollDuration + 0.4))
            suppressOlderMessageLoading = false
            suppressOlderMessageLoadingTask = nil
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

    /// Async scroll-to-bottom: queues a token-driven scroll request and
    /// resumes when the underlying `NativeChatScrollView` reports the
    /// scroll animation has finished (or a safety timer fires).
    /// `AssistantRoundView` awaits this between "place" and "wipe in"
    /// so the reveal animation runs at the final viewport position.
    func scrollToBottomAsync(animated: Bool) async {
        let token = scrollToBottomRequest.token + 1
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // Store the continuation BEFORE triggering the scroll so a
            // synchronous completion callback (e.g. already at bottom)
            // can find it.
            scrollCompletionContinuations[token] = cont
            suppressOlderMessageLoadingTemporarily()
            if animated {
                isAutoScrollingToBottom = true
            }
            scrollToBottomRequest = ScrollToBottomRequest(
                token: token,
                animated: animated
            )
            // Safety net: if onScrollAnimationComplete never fires (host
            // not yet wired up, view about to disappear, etc.), drain the
            // continuation after the expected duration so the controller
            // doesn't deadlock.
            Task { @MainActor in
                try? await Task.sleep(
                    for: .seconds(ChatScrollAnimation.scrollDuration + 0.5)
                )
                if let pending = scrollCompletionContinuations.removeValue(forKey: token) {
                    if animated { isAutoScrollingToBottom = false }
                    pending.resume()
                }
            }
        }
    }
}
