//
//  PromptInputView+Send.swift
//  ExcalidrawZ
//
//  Send pipeline for `PromptInputView`. The send button, the queue
//  drainer, the AI-checkpoint session bookends, the auto-compact
//  threshold check, and the cancel/stop path all live here.
//
//  Why split this out: `startSend` alone is ~180 lines of carefully
//  ordered awaits — checkpoint setup, conversation create vs. update
//  fork, file binding, post-stream session close — and reading it
//  next to view-builder code in the main file made the whole input
//  view feel like a single 900-line wall of glue. Putting it in its
//  own extension lets the main file be about *composition* and
//  *state*, and this file be about *pipeline*.
//

import SwiftUI
import CoreData
import LLMKit
import LLMCore

extension PromptInputView {
    /// Pre-send threshold (fraction of the active model's context window).
    /// At/above this we run a compact before firing the send so the round
    /// doesn't blow the cap. Picked conservatively — modern providers cope
    /// fine up to ~95% but auto-compacting earlier means the *next* round
    /// also has headroom rather than hovering on the edge.
    static var autoCompactThreshold: Double { 0.8 }

    // MARK: - Public entry

    /// User pressed Send (or Enter). Decides whether to fire the network
    /// pipeline immediately, queue the message behind an in-flight reply
    /// or compact, or run an auto-compact first because the round would
    /// otherwise overshoot the context window.
    @MainActor
    func submitDraft(
        prompt trimmedText: String,
        pastedImages: [PendingPastedImage]
    ) -> Bool {
        let files = PastedImageHelpers.buildFiles(from: pastedImages)
        guard !trimmedText.isEmpty || !files.isEmpty else { return false }
        let model = modelForSend(files: files)
        guard !files.containsImageInput || model.supportsExcalidrawImageInput else {
            alertToast(AIChatInputCapabilityError.noModelCanReadImages)
            return false
        }

        // Client-side credits gate: if we already know the balance is empty,
        // skip the round-trip and open the paywall immediately. We only block
        // when the value is loaded — `creditsInfo == nil` means "not fetched
        // yet" and we let the request go through (server will reject and the
        // catch-side dispatcher still routes to the paywall).
        if let balance = llmState.creditsInfo?.balance, balance <= 0 {
            Store.shared.togglePaywall(reason: .aiInsufficientCredits)
            return false
        }

        if let editSession = aiChatState.editSession,
           editSession.conversationID == conversationID {
            startEditedSend(
                prompt: trimmedText,
                files: files,
                editSession: editSession
            )
            return true
        }

        // Mid-stream OR mid-compact: queue and clear the input so the user
        // can keep typing. The drain runs when the in-flight task finishes
        // (either `currentTask` for a stream, or the Task in
        // `compactCurrentContext` for a compact).
        if isGenerating || isCompactingContext {
            enqueue(text: trimmedText, files: files)
            return true
        }

        // Auto-compact gate: if appending this prompt would push the
        // conversation past the configured fraction of the model's
        // context window, run compact first and queue the message so it
        // lands after the summary insertion. The compact's completion
        // path calls `drainQueueIfNeeded()`, which fires this send.
        if shouldAutoCompactBeforeSend() {
            enqueue(text: trimmedText, files: files)
            compactCurrentContext()
            return true
        }

        startSend(prompt: trimmedText, files: files)
        return true
    }

    /// Editing/reverting a previous user turn is a two-phase send:
    /// first make the existing timeline look like the old turn never
    /// happened, then send the replacement prompt through the normal path.
    private func startEditedSend(
        prompt: String,
        files: [ChatMessageContent.File],
        editSession: AIChatState.EditSession
    ) {
        currentTask = Task {
            do {
                llmState.cancelGeneration(conversationID: editSession.conversationID)
                try await llmState.truncateConversation(
                    in: editSession.conversationID,
                    fromMessageID: editSession.userMessageID,
                    inclusive: true
                )
                await MainActor.run {
                    aiChatState.finishEditing()
                    startSend(prompt: prompt, files: files)
                }
            } catch {
                await MainActor.run {
                    currentTask = nil
                    aiChatState.requestDraft(prompt, files: files)
                    alertToast.presentAIChatError(error)
                }
            }
        }
    }

