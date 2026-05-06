//
//  AIChatView.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/09.
//

import ChocofordUI
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
    
    var conversation: Conversation? {
        llmState.conversations.value?.first { $0.id == fileState.aiChatConversationID }
    }
    
    private var streamingState: LLMStreamingStateObject? {
        guard let id = fileState.aiChatConversationID else { return nil }
        return llmState.streamingStore.streamIfExists(for: id)
        as? LLMStreamingStateObject
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let conversation, !conversation.messages.isEmpty {
                messageList(messages: conversation.messages)
            } else {
                emptyPlaceholder()
            }
            
            VStack(spacing: 6) {
                PendingQueueView(
                    messages: aiChatState.pendingQueue,
                    onRemove: { id in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            aiChatState.pendingQueue.removeAll { $0.id == id }
                        }
                    }
                )

                PromptInputView(
                    conversationID: conversationID,
                    pendingQueue: $aiChatState.pendingQueue
                )
            }
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 10)
        .toolbar(content: toolbar)
        .task {
            await llmState.refreshConversations()
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
        NativeChatScrollView(
            isPinnedToBottom: $isPinnedToBottom,
            scrollToBottomRequest: $scrollToBottomRequest,
            isStreaming: isStreamingActive
        ) {
            messageListRows(messages: messages)
        }
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
        }
        .onChange(of: bottomID) { _ in
            requestScrollToBottomIfNeeded(bottomID)
        }
    }
    
    @ViewBuilder
    private func messageListRows(messages: [ChatMessage]) -> some View {
        let layout = makeRowLayout(messages: messages)
        
        StaticGroupsView(
            groups: layout.staticGroups,
            onRegenerate: regenerateMessage
        )
        .equatable()
        
        // Mount the live slot whenever there's *anything* to host — either an
        // active stream (whose inflight message is synthesized inside
        // `LiveAssistantRoundView`) or a committed trailing round (pinned
        // post-stream, until the next round pushes it out).
        //
        // The active-stream branch is critical: LLMKit only commits an
        // assistant message into `conversation.messages` at `.tool` boundaries
        // or stream end, so during the streaming of a `final_answer`-style
        // agent there's no committed assistant in the round yet. Without this
        // guard, the live slot stays empty for the whole streaming window and
        // `SmoothStreamingText` mounts only at stream end with the full text
        // already in hand — no visible streaming, no `ingest` ticks, the
        // batching/animation pipeline never runs.
        if layout.liveStream != nil || !layout.liveCommittedRound.isEmpty {
            ChatScrollRow {
                LiveAssistantRoundView(
                    committedMessages: layout.liveCommittedRound,
                    stream: layout.liveStream,
                    onRegenerate: regenerateMessage,
                    // `ChatScrollView`'s `followBottom` is on while streaming —
                    // it auto-scrolls on every contentHeight change. We don't
                    // need a per-chunk scroll request here too; that just
                    // queues up redundant scrolls before layout has settled.
                    onStreamUpdate: nil
                )
            }
        }
    }
    
    /// Partition committed messages into static groups + the most-recent
    /// assistant round (which lives in the "live slot").
    ///
    /// Crucially, `liveCommittedRound` is the trailing round **regardless of
    /// stream state** — when there's no active stream, the round is still
    /// hosted in the live slot, just rendered statically. This pins the round
    /// to a stable view position from the moment it starts streaming until
    /// a new round pushes it out, which preserves SwiftUI view identity (and
    /// the per-message `SmoothStreamingText` state inside) across the
    /// stream-end transition.
    private func makeRowLayout(messages: [ChatMessage]) -> RowLayout {
        let allGroups = groupMessages(messages)
        
        let activeStream: LLMStreamingStateObject? = {
            guard let s = streamingState,
                  shouldShowStreamingMessage(s, messages: messages)
            else { return nil }
            return s
        }()
        
        // Trailing round → live slot; everything before → static.
        if let last = allGroups.last, case .assistantRound(_, let msgs) = last {
            return RowLayout(
                staticGroups: Array(allGroups.dropLast()),
                liveStream: activeStream,
                liveCommittedRound: msgs
            )
        }
        
        // No trailing assistant round (e.g. only a user message so far). The
        // active stream — if any — will land here once its first chunk gets
        // committed. For now there's nothing to pin.
        return RowLayout(
            staticGroups: allGroups,
            liveStream: activeStream,
            liveCommittedRound: []
        )
    }
    
    @MainActor @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
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
            } label: {
                Label("More", systemSymbol: .ellipsis)
            }
            .menuIndicator(.hidden)
        }
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
        lastBottomID = newBottomID
        guard isPinnedToBottom else { return }
        requestScrollToBottom(animated: false)
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
