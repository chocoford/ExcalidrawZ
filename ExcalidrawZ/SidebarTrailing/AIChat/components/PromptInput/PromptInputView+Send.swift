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
import Logging
import LLMKit
import LLMCore

private let promptInputSendLogger = Logger(label: "PromptInputSend")

struct AIChatModelProfileUnavailableError: LocalizedError {
    var errorDescription: String? {
        "The selected AI model profile is not available."
    }
}

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
        guard AIChatAvailability.canUseAI else { return false }
        do {
            if let conversationID { try inferenceSessions.requireTransportReady(conversationID) }
            let route = try routeForSend()
            if case .basicBYOK(let connectionID, let modelID) = route {
                _ = try inferenceBilling.directSnapshot(connectionID: connectionID,
                    configuration: conversation?.directConnection?.configuration, modelID: modelID)
            } else if let binding = route.binding {
                _ = try inferenceBilling.resolveSelection(for: binding)
            } else {
                _ = try inferenceBilling.resolveSelection()
            }
        } catch {
            alertToast.presentAIChatError(error)
            return false
        }
        let files = PastedImageHelpers.buildFiles(from: pastedImages)
        guard !trimmedText.isEmpty || !files.isEmpty else { return false }
        if let modelOption = modelSelectionForSend(files: files),
           files.containsImageInput,
           !modelOption.supportsImageInput {
            alertToast(AIChatInputCapabilityError.noModelCanReadImages)
            return false
        }

        // Client-side credits gate: if we already know the balance is empty,
        // skip the round-trip and open the paywall immediately. We only block
        // when the value is loaded — `creditsInfo == nil` means "not fetched
        // yet" and we let the request go through (server will reject and the
        // catch-side dispatcher still routes to the paywall).
        if !modelPickerUsesBYOK,
           let balance = llmState.creditsInfo?.balance, balance <= 0 {
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
        let billingRevision = inferenceBilling.modelCatalogRevision
        currentTask = Task {
            do {
                llmState.cancelGeneration(conversationID: editSession.conversationID)
                try await llmState.truncateConversation(
                    in: editSession.conversationID,
                    fromMessageID: editSession.userMessageID,
                    inclusive: true
                )
                try await MainActor.run {
                    try inferenceBilling.validateSelection(expectedRevision: billingRevision)
                    aiChatState.finishEditing()
                    startSend(prompt: prompt, files: files, expectedBillingRevision: billingRevision)
                }
            } catch {
                await MainActor.run {
                    currentTask = nil
                    aiChatState.requestDraft(
                        prompt,
                        files: files,
                        draftKey: promptDraftKey
                    )
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
                PendingQueueMessage(text: text, files: files, billingRevision: inferenceBilling.modelCatalogRevision)
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
        guard let cap = activeModelContextWindowTokens else { return false }
        guard cap > 0 else { return false }
        return Double(used) >= Double(cap) * Self.autoCompactThreshold
    }

    // MARK: - Stream pipeline

    /// Kicks off the actual network/stream pipeline for `prompt`. Stores the
    /// Task in `currentTask` so the stop button can cancel it; on completion
    /// (success or failure) it clears the slot and drains the queue.
    func startSend(prompt: String, files: [ChatMessageContent.File] = [], expectedBillingRevision: Int? = nil) {
        guard AIChatAvailability.canUseAI else { return }
        let billingRevision = expectedBillingRevision ?? inferenceBilling.modelCatalogRevision
        let existingConversationID = self.conversationID
        let fileScopeForSession = fileState.currentActiveFile?.aiConversationFileScope
        let requiresImageInput = requiresImageInputModel || files.containsImageInput
        let capturedRoute = try? routeForSend()
        let preferredInteractionMode = prefs.interactionMode(for: fileState.currentActiveFile)
        let newConversationID = UUID().uuidString
        let conversationIDForSession: String = existingConversationID ?? newConversationID
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
            var attemptedModelProfileID: String?

            do {
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                await MainActor.run {
                    aiChatState.clearTransientError(for: conversationIDForSession)
                }
                guard let route = capturedRoute else { throw AIChatRoutingError.invalidRoute }
                if route == .legacy, let existingConversationID {
                    try await routing.loadLegacySelection(conversationID: existingConversationID)
                } else if !route.usesBYOK {
                    await schemeCatalog.refresh(force: true, forServerConversation: existingConversationID != nil)
                }
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                if existingConversationID == nil || route == .legacy {
                    try inferenceBilling.validateSelection(expectedRevision: billingRevision)
                }
                let modelOption = try routing.modelSelection(for: route, conversationID: existingConversationID)
                guard !requiresImageInput || modelOption.supportsImageInput else {
                    throw AIChatInputCapabilityError.noModelCanReadImages
                }
                let model = modelOption.model
                attemptedModelProfileID = modelOption.profileID
                await ensureConversationCacheLoaded()
                let isNewConversation = existingConversationID == nil
                guard isNewConversation || llmState.getConversation(by: conversationIDForSession) != nil else {
                    throw AIChatRoutingError.invalidRoute
                }
                let imageAttachments = AIChatImageAttachmentReference.makeReferences(from: files)
                let canIncludeActiveFileContext = await activeFileAllowsAIContext()
                let invocationPlan = AIChatInvocationPlan.make(
                    fileState: fileState,
                    preferredInteractionMode: preferredInteractionMode,
                    includesCurrentFileContext: canIncludeActiveFileContext
                )
                if !isNewConversation {
                    try await refreshExistingConversationToolsIfNeeded(
                        conversationID: conversationIDForSession,
                        supportsImageInput: modelOption.supportsImageInput,
                        mode: invocationPlan.interactionMode,
                        includesCurrentFileContext: invocationPlan.includesCurrentFileContext
                    )
                }
                try await routing.withRequest(route: route,
                    conversationID: isNewConversation ? nil : conversationIDForSession,
                    state: llmState, expectedBillingRevision: billingRevision) {
                    try await LockedContentAIGuard.withProtectedContentAccessDenied {
                        guard AIChatAvailability.canUseAI else { throw CancellationError() }
                        let context = try await invocationPlan.makeContext(
                            fileState: fileState,
                            model: model,
                            supportsImageInput: modelOption.supportsImageInput,
                            imageAttachments: imageAttachments
                        )
                        let metadata = await makeTransactionMetadata(
                            conversationID: conversationIDForSession,
                            userMessageID: userMessageID,
                            requestKind: isNewConversation ? .createConversation : .sendMessage,
                            model: model,
                            modelProfileID: modelOption.profileID,
                            invocationPlan: invocationPlan,
                            attachmentCount: files.count,
                            hasCurrentFileData: context.currentFileData != nil,
                            isNewConversation: isNewConversation
                        )
                        guard AIChatAvailability.canUseAI else { throw CancellationError() }

                        guard self.conversationID == existingConversationID,
                              fileState.currentActiveFile?.aiConversationFileScope == fileScopeForSession else {
                            throw AIInferenceBillingError.selectionChanged
                        }
                        // Open the AI chat session: snapshots the current active
                        // file as `.aiPre` (anchored to this user message) and
                        // flips suppression on so all canvas mutations during
                        // the round don't write to user history.
                        if invocationPlan.usesMutationSession {
                            try await fileState.beginAIChatSession(
                                conversationID: conversationIDForSession,
                                userMessageID: userMessageID
                            )
                            sessionOpened = true
                        }

                        if isNewConversation {
                            self.conversationID = newConversationID
                            pendingProfileID = nil
                            do {
                                try await llmState.createConversation(
                                    id: newConversationID,
                                    type: .regular,
                                    model: model,
                                    // Tool roster + agentID centralized in
                                    // `ExcalidrawAgentConfig` so the persistence
                                    // restore path uses the exact same wiring.
                                    agentConfig: ExcalidrawAgentConfig.config(isDirect: route.isDirect,
                                        mode: invocationPlan.interactionMode,
                                        supportsImageInput: modelOption.supportsImageInput,
                                        includesCurrentFileContext: invocationPlan.includesCurrentFileContext
                                    ),
                                    messages: [.content(userMessage)],
                                    metadata: metadata,
                                    context: context
                                )
                            }

                            // Bind the new conversation to the active file's
                            // unified scope so library files, URL-backed files,
                            // and collaboration files can all resume their own
                            // latest conversation on the next open.
                            if let scope = fileScopeForSession {
                                do {
                                    try await PersistenceController.shared.aiConversationRepository
                                        .bindConversationToFileScope(
                                            conversationID: newConversationID,
                                            scope: scope
                                        )
                                } catch {
                                    promptInputSendLogger.warning("Failed to bind new AI conversation to file scope: \(error)")
                                }
                            }
                        } else {
                            do {
                                try await llmState.sendMessage(
                                    to: conversationIDForSession,
                                    model: model,
                                    message: .content(userMessage),
                                    metadata: metadata,
                                    context: context
                                )
                            }
                        }

                        // Stream completed without throwing. The `.aiPost`
                        // snapshot will anchor to whatever the trailing assistant
                        // message id ends up being — read after-the-fact rather
                        // than guessing.
                        streamSucceeded = true
                    }
                }
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
                        retryFiles: files,
                        retryModelProfileID: attemptedModelProfileID
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

    func refreshExistingConversationToolsIfNeeded(
        conversationID: String,
        supportsImageInput: Bool,
        mode: AIChatInteractionMode,
        includesCurrentFileContext: Bool
    ) async throws {
        let tools = ExcalidrawAgentConfig.config(isDirect: conversation?.directConnection != nil,
            mode: mode,
            supportsImageInput: supportsImageInput,
            includesCurrentFileContext: includesCurrentFileContext
        ).tools
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

    @MainActor
    private func ensureConversationCacheLoaded() async {
        guard case .loaded = llmState.conversations else {
            await llmState.refreshConversations()
            return
        }
    }

    private func makeTransactionMetadata(
        conversationID: String,
        userMessageID: String,
        requestKind: ExcalidrawAITransactionRequestKind,
        model: SupportedModel,
        modelProfileID: String?,
        invocationPlan: AIChatInvocationPlan,
        attachmentCount: Int,
        hasCurrentFileData: Bool,
        isNewConversation: Bool
    ) async -> ExcalidrawAITransactionMetadata {
        let fileContext = await MainActor.run {
            invocationPlan.includesCurrentFileContext
                ? transactionFileContext(for: fileState.currentActiveFile)
                : (id: nil, name: nil, kind: nil)
        }

        return ExcalidrawAITransactionMetadata(
            schemaVersion: 1,
            source: .aiChatSidebar,
            conversationID: conversationID,
            userMessageID: userMessageID,
            requestKind: requestKind,
            agentID: agentID,
            model: model.rawValue,
            modelProfileID: modelProfileID,
            canvasTarget: invocationPlan.toolCanvasTarget.rawValue,
            fileID: fileContext.id,
            fileName: fileContext.name,
            fileKind: fileContext.kind,
            selectedElementCount: invocationPlan.selectedElementCount,
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
            case .cloudStorageFile:
                let scope = activeFile.aiConversationFileScope
                return (scope.id, activeFile.name, scope.kind.rawValue)
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
        compactTask?.cancel()
        compactTask = nil
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
    /// Platform summaries use gpt4oMini. BYOK uses the current chat model.
    /// LLMKit rolls in the full pre-compaction
    /// timeline (no keep-recent knob), so after this returns the
    /// chat shows just the summary card and any subsequent messages.
    func compactCurrentContext() {
        guard AIChatAvailability.canUseAI,
              let id = conversationID,
              !isCompactingContext else { return }
        aiChatState.markCompacting(conversationID: id)
        let capturedRoute = try? routeForSend()
        compactTask = Task {
            do {
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                guard let route = capturedRoute else { throw AIChatRoutingError.invalidRoute }
                try await routing.withRequest(route: route, conversationID: id, state: llmState) {
                    let model: SupportedModel = route == .legacy
                        ? try inferenceBilling.modelForAuxiliaryRequest(fallback: .gpt4oMini,
                            conversationModel: routing.modelSelection(for: route, conversationID: id).model)
                        : .gpt4oMini
                    // The SDK resolves bound BYOK summaries from the saved chat/auxiliary model.
                    try await llmState.compactConversation(
                        id,
                        summaryModel: model
                    )
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    alertToast.presentAIChatError(error)
                }
            }
            await MainActor.run {
                compactTask = nil
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
        guard AIChatAvailability.canUseAI else {
            withAnimation(.easeInOut(duration: 0.2)) {
                pendingQueue.removeAll()
            }
            return
        }
        let next: PendingQueueMessage = withAnimation(.easeInOut(duration: 0.2)) {
            pendingQueue.removeFirst()
        }
        startSend(prompt: next.text, files: next.files, expectedBillingRevision: next.billingRevision)
    }
}
