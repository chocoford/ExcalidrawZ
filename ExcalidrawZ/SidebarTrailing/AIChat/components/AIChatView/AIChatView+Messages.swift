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
    @Published var hideMessageList = false
    @Published var useMinimalPromptInput = false
    @Published var hidePromptActionBar = false
    @Published var hideGeneratingEffect = false
    @Published var useStackMessageListHost = true

    func reset() {
        isEnabled = false
        hideMessageList = false
        useMinimalPromptInput = false
        hidePromptActionBar = false
        hideGeneratingEffect = false
        useStackMessageListHost = true
    }
}

enum AIChatRenderDebug {
    static let state = AIChatRenderDebugState()

    static var isEnabled: Bool {
        state.isEnabled
    }

    static var hideMessageList: Bool {
        state.hideMessageList
    }

    static var useMinimalPromptInput: Bool {
        state.useMinimalPromptInput
    }

    static var hidePromptActionBar: Bool {
        state.hidePromptActionBar
    }

    static var hideGeneratingEffect: Bool {
        state.hideGeneratingEffect
    }

    static var useStackMessageListHost: Bool {
        state.useStackMessageListHost
    }

    private static let counterStore = CounterStore()

    static func hit(_ name: String) {
        guard isEnabled else { return }
        counterStore.hit(name)
    }

    static func measure<T>(_ name: String, _ work: () -> T) -> T {
        guard isEnabled else { return work() }

        let start = CFAbsoluteTimeGetCurrent()
        let result = work()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        counterStore.hit(name, milliseconds: elapsed)
        return result
    }

    private final class CounterStore: @unchecked Sendable {
        struct TimingStats {
            var count: Int = 0
            var total: Double = 0
            var max: Double = 0

            mutating func record(_ milliseconds: Double) {
                count += 1
                total += milliseconds
                max = Swift.max(max, milliseconds)
            }
        }

        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var timings: [String: TimingStats] = [:]
        private var lastFlush = CFAbsoluteTimeGetCurrent()

        func hit(_ name: String, milliseconds: Double? = nil) {
            lock.lock()
            if let milliseconds {
                timings[name, default: TimingStats()].record(milliseconds)
            } else {
                counts[name, default: 0] += 1
            }

            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastFlush >= 1 else {
                lock.unlock()
                return
            }

            let countSnapshot = counts
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(20)
                .map { "\($0.key)=\($0.value)" }

            let timingSnapshot = timings
                .sorted { lhs, rhs in
                    if lhs.value.total == rhs.value.total { return lhs.key < rhs.key }
                    return lhs.value.total > rhs.value.total
                }
                .prefix(20)
                .map { name, stats in
                    let avg = stats.total / Double(max(stats.count, 1))
                    return String(
                        format: "%@ n=%d total=%.2fms avg=%.2fms max=%.2fms",
                        name,
                        stats.count,
                        stats.total,
                        avg,
                        stats.max
                    )
                }

            let snapshot = (countSnapshot + timingSnapshot)
                .joined(separator: " | ")

            counts.removeAll(keepingCapacity: true)
            timings.removeAll(keepingCapacity: true)
            lastFlush = now
            lock.unlock()

            if !snapshot.isEmpty {
                print("[AIChatRender] \(snapshot)")
            }
        }
    }
}
#else
enum AIChatRenderDebug {
    static func hit(_ name: String) {}

    static func measure<T>(_ name: String, _ work: () -> T) -> T {
        work()
    }

    static var hideMessageList: Bool { false }
    static var useMinimalPromptInput: Bool { false }
    static var hidePromptActionBar: Bool { false }
    static var hideGeneratingEffect: Bool { false }
    static var useStackMessageListHost: Bool { false }
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
                Text(localizable: .aiChatEmptyContentPlaceholderTitle)
                    .foregroundStyle(.secondary)
                    .font(.title3)
                Text(localizable: .aiChatEmptyContentPlaceholderDescription)
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
        let _ = AIChatRenderDebug.hit("AIChatView.messageList")

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
        let showsUserMessageActions = !isRoundLifecycleActive
        let disablesUserMessageActions = !isGenerationCancelled
        && (isRunActive || streamScrollFollowTail)
        let scrollRows = chatScrollRows(
            allGroups: allGroups,
            visibleGroups: visibleGroups,
            activeRoundID: activeRoundID,
            transientError: visibleTransientError,
            streamingMessageIDs: streamingMessageIDs,
            isGenerationCancelled: isGenerationCancelled
        )
        let isScrollStreaming = !isGenerationCancelled
            && (isRunActive || streamScrollFollowTail)

