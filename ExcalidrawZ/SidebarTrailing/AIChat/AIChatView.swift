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
    @State private var streamScrollFollowTail: Bool = false
    @State private var isMessageListInitiallySettled: Bool = false
    @State private var lastActiveStreamID: String?
    @State private var revealingAssistantRoundID: String?
    @State private var pendingLoadingRowID: String?
    @State private var revertableUserMessageIDs: Set<String> = []
    /// Confirmation dialog for the "Clear chat" toolbar action — destructive,
    /// so we route through a confirmationDialog rather than firing on tap.
    @State private var isConfirmingClear: Bool = false

    /// Tapped Get Started on the first-run welcome cover. We only fall back
    /// on the `conversations` count for "first-time visitor" detection;
    /// once dismissed in this view we never want to flash the cover again
    /// even if the user clears all chats from the More menu.
    @State private var hasDismissedWelcome: Bool = false
    @State private var isShowingWelcomeManually: Bool = false

    /// Show the welcome cover when no conversations exist anywhere yet AND
    /// the user hasn't already dismissed it. We treat `nil` (cache not
    /// loaded) as "don't show yet" — flashing the welcome before LLMKit
    /// finishes its first refresh would feel jumpy.
    private var shouldShowWelcome: Bool {
        if isShowingWelcomeManually { return true }
        guard !hasDismissedWelcome else { return false }
#if DEBUG
        return true
#else
        guard let convos = llmState.conversations.value else { return false }
        return convos.isEmpty
#endif
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
            if let conversation, !conversation.messages.isEmpty {
                messageList(messages: conversation.messages)
            } else {
                emptyPlaceholder()
            }
            
            VStack(spacing: 6) {
                if let editSession = activeEditSession {
                    EditSessionBanner(
                        mode: editSession.mode,
                        onCancel: { aiChatState.cancelEditing() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

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
                    )
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
    }

    private var activeEditSession: AIChatState.EditSession? {
        guard let editSession = aiChatState.editSession,
              editSession.conversationID == fileState.aiChatConversationID
        else {
            return nil
        }
        return editSession
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
        let bottomID = streamingState?.id ?? messages.last?.id
        let isStreamingActive: Bool = {
            guard let stream = streamingState else { return false }
            return shouldShowStreamingMessage(stream, messages: messages)
        }()
        // Pass `isStreamingActive || streamScrollFollowTail` so the scroll
        // host's growth-driven auto-follow stays armed for a short tail
        // after the stream ends — that window covers the loading→message
        // swap's height grow and the trailing reveal mask animation.
        NativeChatScrollView(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreamingActive || streamScrollFollowTail
        ) {
            messageListRows(messages: messages)
        }
        .opacity(isMessageListInitiallySettled ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isMessageListInitiallySettled)
        .overlay(alignment: .bottom) {
            if !isPinnedToBottom {
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
            guard !isMessageListInitiallySettled else { return }
            requestScrollToBottom(animated: false)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                requestScrollToBottom(animated: false)
                isMessageListInitiallySettled = true
            }
        }
        .onChange(of: bottomID) { _ in
            guard !isStreamingActive else { return }
            requestScrollToBottomIfNeeded(bottomID)
        }
        .onChange(of: isStreamingActive) { nowStreaming in
            if nowStreaming {
                lastActiveStreamID = streamingState?.id
                pendingLoadingRowID = messages.last(where: {
                    if case .loading = $0 { return true }
                    return false
                })?.id
                // Just kicked off a new round (user sent / regenerate).
                // Force-pin and request an explicit scroll-to-bottom: the
                // host's growth-driven follow can race against
                // `isStreaming` reaching the Coordinator (the user-message
                // frame may land before SwiftUI has propagated the new
                // streaming state through `updateNSView`), so without this
                // nudge the user's message + the LoadingMessageRow can
                // appear without the viewport tracking them.
                isPinnedToBottom = true
                requestScrollToBottom(animated: true)
                return
            }
            revealingAssistantRoundID = lastActiveStreamID ?? streamingState?.id
            // Tail window: the round-level loading→message swap and the
            // trailing reveal mask animation both happen *after* the
            // stream finishes. Keep the host's growth-driven follow
            // armed for ~600 ms so the round can smoothly slide up to
            // accommodate the committed message instead of overflowing
            // below the viewport.
            streamScrollFollowTail = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                streamScrollFollowTail = false
                pendingLoadingRowID = nil
            }
        }
        .task(id: revertableRefreshKey(messages: messages)) {
            await refreshRevertableUserMessageIDs(messages: messages)
        }
    }
    
    @ViewBuilder
    private func messageListRows(messages: [ChatMessage]) -> some View {
        let layout = makeRowLayout(messages: messages)
        
        StaticGroupsView(
            groups: layout.staticGroups,
            revealingAssistantRoundID: revealingAssistantRoundID,
            pendingLoadingRowID: pendingLoadingRowID,
            onRegenerate: regenerateMessage,
            revertableUserMessageIDs: revertableUserMessageIDs,
            onUserMessageAction: beginEditingUserMessage
        )
    }

    /// Timeline rows are rendered directly from committed / placeholder
    /// messages. Active loading is represented by LLMKit's `.loading` message,
    /// so no separate live slot is needed here.
    private func makeRowLayout(messages: [ChatMessage]) -> RowLayout {
        return RowLayout(
            staticGroups: groupMessages(messages)
        )
    }

    private func shouldShowPendingLoadingFallback(in groups: [MessageGroup]) -> Bool {
        guard streamScrollFollowTail,
              let revealingAssistantRoundID
        else {
            return false
        }
        let hasLoading = groups.contains { group in
            if case .loading = group { return true }
            return false
        }
        let hasRevealingAssistant = groups.contains { group in
            guard case .assistantRound(let id, let messages) = group else {
                return false
            }
            return id == revealingAssistantRoundID
                || messages.contains { $0.id == revealingAssistantRoundID }
        }
        return !hasLoading && !hasRevealingAssistant
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
    
    /// Start editing a historical user message. We intentionally delay
    /// truncation / file-restore until the user presses Send, so Cancel
    /// can restore the original chat by simply clearing edit state.
    private func beginEditingUserMessage(_ userMessageID: String) {
        guard let convo = conversation else { return }
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

        llmState.cancelGeneration(conversationID: conversationID)
        aiChatState.beginEditing(
            conversationID: conversationID,
            userMessageID: userMessageID,
            text: content.content ?? "",
            files: content.files ?? [],
            mode: revertableUserMessageIDs.contains(userMessageID) ? .revert : .edit
        )
        isPinnedToBottom = true
        requestScrollToBottom(animated: true)
    }

    private func revertableRefreshKey(messages: [ChatMessage]) -> String {
        let fileID: String = {
            guard case .file(let file) = fileState.currentActiveFile else { return "no-file" }
            return file.objectID.uriRepresentation().absoluteString
        }()
        let messageIDs = messages.map(\.id).joined(separator: "|")
        return "\(fileID)::\(messageIDs)"
    }

    private func refreshRevertableUserMessageIDs(messages: [ChatMessage]) async {
        let userMessageIDs = messages.compactMap { message -> String? in
            guard case .content(let content) = message, content.role == .user else { return nil }
            return content.id
        }
        guard !userMessageIDs.isEmpty,
              case .file(let file) = fileState.currentActiveFile
        else {
            revertableUserMessageIDs = []
            return
        }
        let fileObjectID = file.objectID
        let context = PersistenceController.shared.newTaskContext()
        let ids: Set<String> = await context.perform {
            guard let file = try? context.existingObject(with: fileObjectID) as? File else { return [] }
            let fetch = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetch.predicate = NSPredicate(
                format: "file == %@ AND source == %@ AND messageID IN %@",
                file,
                FileCheckpointSource.aiPre.rawValue,
                userMessageIDs
            )
            guard let checkpoints = try? context.fetch(fetch) else { return [] }
            return Set(checkpoints.compactMap(\.messageID))
        }
        revertableUserMessageIDs = ids
    }

    private func regenerateMessage(messageID: String) {
        guard let id = fileState.aiChatConversationID else { return }
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
                    alertToast.presentAIChatError(error)
                }
            }
        }
    }
    
    private func shouldShowStreamingMessage(
        _ stream: LLMStreamingStateObject,
        messages: [ChatMessage]
    ) -> Bool {
        if !stream.isFinished { return true }
        guard let lastID = messages.last?.id else { return !stream.content.isEmpty }
        return lastID != stream.id
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

private struct EditSessionBanner: View {
    let mode: AIChatState.EditSession.Mode
    let onCancel: () -> Void

    private var title: String {
        switch mode {
            case .edit: "Editing message"
            case .revert: "Editing with canvas revert"
        }
    }

    private var symbol: SFSymbol {
        switch mode {
            case .edit: .pencil
            case .revert: .arrowUturnBackward
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
        .background(.regularMaterial, in: Capsule())
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
