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
    /// Confirmation dialog for the "Clear chat" toolbar action — destructive,
    /// so we route through a confirmationDialog rather than firing on tap.
    @State private var isConfirmingClear: Bool = false
    
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
        guard let req = llmState.pendingApprovalRequest else { return false }
        return aiChatState.revealedToolCallIDs.contains(req.toolCallID)
    }

    /// True while LLMKit's `compactConversation` is running on the
    /// conversation we're rendering. Drives the transient "compacting…"
    /// banner in the bottom stack so the user knows the next send is
    /// being held until the summary lands.
    private var isCompactingThisConversation: Bool {
        aiChatState.isCompacting(conversationID: fileState.aiChatConversationID)
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

                if isCompactingThisConversation {
                    CompactingIndicatorView()
                        .transition(.opacity)
                }

                ApprovalPromptView()

                PromptInputView(
                    conversationID: conversationID,
                    pendingQueue: $aiChatState.pendingQueue
                )
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
            onRegenerate: regenerateMessage,
            onRevertUserMessage: revertToUserMessage
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
    
    /// "Revert" action attached to each user message in the static history.
    /// Four steps, in order:
    ///
    /// 1. Cancel any in-flight stream so the restore doesn't race the
    ///    AI's autosave-tool-call dance.
    /// 2. Restore the file from the `.aiPre` checkpoint anchored to
    ///    this message id (same pipeline as `FileCheckpointDetailView`'s
    ///    manual restore).
    /// 3. Truncate the conversation at (and including) this user
    ///    message — wipes the old user message + AI reply + any
    ///    subsequent rounds, so the chat reads as if this turn never
    ///    happened.
    /// 4. Push the message's original text back into the input box so
    ///    the user can edit and re-send.
    private func revertToUserMessage(_ userMessageID: String) {
        guard let convo = conversation else { return }
        let conversationID = convo.id

        // Pull message text + sanity-check that it's actually a user msg.
        let text: String? = convo.messages.first {
            if case .content(let c) = $0,
               c.id == userMessageID,
               c.role == .user { return true }
            return false
        }.flatMap { msg -> String? in
            if case .content(let c) = msg { return c.content }
            return nil
        }
        guard let messageText = text else { return }

        // Cancel any in-flight stream first — reverting while the AI is
        // mid-reply would race the file restore against autosaves from
        // the still-running tool calls.
        llmState.cancelGeneration(conversationID: conversationID)

        Task { @MainActor in
            await performFileRestore(forUserMessageID: userMessageID)

            // Truncate the conversation: remove this user message + the
            // assistant's old reply + anything after. `inclusive: true`
            // because we're going to re-send a (possibly edited) version
            // of this same user message; leaving the original would
            // duplicate it.
            do {
                try await llmState.truncateConversation(
                    in: conversationID,
                    fromMessageID: userMessageID,
                    inclusive: true
                )
            } catch {
                alertToast.presentAIChatError(error)
                // Don't bail: file is already restored, draft prefill
                // still useful even if truncation failed.
            }

            // Push the original user text into the input box. Token-based
            // request handles the "revert twice with same text" case.
            aiChatState.requestDraft(messageText)
        }
    }

    /// Find the `.aiPre` checkpoint with `messageID == userMessageID` for
    /// the currently active file, and restore. Silently no-ops if no
    /// matching checkpoint exists (shouldn't happen for messages whose
    /// turn was opened with `beginAIChatSession`, but be defensive).
    private func performFileRestore(forUserMessageID userMessageID: String) async {
        guard case .file(let file) = fileState.currentActiveFile else {
            // Local files: revert path not implemented yet (see
            // `RestoreFileHistoryTool`'s scope note). Surface a toast
            // rather than failing silently.
            await MainActor.run {
                alertToast(.init(
                    displayMode: .hud,
                    type: .regular,
                    title: "Revert is currently only supported for library files."
                ))
            }
            return
        }

        let fileObjectID = file.objectID
        let context = PersistenceController.shared.newTaskContext()

        let checkpointObjectID: NSManagedObjectID? = await context.perform {
            let fetch = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
            fetch.predicate = NSPredicate(
                format: "file == %@ AND messageID == %@ AND source == %@",
                file,
                userMessageID,
                FileCheckpointSource.aiPre.rawValue
            )
            fetch.fetchLimit = 1
            return (try? context.fetch(fetch).first)?.objectID
        }

        guard let checkpointObjectID else {
            await MainActor.run {
                alertToast(.init(
                    displayMode: .hud,
                    type: .regular,
                    title: "No revert point found for this message."
                ))
            }
            return
        }

        do {
            let cpRepo = PersistenceController.shared.checkpointRepository
            let fileRepo = PersistenceController.shared.fileRepository

            try await cpRepo.restoreCheckpoint(
                checkpointObjectID: checkpointObjectID,
                to: fileObjectID
            )
            let content = try await cpRepo.loadCheckpointContent(
                checkpointObjectID: checkpointObjectID
            )
            try await fileRepo.saveFileContentToStorage(
                fileObjectID: fileObjectID,
                content: content
            )

            // Reload the canvas so the user sees the revert immediately.
            await MainActor.run {
                Task { await fileState.excalidrawWebCoordinator?.loadFile(from: file, force: true) }
                fileState.didUpdateFile = false
            }
        } catch {
            await MainActor.run {
                alertToast.presentAIChatError(error)
            }
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