        SwiftUI.Group {
            ChatScrollView(
                rows: scrollRows,
                isPinnedToBottom: $isPinnedToBottom,
                scrollToBottomRequest: $scrollToBottomRequest,
                isStreaming: isScrollStreaming,
                rowRenderKey: { row in
                    chatScrollRowRenderKey(
                        row,
                        activeRoundID: activeRoundID,
                        streamingMessageIDs: streamingMessageIDs,
                        isGenerationCancelled: isGenerationCancelled,
                        showsUserMessageActions: showsUserMessageActions,
                        disablesUserMessageActions: disablesUserMessageActions
                    )
                },
                onReachTop: {
                    loadMoreMessageGroupsIfNeeded(totalGroupCount: allGroups.count)
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
                    showsUserMessageActions: showsUserMessageActions,
                    disablesUserMessageActions: disablesUserMessageActions
                )
                .environmentObject(aiChatState)
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
            guard !isRunActive else { return }
            requestScrollToBottomIfNeeded(bottomID)
        }
        .onChange(of: isRunActive) { nowRunning in
            if nowRunning {
                resetVisibleMessageWindowIfNeeded()
                // Just kicked off a new round (user sent / regenerate).
                // Force-pin and request an explicit scroll-to-bottom:
                // the host's growth-driven follow can race against
                // `isRunning` reaching the Coordinator (the user-
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

    func chatScrollRows(
        allGroups: [MessageGroup],
        visibleGroups: [MessageGroup],
        activeRoundID: String?,
        transientError: AIChatState.TransientError?,
        streamingMessageIDs: Set<String>,
        isGenerationCancelled: Bool
    ) -> [ChatScrollRowModel] {
        let hiddenGroupCount = max(0, allGroups.count - visibleGroups.count)
        var rows: [ChatScrollRowModel] = []

        if hiddenGroupCount > 0 {
            rows.append(
                ChatScrollRowModel(
                    id: "hidden-history",
                    kind: .hiddenHistory(
                        hiddenGroupCount: hiddenGroupCount,
                        isLoading: isLoadingOlderMessages
                    )
                )
            )
        }

        for group in visibleGroups {
            if case .assistantRound(let roundID, let messages) = group,
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
                    items: items,
                    isRoundCancelled: isGenerationCancelled
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

    func chatScrollRowRenderKey(
        _ row: ChatScrollRowModel,
        activeRoundID: String?,
        streamingMessageIDs: Set<String>,
        isGenerationCancelled: Bool,
        showsUserMessageActions: Bool,
        disablesUserMessageActions: Bool
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
                    showsUserMessageActions: showsUserMessageActions,
                    disablesUserMessageActions: disablesUserMessageActions
                )

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
        showsUserMessageActions: Bool,
        disablesUserMessageActions: Bool
    ) -> String {
        switch group {
            case .user(let content):
                return [
                    messageGroupPresentationSignature(
                        group,
                        streamingMessageIDs: streamingMessageIDs
                    ),
                    "action:\(userMessageActionKind(for: content.id).map { String(describing: $0) } ?? "none")",
                    "showAction:\(showsUserMessageActions ? "1" : "0")",
                    "disableAction:\(disablesUserMessageActions ? "1" : "0")"
                ].joined(separator: "::")

            case .assistantRound(let id, _):
                return [
                    messageGroupPresentationSignature(
                        group,
                        streamingMessageIDs: streamingMessageIDs
                    ),
                    "active:\(activeRoundID == id ? "1" : "0")",
                    "cancel:\(isGenerationCancelled ? "1" : "0")"
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
        showsUserMessageActions: Bool,
        disablesUserMessageActions: Bool
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
                        showsUserMessageActions: showsUserMessageActions,
                        disablesUserMessageActions: disablesUserMessageActions
                    )
                }
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
        showsUserMessageActions: Bool,
        disablesUserMessageActions: Bool
    ) -> some View {
        switch group {
            case .user(let content):
                UserMessageBubble(
                    content: content,
                    actionKind: userMessageActionKind(for: content.id),
                    showsAction: showsUserMessageActions,
                    isActionDisabled: disablesUserMessageActions,
                    onAction: beginEditingUserMessage
                )
            case .loading:
                LoadingMessageRow()
            case .error(_, let message):
                ErrorMessageRow(
                    error: message,
                    onRetry: resumeGeneration
                )
            case .assistantRound(let id, let messages):
                AssistantRoundView(
                    roundID: id,
                    messages: messages,
                    activeRoundID: activeRoundID,
                    streamingMessageIDs: streamingMessageIDs,
                    isRoundCancelled: isGenerationCancelled,
                    onRegenerate: regenerateMessage
                )
                .equatable()
            case .compactSummary(let content):
                CompactSummaryRow(content: content)
        }
    }

    func userMessageActionKind(for id: String) -> UserMessageBubble.ActionKind? {
        revertRequiredUserMessageIDs.contains(id) ? .revert : .edit
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
        guard !aiChatState.isGenerationCancelled(conversationID: conversationID) else {
            return []
        }
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