    /// Append to the pending queue and clear the input. Hoisted out
    /// of `sendMessage` because all three "queue, don't fire" branches
    /// (mid-stream, mid-compact, auto-compact) share the same fix-up.
    private func enqueue(text: String, files: [ChatMessageContent.File]) {
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingQueue.append(
                PendingQueueMessage(text: text, files: files)
            )
        }
    }

    /// Returns true when the conversation's LLMKit-estimated active
    /// context is above `autoCompactThreshold` of the active model's
    /// context window.
    ///
    /// Skips the check when there's no conversation yet (a fresh
    /// chat has nothing to roll up — the prompt itself is the first
    /// turn).
    @MainActor
    private func shouldAutoCompactBeforeSend() -> Bool {
        guard let conversationID else { return false }
        let used = llmState.estimatedTokenUsage(in: conversationID)
        guard let cap = activeModel.maxContextTokens else { return false }
        guard cap > 0 else { return false }
        return Double(used) >= Double(cap) * Self.autoCompactThreshold
    }

    // MARK: - Stream pipeline

    /// Kicks off the actual network/stream pipeline for `prompt`. Stores the
    /// Task in `currentTask` so the stop button can cancel it; on completion
    /// (success or failure) it clears the slot and drains the queue.
    func startSend(prompt: String, files: [ChatMessageContent.File] = []) {
        let newConversationID = UUID().uuidString
        let conversationIDForSession: String = self.conversationID ?? newConversationID
        aiChatState.clearGenerationCancellation(for: conversationIDForSession)

        // Build the user message ahead of time so we can capture its id
        // for the AI chat session begin hook (anchors the `.aiPre`
        // checkpoint to this exact message — UI later renders a
        // "revert to here" affordance on the message row).
        let userMessage = ChatMessageContent(
            role: .user,
            content: prompt,
            files: files
        )
        let userMessageID = userMessage.id

        currentTask = Task {
            // Tracked so the trailing block can decide whether to write
            // `.aiPost` (success) or just clear suppression (failure /
            // cancel).
            var sessionOpened = false
            var streamSucceeded = false

            do {
                await MainActor.run {
                    aiChatState.clearTransientError(for: conversationIDForSession)
                }
                await MainActor.run {
                    ExcalidrawCoordinatorRegistry.shared.update(
                        normal: fileState.excalidrawWebCoordinator,
                        collaboration: fileState.excalidrawCollaborationWebCoordinator
                    )
                }
                let canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = {
                    switch fileState.currentActiveFile {
                        case .collaborationFile:
                            .collaboration
                        default:
                            .normal
                    }
                }()
                let selectedElementIDs: [String]? = await MainActor.run {
                    let coordinator: ExcalidrawCanvasView.Coordinator? = switch canvasTarget {
                        case .normal:
                            fileState.excalidrawWebCoordinator
                        case .collaboration:
                            fileState.excalidrawCollaborationWebCoordinator
                    }
                    let ids = coordinator?.selectedElementIDs ?? []
                    return ids.isEmpty ? nil : ids
                }
                let currentFileID: UUID? = await MainActor.run {
                    if case .file(let file) = fileState.currentActiveFile {
                        return file.id
                    }
                    return nil
                }
                // Make sure agent config is loaded so `activeModel` resolves to the
                // server-blessed default (or the user's picker selection) rather
                // than the hard-coded fallback.
                await loadAgentConfigIfNeeded()
                let model = await MainActor.run { modelForSend(files: files) }
                let isNewConversation = self.conversation == nil
                if !isNewConversation {
                    try await refreshExistingConversationToolsIfNeeded(
                        conversationID: conversationIDForSession,
                        model: model
                    )
                }
                let context = try await ExcalidrawChatInvocationContext(
                    currentFileData: currentFileData,
                    canvasTarget: canvasTarget,
                    selectedElementIDs: selectedElementIDs,
                    currentFileID: currentFileID,
                    currentModelSupportsImageInput: model.supportsExcalidrawImageInput
                )
                let metadata = await makeTransactionMetadata(
                    conversationID: conversationIDForSession,
                    userMessageID: userMessageID,
                    requestKind: isNewConversation ? .createConversation : .sendMessage,
                    model: model,
                    canvasTarget: canvasTarget,
                    selectedElementCount: selectedElementIDs?.count ?? 0,
                    attachmentCount: files.count,
                    hasCurrentFileData: context.currentFileData != nil,
                    isNewConversation: isNewConversation
                )

                // Open the AI chat session: snapshots the current active
                // file as `.aiPre` (anchored to this user message) and
                // flips suppression on so all canvas mutations during
                // the round don't write to user history.
                try await fileState.beginAIChatSession(
                    conversationID: conversationIDForSession,
                    userMessageID: userMessageID
                )
                sessionOpened = true

                if isNewConversation {
                    self.conversationID = newConversationID
                    // Promote the staged pick (if any) to a per-conversation
                    // override now that we have an id. Without this, the
                    // user's pre-send model choice would be lost on reopen
                    // — `pendingModelSelection` is @State, conversation
                    // overrides survive the view's lifetime.
                    if await MainActor.run(body: { pendingModelSelection != nil }) {
                        await MainActor.run {
                            prefs.setModel(model, for: newConversationID)
                            pendingModelSelection = nil
                        }
                    }
                    try await llmState.createConversation(
                        id: newConversationID,
                        type: .regular,
                        model: model,
                        // Tool roster + agentID centralized in
                        // `ExcalidrawAgentConfig` so the persistence
                        // restore path uses the exact same wiring.
                        agentConfig: ExcalidrawAgentConfig.defaultConfig(
                            supportsImageInput: model.supportsExcalidrawImageInput
                        ),
                        messages: [.content(userMessage)],
                        metadata: metadata,
                        context: context
                    )

                    // Bind the new conversation to the active file's
                    // unified scope so library files, URL-backed files,
                    // and collaboration files can all resume their own
                    // latest conversation on the next open.
                    let scopeForBinding = await MainActor.run {
                        fileState.currentActiveFile?.aiConversationFileScope
                    }
                    if let scope = scopeForBinding {
                        do {
                            try await PersistenceController.shared.aiConversationRepository
                                .bindConversationToFileScope(
                                    conversationID: newConversationID,
                                    scope: scope
                                )
                        } catch {
                            print("[AIChatDiag] post-create bind threw \(error.localizedDescription)")
                        }
                    }
                } else {
                    try await llmState.sendMessage(
                        to: self.conversationID!,
                        model: model,
                        message: .content(userMessage),
                        metadata: metadata,
                        context: context
                    )
                }

                // Stream completed without throwing. The `.aiPost`
                // snapshot will anchor to whatever the trailing assistant
                // message id ends up being — read after-the-fact rather
                // than guessing.
                streamSucceeded = true
            } catch {
                // Keep send-pipeline failures in the chat transcript area as
                // a transient client row. It is not committed to LLMKit's
                // conversation; retry resumes when the triggering user
                // message already reached the timeline, otherwise it
                // restores the draft into the input.
                await MainActor.run {
                    aiChatState.presentTransientError(
                        error,
                        conversationID: conversationIDForSession,
                        userMessageID: userMessageID,
                        retryPrompt: prompt,
                        retryFiles: files
                    )
                }
            }

            // Close the session unconditionally. Behaviour split:
            //   - success + canvasModified: write `.aiPost` snapshot
            //     anchored to the trailing assistant message
            //   - success + !canvasModified: delete the eager `.aiPre`
            //     (the round was read-only, no history value)
            //   - !success: keep `.aiPre` for revert, no `.aiPost`
            //
            // `canvasModified` is decided by inspecting the round's
            // assistant tool calls — only canvas-mutating ones (per
            // `ExcalidrawAgentConfig.canvasModifyingToolNames`) count.
            // Pure-chat rounds, search/read-only tool rounds, and
            // navigation-only rounds all leave the canvas untouched
            // and shouldn't burn a history entry.
            if sessionOpened {
                let (assistantMessageID, canvasModified): (String?, Bool) = await MainActor.run {
                    guard streamSucceeded else { return (nil, false) }
                    let convo = llmState.conversations.value?
                        .first(where: { $0.id == conversationIDForSession })
                    let lastAssistantID = convo?.messages.last(where: {
                        if case .content(let c) = $0, c.role == .assistant {
                            return true
                        }
                        return false
                    })?.id
                    let modified = roundUsedCanvasModifyingTool(
                        in: convo,
                        sinceUserMessageID: userMessageID
                    )
                    return (lastAssistantID, modified)
                }
                // `description` is intentionally nil for now — wired up
                // later (likely from `final_answer` tool args).
                await fileState.endAIChatSession(
                    success: streamSucceeded,
                    canvasModified: canvasModified,
                    assistantMessageID: assistantMessageID,
                    description: nil
                )
            }

            await MainActor.run {
                currentTask = nil
                drainQueueIfNeeded()
            }
        }
    }

    private func refreshExistingConversationToolsIfNeeded(
        conversationID: String,
        model: SupportedModel
    ) async throws {
        let tools = ExcalidrawAgentConfig.toolNames(
            supportsImageInput: model.supportsExcalidrawImageInput
        )
        let currentTools = await MainActor.run {
            conversation?.agentConfig.tools
        }
        guard currentTools != tools else { return }

        try await PersistenceController.shared.aiConversationRepository.updateTools(
            conversationID: conversationID,
            toolsData: ExcalidrawAgentConfig.encodeToolNames(tools)
        )
        await llmState.refreshConversations()
    }

    private func makeTransactionMetadata(
        conversationID: String,
        userMessageID: String,
        requestKind: ExcalidrawAITransactionRequestKind,
        model: SupportedModel,
        canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget,
        selectedElementCount: Int,
        attachmentCount: Int,
        hasCurrentFileData: Bool,
        isNewConversation: Bool
    ) async -> ExcalidrawAITransactionMetadata {
        let fileContext = await MainActor.run {
            transactionFileContext(for: fileState.currentActiveFile)
        }

        return ExcalidrawAITransactionMetadata(
            schemaVersion: 1,
            source: .aiChatSidebar,
            conversationID: conversationID,
            userMessageID: userMessageID,
            requestKind: requestKind,
            agentID: agentID,
            model: model.rawValue,
            canvasTarget: canvasTarget.rawValue,
            fileID: fileContext.id,
            fileName: fileContext.name,
            fileKind: fileContext.kind,
            selectedElementCount: selectedElementCount,
            attachmentCount: attachmentCount,
            hasCurrentFileData: hasCurrentFileData,
            isNewConversation: isNewConversation
        )
    }

    @MainActor
    private func transactionFileContext(
        for activeFile: FileState.ActiveFile?
    ) -> (id: String?, name: String?, kind: String?) {
        guard let activeFile else {
            return (nil, nil, nil)
        }

        switch activeFile {
            case .file(let file):
                let scope = activeFile.aiConversationFileScope
                return (scope.id, file.name, scope.kind.rawValue)
            case .localFile:
                let scope = activeFile.aiConversationFileScope
                return (scope.id, activeFile.name, scope.kind.rawValue)
            case .temporaryFile:
                let scope = activeFile.aiConversationFileScope
                return (scope.id, activeFile.name, scope.kind.rawValue)
            case .collaborationFile(let file):
                let scope = activeFile.aiConversationFileScope
                return (scope.id, file.name, scope.kind.rawValue)
        }
    }

    /// True if any assistant message at or after `userMessageID`
    /// carries a tool call whose name is in
    /// `ExcalidrawAgentConfig.canvasModifyingToolNames`. Drives the
    /// "skip the .aiPost / clean up the .aiPre" decision in
    /// `endAIChatSession` — pure-chat rounds, search-only rounds,
    /// navigation-only rounds, etc. all return false and the round's
    /// pre-snapshot is dropped.
    ///
    /// We scan from the user message anchor (rather than e.g. the
    /// trailing assistant message backwards) so a round that produced
    /// multiple assistant turns — intermediate tool-using turn(s) +
    /// final summary — is checked end-to-end. Falls back to "the
    /// whole conversation" if the user message can't be located in
    /// the snapshot, which is conservative but safe (false positive
    /// just leaves a history pair we'd otherwise drop).
    @MainActor
    func roundUsedCanvasModifyingTool(
        in conversation: Conversation?,
        sinceUserMessageID userMessageID: String
    ) -> Bool {
        guard let conversation else { return false }
        let messages = conversation.messages
        let startIndex: Int = {
            if let idx = messages.firstIndex(where: { $0.id == userMessageID }) {
                return idx
            }
            return messages.startIndex
        }()
        let modifying = ExcalidrawAgentConfig.canvasModifyingToolNames
        return messages[startIndex...].contains { msg in
            guard case .content(let c) = msg, c.role == .assistant else { return false }
            return c.toolCalls?.contains(where: { modifying.contains($0.name) }) == true
        }
    }

    /// Stop button: ask LLMKit to terminate the in-flight generation
    /// (closes the SSE stream + cleans up streamingStore + commits/rolls back
    /// partial state per LLMKit's policy). Then locally cancel our send Task
    /// so its `await` chain unwinds quickly, and drop any queued follow-ups
    /// — "stop" is the user's intent to halt, not "stop this one but send
    /// the next".
    func cancelCurrentGeneration() {
        if let id = conversationID {
            llmState.cancelGeneration(conversationID: id)
            aiChatState.markGenerationCancelled(conversationID: id)
        }
        currentTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingQueue.removeAll()
        }
    }

    // MARK: - Compact

    /// Hand off to LLMKit's `compactConversation`. Drives state through
    /// `aiChatState.compactingConversationIDs` (lifted out of @State so
    /// `AIChatView` can render a compacting indicator without prop
    /// drilling). On completion, drains the pending queue so any
    /// auto-compact-queued message fires next.
    ///
    /// `summaryModel: .gpt4oMini` is the cheap "Low" tier; the
    /// summary just compresses history, no need to spend Sonnet
    /// credits on it. LLMKit always rolls in the full pre-compaction
    /// timeline (no keep-recent knob), so after this returns the
    /// chat shows just the summary card and any subsequent messages.
    func compactCurrentContext() {
        guard let id = conversationID, !isCompactingContext else { return }
        aiChatState.markCompacting(conversationID: id)
        Task {
            do {
                try await llmState.compactConversation(
                    id,
                    summaryModel: .gpt4oMini
                )
            } catch {
                await MainActor.run {
                    alertToast.presentAIChatError(error)
                }
            }
            await MainActor.run {
                aiChatState.unmarkCompacting(conversationID: id)
                // Drain even on failure: the user's pending message is
                // already in the queue, dropping it silently would be
                // worse than letting the next send hit (and surface)
                // the LLM-side cap as a normal error toast.
                drainQueueIfNeeded()
            }
        }
    }

    /// Pop the next queued message and start a fresh send. Called from
    /// the completion path of `startSend` (post-generation) and
    /// `compactCurrentContext` (post-compact) so messages flow strictly
    /// serially across both kinds of in-flight work.
    func drainQueueIfNeeded() {
        guard !pendingQueue.isEmpty else { return }
        let next: PendingQueueMessage = withAnimation(.easeInOut(duration: 0.2)) {
            pendingQueue.removeFirst()
        }
        startSend(prompt: next.text, files: next.files)
    }
}
