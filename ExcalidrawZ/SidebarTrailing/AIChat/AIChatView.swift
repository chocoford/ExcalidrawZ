//
//  AIChatView.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/09.
//

import ChocofordUI
import CoreData
import LLMCore
import LLMKit
import SFSafeSymbols
import SwiftUI

struct AIChatView: View {
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var llmState: LLMStateObject
    @EnvironmentObject private var aiChatState: AIChatState
    @Environment(\.alertToast) private var alertToast
    
    /// Conversation id lives on `FileState` (chats are scoped to the current
    /// file). We bridge it to a `Binding` for `PromptInputView`'s API and so
    /// the inspector and the island both write back to the same place.
    private var conversationID: Binding<String?> {
        Binding(
            get: { fileState.aiChatConversationID },
            set: { fileState.aiChatConversationID = $0 }
        )
    }
    
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    @State private var lastBottomID: String?
    @State private var isPinnedToBottom: Bool = true
    @State private var scrollToBottomRequest = ScrollToBottomRequest()
    @State private var isAutoScrollingToBottom: Bool = false
    @State private var streamScrollFollowTail: Bool = false
    @State private var isMessageListInitiallySettled: Bool = false
    @State private var messageListSettleTask: Task<Void, Never>?
    /// Resumed by `onScrollAnimationComplete` from `NativeChatScrollView`,
    /// keyed by the scroll-request token. Lets `AssistantRoundView`'s
    /// reveal pipeline `await scrollToBottom` and only run the wipe
    /// after the smooth scroll has actually reached the new bottom.
    @State private var scrollCompletionContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    @State private var revertRequiredUserMessageIDs: Set<String> = []
    @State private var visibleMessageGroupLimit: Int = 20
    @State private var isLoadingOlderMessages: Bool = false
    @State private var loadOlderMessagesTask: Task<Void, Never>?
    @State private var suppressOlderMessageLoading: Bool = false
    @State private var suppressOlderMessageLoadingTask: Task<Void, Never>?
    /// Confirmation dialog for the "Clear chat" toolbar action — destructive,
    /// so we route through a confirmationDialog rather than firing on tap.
    @State private var isConfirmingClear: Bool = false

    /// Tapped Get Started on the first-run welcome cover. We only fall back
    /// on the `conversations` count for "first-time visitor" detection;
    /// once dismissed in this view we never want to flash the cover again
    /// even if the user clears all chats from the More menu.
    @State private var hasDismissedWelcome: Bool = false
    @State private var isShowingWelcomeManually: Bool = false

    private let initialVisibleMessageGroupLimit = 20
    private let messageGroupLoadIncrement = 20

    /// Show the welcome cover when no conversations exist anywhere yet AND
    /// the user hasn't already dismissed it. We treat `nil` (cache not
    /// loaded) as "don't show yet" — flashing the welcome before LLMKit
    /// finishes its first refresh would feel jumpy.
    private var shouldShowWelcome: Bool {
        if isShowingWelcomeManually { return true }
        guard !hasDismissedWelcome else { return false }
        guard let convos = llmState.conversations.value else { return false }
        return convos.isEmpty
    }

    private var messageListSwitchID: String {
        [
            fileState.currentActiveFile?.id ?? "nil",
            fileState.aiChatConversationID ?? "nil"
        ].joined(separator: "|")
    }
    
    var conversation: Conversation? {
        llmState.conversations.value?.first { $0.id == fileState.aiChatConversationID }
    }
    
    private var streamingState: LLMStreamingStateObject? {
        guard let id = fileState.aiChatConversationID else { return nil }
        return llmState.streamingStore.streamIfExists(for: id)
        as? LLMStreamingStateObject
    }

    /// Mirrors `ApprovalPromptView`'s internal gate. Used as the
    /// `.animation(value:)` driver on the bottom VStack so the card's
    /// appearance/disappearance smoothly slides the input box without
    /// SwiftUI seeing an "unmotivated" layout change.
    private var shouldShowApprovalCard: Bool {
        llmState.pendingApprovalRequest != nil
    }

