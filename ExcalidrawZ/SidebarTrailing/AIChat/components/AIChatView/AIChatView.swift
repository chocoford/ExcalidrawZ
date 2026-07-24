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
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var llmState: LLMStateObject
    @EnvironmentObject var aiChatState: AIChatState
    @Environment(\.alertToast) var alertToast
    @Environment(\.containerHorizontalSizeClass) var containerHorizontalSizeClass
    @ObservedObject var prefs = AIChatPreferences.shared

    /// Conversation id lives on `FileState` (chats are scoped to the current
    /// file). We bridge it to a `Binding` for `PromptInputView`'s API and so
    /// the inspector and the island both write back to the same place.
    var conversationID: Binding<String?> {
        Binding(
            get: { fileState.aiChatConversationID },
            set: { fileState.aiChatConversationID = $0 }
        )
    }

    @FocusState var isInputFocused: Bool

    @State var lastBottomID: String?
    @State var isPinnedToBottom: Bool = true
    @State var scrollToBottomRequest = ScrollToBottomRequest()
    @State var isAutoScrollingToBottom: Bool = false
    @State var streamScrollFollowTail: Bool = false
    @State var isMessageListInitiallySettled: Bool = false
    @State var isHoldingConversationLoadingPlaceholder: Bool = false
    @State var messageListSettleTask: Task<Void, Never>?
    /// Resumed by `onScrollAnimationComplete` from `NativeChatScrollView`,
    /// keyed by the scroll-request token. Lets `AssistantRoundView`'s
    /// reveal pipeline `await scrollToBottom` and only run the wipe
    /// after the smooth scroll has actually reached the new bottom.
    @State var scrollCompletionContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    @State var revertRequiredUserMessageIDs: Set<String> = []
    @State var messageWindow = ChatMessageWindowState(pageSize: 20)
    @State var aiActionTask: Task<Void, Never>?
    @State var chatInputControlsHeight: CGFloat = 0
    @StateObject var promptTextAreaProxy = TextAreaProxy()
    /// Confirmation dialog for the "Clear chat" toolbar action — destructive,
    /// so we route through a confirmationDialog rather than firing on tap.
    @State var isConfirmingClear: Bool = false
    @State var isAISettingsSheetPresented: Bool = false

    /// Tapped Get Started on the first-run welcome cover. We only fall back
    /// on the `conversations` count for "first-time visitor" detection;
    /// once dismissed in this view we never want to flash the cover again
    /// even if the user clears all chats from the More menu.
    @State var hasDismissedWelcome: Bool = false
    @State var isShowingWelcomeManually: Bool = false
    /// Show the welcome cover when no conversations exist anywhere yet AND
    /// the user hasn't already dismissed it. We treat `nil` (cache not
    /// loaded) as "don't show yet" — flashing the welcome before LLMKit
    /// finishes its first refresh would feel jumpy.
    var shouldShowWelcome: Bool {
        guard !fileState.isAIChatConversationLoading else { return false }
        if isShowingWelcomeManually { return true }
        guard !hasDismissedWelcome else { return false }
        guard let convos = llmState.conversations.value else { return false }
        return convos.isEmpty
    }

    var messageListSwitchID: String {
        [
            fileState.currentActiveFile?.id ?? "nil",
            fileState.aiChatConversationID ?? "nil"
        ].joined(separator: "|")
    }

    var conversation: Conversation? {
        llmState.conversations.value?.first { $0.id == fileState.aiChatConversationID }
    }

    var streamingState: LLMStreamingStateObject? {
        guard let id = fileState.aiChatConversationID else { return nil }
        return llmState.streamingStore.streamIfExists(for: id)
        as? LLMStreamingStateObject
    }

    /// Mirrors `ApprovalPromptView`'s internal gate. Used as the
    /// `.animation(value:)` driver on the bottom VStack so the card's
    /// appearance/disappearance smoothly slides the input box without
    /// SwiftUI seeing an "unmotivated" layout change.
    var shouldShowApprovalCard: Bool {
        llmState.pendingApprovalRequest != nil
    }

    /// True while LLMKit's `compactConversation` is running on the
    /// conversation we're rendering. Drives the transient "compacting…"
    /// banner in the bottom stack so the user knows the next send is
    /// being held until the summary lands.
    var isCompactingThisConversation: Bool {
        aiChatState.isCompacting(conversationID: fileState.aiChatConversationID)
    }

    var shouldShowConversationLoadingPlaceholder: Bool {
        fileState.isAIChatConversationLoading || isHoldingConversationLoadingPlaceholder
    }

    var creditsDisplayText: String {
        let balance = llmState.creditsInfo?.balance ?? 0
        return balance.formatted(.number.precision(.fractionLength(2)))
    }

    var isAIAvailable: Bool {
        AIChatAvailability.isAvailable
    }

    var isCompactIOS: Bool {
#if os(iOS)
        containerHorizontalSizeClass == .compact
#else
        false
#endif
    }

    var promptInputStyle: PromptInputStyle<PlatformDefaultPromptBackground> {
#if os(iOS)
        if isCompactIOS {
            return .compactIOS
        }
#endif
        return .regular
    }

    @MainActor
    func activeFileAllowsAIContext() async -> Bool {
        guard let activeFile = fileState.currentActiveFile else { return false }
        guard prefs.allowsFileAccess(for: activeFile) else { return false }
        return await LockedContentAIGuard.canAIRead(activeFile: activeFile)
    }

    var shouldBlockAIForPreference: Bool {
        !prefs.isAIEnabled
    }

    var shouldShowWelcomeContent: Bool {
        !isAIAvailable || shouldBlockAIForPreference || shouldShowWelcome
    }

    var body: some View {
        let _ = AIChatRenderDebug.hit("AIChatView.body")

        ZStack {
            if shouldShowWelcomeContent {
                welcomeContent
                    .transition(.opacity)
            } else {
                chatBody
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(content: toolbar)
        .confirmationDialog(
            String(localizable: .aiChatClearChatConfimationDialogTitle),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(.localizable(.generalButtonConfirm), role: .destructive) {
                clearCurrentConversation()
            }
            Button(.localizable(.generalButtonCancel), role: .cancel) {}
        } message: {
            Text(localizable: .aiChatClearChatConfimationDialogMessage)
        }
#if os(iOS)
        .sheet(isPresented: $isAISettingsSheetPresented) {
            aiSettingsSheet
        }
#endif
        .background {
            debugPublishProbe
        }
        .watch(value: prefs.isAIEnabled) { isEnabled in
            guard !isEnabled else { return }
            cancelAIWorkForDisabledAI()
        }
        .task {
            guard isAIAvailable, prefs.isAIEnabled else { return }
            await LLMCreditsRefreshCoordinator.shared.refreshCredits(reason: .aiChatAppear)
        }
        .task(id: fileState.aiChatConversationID) {
            guard isAIAvailable, prefs.isAIEnabled else { return }
            try? await Task.sleep(nanoseconds: AIChatState.selectedConversationRefreshDelay)
            guard !Task.isCancelled else { return }
            await aiChatState.refreshSelectedConversationCacheIfNeeded(
                in: llmState,
                fileState: fileState
            )
        }
    }

    @ViewBuilder
    private var welcomeContent: some View {
        if !isAIAvailable {
            AIChatWelcomeView(
                buttonTitle: String(localizable: .aiChatUnavailableNonAppStoreButtonTitle),
                buttonCaption: String(localizable: .aiChatUnavailableNonAppStoreMessage),
                buttonURL: AppStoreVersion.appURL
            ) {}
        } else if shouldBlockAIForPreference {
            AIChatWelcomeView(
                buttonTitle: String(localizable: .aiChatDisabledButtonEnable),
                buttonCaption: String(localizable: .aiChatDisabledMessage),
                requiresEnableConfirmation: true
            ) {
                enableAIFromWelcome()
            }
        } else if shouldShowWelcome {
            AIChatWelcomeView {
                dismissWelcome()
            }
        }
    }

    private func dismissWelcome() {
        withAnimation(.easeInOut(duration: 0.25)) {
            hasDismissedWelcome = true
            isShowingWelcomeManually = false
        }
    }

    private func enableAIFromWelcome() {
        prefs.isAIEnabled = true
        Task {
            await LLMServiceActivationCoordinator.shared.restoreIfAIEnabled(reason: .aiChatEnable)
            await LLMCreditsRefreshCoordinator.shared.refreshCredits(reason: .aiChatAppear, force: true)
        }
        dismissWelcome()

        if isCompactIOS,
           fileState.currentActiveFile != nil,
           !fileState.currentActiveFileIsInTrash {
            layoutState.isInspectorPresented = false
            layoutState.enterCompactAIChatInputEditing()
        }
    }

#if os(iOS)
    @ViewBuilder
    private var aiSettingsSheet: some View {
        if #available(iOS 16.4, *) {
            SettingsView()
                .presentationContentInteraction(.scrolls)
                .swiftyAlert()
        } else {
            SettingsView()
                .swiftyAlert()
        }
    }
#endif

    @ViewBuilder
    private var debugPublishProbe: some View {
#if DEBUG
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(llmState.objectWillChange) { _ in
                AIChatRenderDebug.hit("publish.llmState")
            }

        if let streamingState {
            Color.clear
                .frame(width: 0, height: 0)
                .onReceive(streamingState.objectWillChange) { _ in
                    AIChatRenderDebug.hit("publish.streamingState")
                }
        }
#else
        EmptyView()
#endif
    }

    @ViewBuilder
    var chatBody: some View {
        let _ = AIChatRenderDebug.hit("AIChatView.chatBody")

        ZStack {
            regularChatBody
        }
        // The approval card eats vertical space from the chat scroll
        // view. Without an explicit nudge the messages slide up but the
        // viewport's last-row anchor stays where it was — the user ends
        // up looking at the middle of the conversation while the prompt
        // they need to answer is offscreen. Re-pin to bottom whenever
        // the card appears so the trailing message + the approval card
        // are both in view together.
        .watch(value: shouldShowApprovalCard) { _, showing in
            guard showing else { return }
            isPinnedToBottom = true
            requestScrollToBottom(animated: true)
        }
        .task(id: messageListSwitchID) {
            settleMessageListAfterSwitch()
        }
    }

    @ViewBuilder
    var regularChatBody: some View {
        VStack(spacing: 0) {
            chatMessageStage(bottomContentPadding: 0)

            chatInputControls
                .padding(.bottom, 10)
                .readHeight($chatInputControlsHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .watch(value: chatInputControlsHeight) { oldHeight, newHeight in
            guard oldHeight != newHeight,
                  newHeight > 0,
                  isPinnedToBottom else {
                return
            }
            requestScrollToBottom(animated: false)
        }
    }

    @ViewBuilder
    func chatMessageStage(bottomContentPadding: CGFloat) -> some View {
        ZStack {
            if AIChatRenderDebug.hideMessageList {
                Color.clear
            } else if shouldShowConversationLoadingPlaceholder {
                conversationLoadingPlaceholder()
            } else if let conversation, !conversation.messages.isEmpty {
                messageList(
                    messages: conversation.messages,
                    bottomContentPadding: bottomContentPadding
                )
            } else if currentTransientError != nil {
                messageList(
                    messages: conversation?.messages ?? [],
                    bottomContentPadding: bottomContentPadding
                )
            } else {
                emptyPlaceholder()
            }
        }
        .opacity(isMessageListInitiallySettled || shouldShowConversationLoadingPlaceholder ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isMessageListInitiallySettled)
        .watch(value: fileState.isAIChatConversationLoading) { _, isLoading in
            if isLoading {
                isHoldingConversationLoadingPlaceholder = true
            } else if isMessageListInitiallySettled {
                isHoldingConversationLoadingPlaceholder = false
            } else {
                isHoldingConversationLoadingPlaceholder = fileState.currentActiveFile != nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    var chatInputControls: some View {
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

            VStack(spacing: 0) {
                if !isCompactIOS {
                    LowCreditsBannerView(peekBottom: 18)
                        .padding(.horizontal, 10)
                        .font(.caption)
                        .offset(y: 18)
                }

                ZStack(alignment: .top) {
                    PromptInputView(
                        conversationID: conversationID,
                        pendingQueue: $aiChatState.pendingQueue,
                        style: promptInputStyle,
                        showsCompactIOSFullChatButton: false
                    ) {
                        if let editSession = activeEditSession {
                            EditSessionBanner(
                                mode: editSession.mode,
                                onCancel: {
                                    aiChatState.cancelEditing(
                                        conversationID: editSession.conversationID
                                    )
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .disabled(
                        llmState.pendingApprovalRequest != nil ||
                        fileState.isAIChatConversationLoading ||
                        fileState.currentActiveFileIsInTrash
                    )
                    .textAreaProxy(promptTextAreaProxy)

                    ApprovalPromptView()
                }
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

    var activeEditSession: AIChatState.EditSession? {
        guard let editSession = aiChatState.editSession,
              editSession.conversationID == fileState.aiChatConversationID
        else {
            return nil
        }
        return editSession
    }

    var currentTransientError: AIChatState.TransientError? {
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
    func clearCurrentConversation() {
        guard let id = fileState.aiChatConversationID else { return }
        // Cancel any in-flight stream so its trailing message commit
        // doesn't land in a just-cleared conversation.
        llmState.cancelGeneration(conversationID: id)
        aiChatState.clearTransientError(for: id)
        aiChatState.clearGenerationCancellation(for: id)
        aiChatState.unmarkCompacting(conversationID: id)
        aiChatState.cancelEditing(conversationID: id)
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