    /// True while LLMKit's `compactConversation` is running on the
    /// conversation we're rendering. Drives the transient "compacting…"
    /// banner in the bottom stack so the user knows the next send is
    /// being held until the summary lands.
    private var isCompactingThisConversation: Bool {
        aiChatState.isCompacting(conversationID: fileState.aiChatConversationID)
    }

    private var creditsDisplayText: String {
        let balance = llmState.creditsInfo?.balance ?? 0
        return balance.formatted(.number.precision(.fractionLength(2)))
    }
    
    var body: some View {
        ZStack {
            if shouldShowWelcome {
                AIChatWelcomeView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasDismissedWelcome = true
                        isShowingWelcomeManually = false
                    }
                }
                .transition(.opacity)
            } else {
                chatBody
                    .transition(.opacity)
            }
        }
        .toolbar(content: toolbar)
        .confirmationDialog(
            "Clear chat?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear chat", role: .destructive) {
                clearCurrentConversation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages in this conversation will be removed. The drawing file is unaffected.")
        }
    }

    @ViewBuilder
    private var chatBody: some View {
        VStack(spacing: 0) {
            ZStack {
                if let conversation, !conversation.messages.isEmpty {
                    messageList(messages: conversation.messages)
                } else if currentTransientError != nil {
                    messageList(messages: conversation?.messages ?? [])
                } else {
                    emptyPlaceholder()
                }
            }
            .opacity(isMessageListInitiallySettled ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isMessageListInitiallySettled)
            
            VStack(spacing: 6) {
                PendingQueueView(
                    messages: aiChatState.pendingQueue,
                    onRemove: { id in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            aiChatState.pendingQueue.removeAll { $0.id == id }
                        }
                    }
                )

                if isCompactingThisConversation {
                    CompactingIndicatorView()
                        .transition(.opacity)
                }

                ZStack(alignment: .top) {
                    PromptInputView(
                        conversationID: conversationID,
                        pendingQueue: $aiChatState.pendingQueue
                    ) {
                        if let editSession = activeEditSession {
                            EditSessionBanner(
                                mode: editSession.mode,
                                onCancel: { aiChatState.cancelEditing() }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .disabled(llmState.pendingApprovalRequest != nil)
                    
                    ApprovalPromptView()
                }
            }
            .padding(.horizontal, 10)
            // Animate the approval card's appearance/disappearance so
            // the input box doesn't jump when the card flips visibility.
            // Drive the animation off the *gate result* (request present
            // AND its tool-call already revealed), not just the request
            // id — otherwise SwiftUI would treat the gate-driven flip
            // as an unanimated layout change.
            .animation(
                .easeInOut(duration: 0.25),
                value: shouldShowApprovalCard
            )
            .animation(
                .easeInOut(duration: 0.2),
                value: isCompactingThisConversation
            )
            .animation(
                .easeInOut(duration: 0.2),
                value: activeEditSession
            )
        }
        .padding(.bottom, 10)
        // The approval card eats vertical space from the chat scroll
        // view. Without an explicit nudge the messages slide up but the
        // viewport's last-row anchor stays where it was — the user ends
        // up looking at the middle of the conversation while the prompt
        // they need to answer is offscreen. Re-pin to bottom whenever
        // the card appears so the trailing message + the approval card
        // are both in view together.
        .onChange(of: shouldShowApprovalCard) { showing in
            guard showing else { return }
            isPinnedToBottom = true
            requestScrollToBottom(animated: true)
        }
        .task(id: messageListSwitchID) {
            settleMessageListAfterSwitch()
        }
    }

    private var activeEditSession: AIChatState.EditSession? {
        guard let editSession = aiChatState.editSession,
              editSession.conversationID == fileState.aiChatConversationID
        else {
            return nil
        }
        return editSession
    }

    private var currentTransientError: AIChatState.TransientError? {
        guard let error = aiChatState.transientError,
              error.conversationID == fileState.aiChatConversationID
        else {
            return nil
        }
        return error
    }

    /// Wipes the current conversation's message history via LLMKit's
    /// `clearConversation` API. The drawing file and its file-history
    /// (including AI-tagged checkpoints) stay intact — this only clears
    /// the chat, not the canvas state.
    private func clearCurrentConversation() {
        guard let id = fileState.aiChatConversationID else { return }
        // Cancel any in-flight stream so its trailing message commit
        // doesn't land in a just-cleared conversation.
        llmState.cancelGeneration(conversationID: id)
        Task {
            do {
                 try await llmState.clearConversation(id)
            } catch {
                await MainActor.run {
                    alertToast.presentAIChatError(error)
                }
            }
        }
    }
    
    @ViewBuilder
    private func emptyPlaceholder() -> some View {
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
    private func messageList(messages: [ChatMessage]) -> some View {
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
        let streamingID: String? = streamingState?.id
        let streamFinished: Bool = streamingState?.isFinished ?? true
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
        let loadingDiagnosticSignature = loadingDiagnosticsSignature(
            conversationID: fileState.aiChatConversationID,
            isStreamingActive: isStreamingActive,
            streamingID: streamingID,
            streamFinished: streamFinished,
            streamingMessageIDs: streamingMessageIDs,
            groups: allGroups
        )
        NativeChatScrollView(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreamingActive || streamScrollFollowTail,
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
                showsUserMessageActions: !isRoundLifecycleActive,
                disablesUserMessageActions: isStreamingActive || streamScrollFollowTail
            )
        }
        .environment(\.chatScrollToBottom) { animated in
            await scrollToBottomAsync(animated: animated)
        }
        .task(id: loadingDiagnosticSignature) {
            logLoadingDiagnostics(
                conversationID: fileState.aiChatConversationID,
                isStreamingActive: isStreamingActive,
                streamingID: streamingID,
                streamFinished: streamFinished,
                streamingMessageIDs: streamingMessageIDs,
                groups: allGroups
            )
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

    private func containsErrorMessage(
        in groups: [MessageGroup],
        matching message: String
    ) -> Bool {
        groups.contains { group in
            guard case .error(_, let existingMessage) = group else { return false }
            return existingMessage == message
        }
    }

    private func streamingAssistantMessageIDs(
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

    private func loadingDiagnosticsSignature(
        conversationID: String?,
        isStreamingActive: Bool,
        streamingID: String?,
        streamFinished: Bool,
        streamingMessageIDs: Set<String>,
        groups: [MessageGroup]
    ) -> String {
        [
            conversationID ?? "nil",
            "active=\(isStreamingActive)",
            "stream=\(streamingID ?? "nil")",
            "finished=\(streamFinished)",
            "ids=\(streamingMessageIDs.sorted().joined(separator: ","))",
            "groups=\(loadingGroupSummary(groups))"
        ].joined(separator: " ")
    }

    private func loadingGroupSummary(_ groups: [MessageGroup]) -> String {
        groups.map { group in
            switch group {
                case .user(let content):
                    return "user(\(content.id))"
                case .assistantRound(let id, let messages):
                    let ids = messages.compactMap { message -> String? in
                        guard case .content(let content) = message else { return nil }
                        return "\(content.role):\(content.id):c\(content.content?.count ?? 0):tc\(content.toolCalls?.count ?? 0)"
                    }.joined(separator: ",")
                    return "round(\(id))[\(ids)]"
                case .loading(let id):
                    return "loading(\(id.uuidString))"
                case .error(let id, let message):
                    return "error(\(id.uuidString):\(message))"
                case .compactSummary(let content):
                    return "compact(\(content.id))"
            }
        }.joined(separator: "|")
    }

    private func logLoadingDiagnostics(
        conversationID: String?,
        isStreamingActive: Bool,
        streamingID: String?,
        streamFinished: Bool,
        streamingMessageIDs: Set<String>,
        groups: [MessageGroup]
    ) {
        #if DEBUG
        print(
            "[aiChatLoadingDiag] list",
            "conversation=\(conversationID ?? "nil")",
            "isStreamingActive=\(isStreamingActive)",
            "streamingID=\(streamingID ?? "nil")",
            "streamFinished=\(streamFinished)",
            "streamingMessageIDs=\(streamingMessageIDs.sorted())",
            "groups=\(loadingGroupSummary(groups))"
        )
        #endif
    }

    @ViewBuilder
    private func messageListRows(
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
    private func handleScrollAnimationComplete(token: Int) {
        guard !scrollCompletionContinuations.isEmpty else { return }
        let pending = scrollCompletionContinuations
        scrollCompletionContinuations.removeAll()
        isAutoScrollingToBottom = false
        for (_, cont) in pending {
            cont.resume()
        }
    }

    private func visibleMessageGroups(from groups: [MessageGroup]) -> [MessageGroup] {
        guard groups.count > visibleMessageGroupLimit else { return groups }
        return Array(groups.suffix(visibleMessageGroupLimit))
    }

    private func loadMoreMessageGroupsIfNeeded(totalGroupCount: Int) {
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

    private func loadOlderMessageGroupsNow(totalGroupCount: Int) {
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

    private func resetVisibleMessageWindowIfNeeded() {
        guard visibleMessageGroupLimit != initialVisibleMessageGroupLimit else { return }
        resetVisibleMessageWindow()
    }

    private func resetVisibleMessageWindow() {
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

    private func settleMessageListAfterSwitch() {
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

    private func suppressOlderMessageLoadingTemporarily() {
        suppressOlderMessageLoadingTask?.cancel()
        suppressOlderMessageLoading = true
        suppressOlderMessageLoadingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(ChatScrollAnimation.scrollDuration + 0.4))
            suppressOlderMessageLoading = false
            suppressOlderMessageLoadingTask = nil
        }
    }

    private func messagesForCurrentEditSession(_ messages: [ChatMessage]) -> [ChatMessage] {
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
    private func scrollToBottomAsync(animated: Bool) async {
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
    
    @MainActor @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        if layoutState.isInspectorPresented {
            if #available(macOS 26.0, *) {
                ToolbarItemGroup(placement: .destructiveAction) {
                    Button {
                        layoutState.enterAIChatIsland()
                    } label: {
                        Label("Float as island", systemSymbol: .menubarDockRectangle)
                    }
                    .help("Float chat as a draggable island over the editor")
                }
                
                // This work...
                ToolbarItemGroup(placement: .principal) {
                    Spacer()
                }
                
                // Not working...
                ToolbarSpacer(.fixed)
            }
            
            InspectorHeaderToolbar(
                title: "AI Chat",
                isInspectorPresented: layoutState.isInspectorPresented
            )
            
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button {} label: {
                        Label("\(creditsDisplayText) credits", systemSymbol: .sparkles)
                    }
                    .disabled(true)

                    Divider()

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isShowingWelcomeManually = true
                        }
                    } label: {
                        Label("Show welcome", systemSymbol: .sparkles)
                    }

                    if #available(macOS 14.0, iOS 17.0, *) {
                        OpenSettingsMenuItem(deepLinkTo: .ai)
                    } else {
                        // Pre-`openSettings` env fallback — NSApp.sendAction
                        // path. Older macOS doesn't carry the macOS 26+ runtime
                        // "Please use SettingsLink" warning.
                        Button {
                            SettingsRouter.shared.requestOpen(.ai)
                        } label: {
                            Label("Settings…", systemSymbol: .gearshape)
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear chat", systemSymbol: .trash)
                    }
                    // Disable when there's no conversation to clear, so the
                    // user doesn't get a confirmationDialog for a no-op.
                    .disabled(fileState.aiChatConversationID == nil)
                } label: {
                    Label("More", systemSymbol: .ellipsis)
                }
                .menuIndicator(.hidden)
            }
        }
    }
    
    /// Start editing a historical user message. Plain edit is reversible
    /// until Send because truncation is delayed. Revert is destructive by
    /// design: after confirmation it immediately restores the canvas,
    /// truncates the timeline, and only then refills the input box.
    private func beginEditingUserMessage(_ userMessageID: String) {
        guard let convo = conversation else { return }
        if let streamingState,
           shouldShowStreamingMessage(streamingState) {
            return
        }
        let conversationID = convo.id

        let content: ChatMessageContent? = convo.messages.first {
            if case .content(let c) = $0,
               c.id == userMessageID,
               c.role == .user { return true }
            return false
        }.flatMap { msg -> ChatMessageContent? in
            if case .content(let c) = msg { return c }
            return nil
        }
        guard let content else { return }

        if revertRequiredUserMessageIDs.contains(userMessageID) {
            beginRevertingUserMessage(
                conversationID: conversationID,
                content: content
            )
            return
        }

        llmState.cancelGeneration(conversationID: conversationID)
        aiChatState.beginEditing(
            conversationID: conversationID,
            userMessageID: userMessageID,
            text: content.content ?? "",
            files: content.files ?? [],
            mode: .edit
        )
        isPinnedToBottom = true
        requestScrollToBottom(animated: true)
    }

    private func beginRevertingUserMessage(
        conversationID: String,
        content: ChatMessageContent
    ) {
        Task {
            do {
                llmState.cancelGeneration(conversationID: conversationID)
                try await restoreFileForRevert(userMessageID: content.id)
                try await llmState.truncateConversation(
                    in: conversationID,
                    fromMessageID: content.id,
                    inclusive: true
                )
                await MainActor.run {
                    aiChatState.finishEditing()
                    aiChatState.requestDraft(content.content ?? "", files: content.files ?? [])
                    isPinnedToBottom = true
                    requestScrollToBottom(animated: true)
                }
            } catch {
                await MainActor.run {
                    alertToast.presentAIChatError(error)
                }
            }
        }
    }

    @MainActor
    private func restoreFileForRevert(userMessageID: String) async throws {
        guard case .file(let file) = fileState.currentActiveFile else {
            throw AIChatEditError.unsupportedFile
        }

        let fileObjectID = file.objectID
        let context = PersistenceController.shared.newTaskContext()

        let checkpointObjectID: NSManagedObjectID? = try await context.perform {
            guard let file = try context.existingObject(with: fileObjectID) as? File else { return nil }
            let fetch = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetch.predicate = NSPredicate(
                format: "file == %@ AND messageID == %@ AND source == %@",
                file,
                userMessageID,
                FileCheckpointSource.aiPre.rawValue
            )
            fetch.fetchLimit = 1
            return try context.fetch(fetch).first?.objectID
        }

        guard let checkpointObjectID else {
            throw AIChatEditError.missingRevertPoint
        }

        let checkpointRepository = PersistenceController.shared.checkpointRepository
        let fileRepository = PersistenceController.shared.fileRepository
        try await checkpointRepository.restoreCheckpoint(
            checkpointObjectID: checkpointObjectID,
            to: fileObjectID
        )
        let content = try await checkpointRepository.loadCheckpointContent(
            checkpointObjectID: checkpointObjectID
        )
        try await fileRepository.saveFileContentToStorage(
            fileObjectID: fileObjectID,
            content: content
        )

        try await fileState.restoreActiveCanvas(
            fromCheckpointContent: content,
            filename: nil
        )
    }

    private func revertRequirementRefreshKey(groups: [MessageGroup]) -> String {
        let fileID: String = {
            guard case .file(let file) = fileState.currentActiveFile else { return "no-file" }
            return file.objectID.uriRepresentation().absoluteString
        }()
        let sessionID = fileState.aiChatSession.map {
            "\($0.conversationID):\($0.userMessageID)"
        } ?? "no-session"
        let groupIDs = groups.map(\.id).joined(separator: "|")
        return "\(fileID)::\(sessionID)::\(groups.count)::\(groupIDs)"
    }

    private func refreshRevertRequiredUserMessageIDs(groups: [MessageGroup]) async {
        let assistantMessageIDs = Array(Set(assistantMessageIDs(in: groups)))
        guard !assistantMessageIDs.isEmpty,
              case .file(let file) = fileState.currentActiveFile
        else {
            revertRequiredUserMessageIDs = []
            return
        }
        let fileObjectID = file.objectID
        let context = PersistenceController.shared.newTaskContext()
        let aiPostMessageIDs: Set<String> = await context.perform {
            guard let file = try? context.existingObject(with: fileObjectID) as? File else { return [] }
            let fetch = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetch.predicate = NSPredicate(
                format: "file == %@ AND source == %@ AND messageID IN %@",
                file,
                FileCheckpointSource.aiPost.rawValue,
                assistantMessageIDs
            )
            guard let checkpoints = try? context.fetch(fetch) else { return [] }
            return Set(checkpoints.compactMap(\.messageID))
        }
        revertRequiredUserMessageIDs = userMessageIDsBeforeAnyAIPost(
            groups: groups,
            aiPostMessageIDs: aiPostMessageIDs
        )
    }

    private func assistantMessageIDs(in groups: [MessageGroup]) -> [String] {
        groups.flatMap { group -> [String] in
            guard case .assistantRound(_, let messages) = group else { return [] }
            return messages.compactMap { message -> String? in
                guard case .content(let content) = message,
                      content.role == .assistant
                else {
                    return nil
                }
                return content.id
            }
        }
    }

    private func userMessageIDsBeforeAnyAIPost(
        groups: [MessageGroup],
        aiPostMessageIDs: Set<String>
    ) -> Set<String> {
        var result: Set<String> = []
        var hasAIPostAfterCurrentPosition = false

        for group in groups.reversed() {
            switch group {
                case .assistantRound(_, let messages):
                    if messages.contains(where: { message in
                        guard case .content(let content) = message,
                              content.role == .assistant
                        else {
                            return false
                        }
                        return aiPostMessageIDs.contains(content.id)
                    }) {
                        hasAIPostAfterCurrentPosition = true
                    }
                case .user(let content):
                    if hasAIPostAfterCurrentPosition {
                        result.insert(content.id)
                    }
                case .loading, .error, .compactSummary:
                    continue
            }
        }

        return result
    }

    private func regenerateMessage(messageID: String) {
        guard let id = fileState.aiChatConversationID else { return }
        let retryContent: ChatMessageContent? = conversation?.messages.first {
            guard case .content(let content) = $0 else { return false }
            return content.id == messageID && content.role == .user
        }.flatMap { message in
            guard case .content(let content) = message else { return nil }
            return content
        }

        aiChatState.clearTransientError(for: id)
        Task {
            do {
                let agentConfig = try await LLMClient.shared.getDomainAgentConfig(agentID: "excalidraw-canvas")
                try await llmState.regenerateMessage(
                    in: id,
                    fromMessageID: messageID,
                    model: agentConfig.defaultModel,
                    stream: true
                )
            } catch {
                await MainActor.run {
                    aiChatState.presentTransientError(
                        error,
                        conversationID: id,
                        userMessageID: messageID,
                        retryPrompt: retryContent?.content ?? "",
                        retryFiles: retryContent?.files ?? []
                    )
                }
            }
        }
    }

    private func retryTransientError(_ error: AIChatState.TransientError) {
        guard let id = fileState.aiChatConversationID,
              id == error.conversationID
        else {
            return
        }

        let hasUserMessage = conversation?.messages.contains { message in
            guard case .content(let content) = message else { return false }
            return content.id == error.userMessageID && content.role == .user
        } == true

        aiChatState.clearTransientError(for: id)

        if hasUserMessage {
            regenerateMessage(messageID: error.userMessageID)
        } else {
            aiChatState.requestDraft(error.retryPrompt, files: error.retryFiles)
        }
    }
    
    private func shouldShowStreamingMessage(_ stream: LLMStreamingStateObject) -> Bool {
        !stream.isFinished
    }
    
    private func requestScrollToBottomIfNeeded(_ newBottomID: String?) {
        guard let newBottomID else { return }
        guard newBottomID != lastBottomID else { return }
        let wasFirstObservation = (lastBottomID == nil)
        lastBottomID = newBottomID
        guard isPinnedToBottom else { return }
        // First observation (`.onAppear` with existing history) is initial
        // positioning, not a "scroll" — the scroll host's first-measurement
        // path snaps without visible animation. Subsequent changes (new
        // round, newly committed message) are real content events; animate.
        guard !wasFirstObservation else { return }
        requestScrollToBottom(animated: true)
    }

    private func requestScrollToBottom(animated: Bool) {
        suppressOlderMessageLoadingTemporarily()
        if animated {
            isAutoScrollingToBottom = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(ChatScrollAnimation.scrollDuration + 0.12))
                isAutoScrollingToBottom = false
            }
        }
        scrollToBottomRequest = ScrollToBottomRequest(
            token: scrollToBottomRequest.token + 1,
            animated: animated
        )
    }
}

/// Menu item that opens Settings via `@Environment(\.openSettings)` (macOS 14+
/// / iOS 17+) and writes the deep-link target into `SettingsRouter` first.
/// Lives in its own struct because the `openSettings` env value is gated to
/// macOS 14 — declaring it as a property on `AIChatView` (deployment target
/// is older) would compile-error.
@available(macOS 14.0, iOS 17.0, *)
private struct OpenSettingsMenuItem: View {
    let deepLinkTo: SettingsView.Route
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        Button {
            // Write the route *before* `openSettings()` so that whichever
            // arrives first at `SettingsView`, the value is in place — `.task`
            // (first mount) or `.onChange` (window reused) consumes it.
            SettingsRouter.shared.pendingRoute = deepLinkTo
            openSettings()
        } label: {
            Label("Settings…", systemSymbol: .gearshape)
        }
    }
}

private struct HiddenHistoryIndicator: View {
    let hiddenGroupCount: Int
    let isLoading: Bool

    var body: some View {
        ChatScrollRow {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemSymbol: .arrowUp)
                        .font(.caption2.weight(.semibold))
                }
                Text(isLoading ? "Loading earlier items..." : "Scroll up to load \(hiddenGroupCount) earlier items")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

private struct EditSessionBanner: View {
    let mode: AIChatState.EditSession.Mode
    let onCancel: () -> Void

    private var title: String {
        switch mode {
            case .edit: "Editing message"
        }
    }

    private var symbol: SFSymbol {
        switch mode {
            case .edit: .pencil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemSymbol: symbol)
                .foregroundStyle(AIAppearancePalette.foregroundGradient)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button(action: onCancel) {
                Image(systemSymbol: .xmark)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Cancel editing")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
//        .background {
//            if #available(macOS 26.0, *) {
//                RoundedRectangle(cornerRadius: 14)
//                    .fill(.clear)
//                    .glassEffect(
//                        .regular.interactive(),
//                        in: RoundedRectangle(cornerRadius: 14)
//                    )
//            } else {
//                RoundedRectangle(cornerRadius: 14)
//                    .fill(.ultraThinMaterial)
//            }
//        }
//        .padding(1)
    }
}

#if DEBUG
#Preview {
    AIChatView()
        .frame(width: 250, height: 600)
        .llmProvider(
            client: .shared,
            persistenceProvider: nil,
            lagacy: true
        )
}
#endif
