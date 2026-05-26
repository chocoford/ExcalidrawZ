//
//  AIChatView+Actions.swift
//  ExcalidrawZ
//

import CoreData
import LLMCore
import LLMKit
import SwiftUI

extension AIChatView {
    /// Start editing a historical user message. Plain edit is reversible
    /// until Send because truncation is delayed. Revert is destructive by
    /// design: after confirmation it immediately restores the canvas,
    /// truncates the timeline, and only then refills the input box.
    func beginEditingUserMessage(_ userMessageID: String) {
        guard let convo = conversation else { return }
        if llmState.isRunning(conversationID: convo.id) {
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

    func beginRevertingUserMessage(
        conversationID: String,
        content: ChatMessageContent
    ) {
        Task {
            do {
                llmState.cancelGeneration(conversationID: conversationID)
                try await restoreFileForRevert(
                    conversationID: conversationID,
                    userMessageID: content.id
                )
                try await llmState.truncateConversation(
                    in: conversationID,
                    fromMessageID: content.id,
                    inclusive: true
                )
                await MainActor.run {
                    aiChatState.finishEditing()
                    aiChatState.requestDraft(
                        content.content ?? "",
                        files: content.files ?? [],
                        draftKey: aiChatState.promptDraftKey(
                            conversationID: conversationID,
                            fileScope: nil
                        )
                    )
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
    func restoreFileForRevert(
        conversationID: String,
        userMessageID: String
    ) async throws {
        guard case .file(let file) = fileState.currentActiveFile else {
            throw AIChatEditError.unsupportedFile
        }

        let fileObjectID = file.objectID
        let context = PersistenceController.shared.newTaskContext()
        let link = try await PersistenceController.shared.aiMessageCheckpointLinkRepository.fetchLink(
            conversationID: conversationID,
            messageID: userMessageID,
            role: .revertAnchor
        )

        let checkpointObjectID: NSManagedObjectID? = try await context.perform {
            guard let file = try context.existingObject(with: fileObjectID) as? File else { return nil }

            if let link,
               link.checkpointKind == .file {
                let linkedFetch = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
                linkedFetch.predicate = NSPredicate(
                    format: "file == %@ AND id == %@",
                    file,
                    link.checkpointID as CVarArg
                )
                linkedFetch.fetchLimit = 1
                if let linkedCheckpoint = try context.fetch(linkedFetch).first {
                    return linkedCheckpoint.objectID
                }
            }
            return nil
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

    func revertRequirementRefreshKey(groups: [MessageGroup]) -> String {
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

    func refreshRevertRequiredUserMessageIDs(groups: [MessageGroup]) async {
        let assistantMessageIDs = Array(Set(assistantMessageIDs(in: groups)))
        guard !assistantMessageIDs.isEmpty,
              case .file = fileState.currentActiveFile
        else {
            revertRequiredUserMessageIDs = []
            return
        }
        let conversationID = conversation?.id ?? fileState.aiChatConversationID
        guard let conversationID else {
            revertRequiredUserMessageIDs = []
            return
        }
        let linkedAIPostMessageIDs: Set<String> = (try? await PersistenceController.shared.aiMessageCheckpointLinkRepository.fetchLinkedMessageIDs(
            conversationID: conversationID,
            role: .resultSnapshot,
            messageIDs: assistantMessageIDs
        )) ?? []

        let candidates = userMessageIDsBeforeAnyAIPost(
            groups: groups,
            aiPostMessageIDs: linkedAIPostMessageIDs
        )
        guard !candidates.isEmpty else {
            revertRequiredUserMessageIDs = []
            return
        }

        let candidateIDs = Array(candidates)
        let linkedAnchorIDs: Set<String> = (try? await PersistenceController.shared.aiMessageCheckpointLinkRepository.fetchLinkedMessageIDs(
            conversationID: conversationID,
            role: .revertAnchor,
            messageIDs: candidateIDs
        )) ?? []

        revertRequiredUserMessageIDs = candidates.intersection(linkedAnchorIDs)
    }

    func assistantMessageIDs(in groups: [MessageGroup]) -> [String] {
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

    func userMessageIDsBeforeAnyAIPost(
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

    func regenerateMessage(messageID: String) {
        guard AIChatAvailability.canUseAI else { return }
        guard let id = fileState.aiChatConversationID else { return }
        let retryContent = retryUserContent(forSourceMessageID: messageID)

        aiChatState.clearTransientError(for: id)
        aiChatState.clearGenerationCancellation(for: id)
        aiActionTask?.cancel()
        aiActionTask = Task {
            var attemptedModel: SupportedModel?
            do {
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                let model = try await retryModel(conversationID: id)
                attemptedModel = model
                try await refreshConversationToolsIfNeeded(
                    conversationID: id,
                    model: model
                )
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                let context = try await makeInvocationContext(model: model)
                let metadata = await makeTransactionMetadata(
                    conversationID: id,
                    userMessageID: retryContent?.id ?? messageID,
                    requestKind: .regenerateMessage,
                    model: model,
                    context: context,
                    attachmentCount: retryContent?.files?.count ?? 0
                )
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                try await llmState.regenerateMessage(
                    in: id,
                    fromMessageID: messageID,
                    model: model,
                    stream: true,
                    metadata: metadata,
                    context: context
                )
            } catch {
                await MainActor.run {
                    aiChatState.presentTransientError(
                        error,
                        conversationID: id,
                        userMessageID: retryContent?.id ?? messageID,
                        retryPrompt: retryContent?.content ?? "",
                        retryFiles: retryContent?.files ?? [],
                        retryModel: attemptedModel
                    )
                }
            }
        }
    }

    func resumeGeneration(modelOverride: SupportedModel? = nil) {
        guard AIChatAvailability.canUseAI else { return }
        guard let id = fileState.aiChatConversationID else { return }
        let retryContent = lastUserContent()

        aiChatState.clearTransientError(for: id)
        aiChatState.clearGenerationCancellation(for: id)
        aiActionTask?.cancel()
        aiActionTask = Task {
            var attemptedModel: SupportedModel?
            do {
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                let model = try await retryModel(
                    conversationID: id,
                    preferredModel: modelOverride
                )
                attemptedModel = model
                try await refreshConversationToolsIfNeeded(
                    conversationID: id,
                    model: model
                )
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                let context = try await makeInvocationContext(model: model)
                let metadata = await makeTransactionMetadata(
                    conversationID: id,
                    userMessageID: retryContent?.id ?? "",
                    requestKind: .resumeGeneration,
                    model: model,
                    context: context,
                    attachmentCount: retryContent?.files?.count ?? 0
                )
                guard AIChatAvailability.canUseAI else { throw CancellationError() }
                try await llmState.resumeGeneration(
                    in: id,
                    model: model,
                    stream: true,
                    metadata: metadata,
                    context: context
                )
            } catch {
                await MainActor.run {
                    aiChatState.presentTransientError(
                        error,
                        conversationID: id,
                        userMessageID: retryContent?.id ?? "",
                        retryPrompt: retryContent?.content ?? "",
                        retryFiles: retryContent?.files ?? [],
                        retryModel: attemptedModel
                    )
                }
            }
        }
    }

    @MainActor
    private func makeInvocationContext(
        model: SupportedModel
    ) async throws -> ExcalidrawChatInvocationContext {
        ExcalidrawCoordinatorRegistry.shared.update(
            normal: fileState.excalidrawWebCoordinator,
            collaboration: fileState.excalidrawCollaborationWebCoordinator
        )

        let canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = {
            switch fileState.currentActiveFile {
                case .collaborationFile:
                    .collaboration
                default:
                    .normal
            }
        }()

        let coordinator: ExcalidrawCanvasView.Coordinator? = switch canvasTarget {
            case .normal:
                fileState.excalidrawWebCoordinator
            case .collaboration:
                fileState.excalidrawCollaborationWebCoordinator
        }
        let ids = coordinator?.selectedElementIDs ?? []
        let selectedElementIDs = ids.isEmpty ? nil : ids

        let currentFileID: UUID? = {
            if case .file(let file) = fileState.currentActiveFile {
                return file.id
            }
            return nil
        }()

        let currentFileData = try await CurrentExcalidrawDataResolver.resolve(
            fileState: fileState,
            canvasTarget: canvasTarget
        )

        return ExcalidrawChatInvocationContext(
            currentFileData: currentFileData,
            canvasTarget: canvasTarget,
            selectedElementIDs: selectedElementIDs,
            currentFileID: currentFileID,
            currentModelSupportsImageInput: model.supportsExcalidrawImageInput
        )
    }

    private func makeTransactionMetadata(
        conversationID: String,
        userMessageID: String,
        requestKind: ExcalidrawAITransactionRequestKind,
        model: SupportedModel,
        context: ExcalidrawChatInvocationContext,
        attachmentCount: Int
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
            agentID: ExcalidrawAgentConfig.agentID,
            model: model.rawValue,
            canvasTarget: context.canvasTarget.rawValue,
            fileID: fileContext.id,
            fileName: fileContext.name,
            fileKind: fileContext.kind,
            selectedElementCount: context.selectedElementIDs?.count ?? 0,
            attachmentCount: attachmentCount,
            hasCurrentFileData: context.currentFileData != nil,
            isNewConversation: false
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

    private func retryModel(
        conversationID: String,
        preferredModel: SupportedModel? = nil
    ) async throws -> SupportedModel {
        guard AIChatAvailability.canUseAI else { throw CancellationError() }
        let agentConfig = try await LLMClient.shared.getDomainAgentConfig(agentID: "excalidraw-canvas")
        return try await MainActor.run {
            let requiresImageInput = conversation?.messages.contains { message in
                message.files?.containsImageInput == true
            } ?? false
            let preferences = AIChatPreferences.shared
            let canUse: (SupportedModel) -> Bool = { model in
                model.isVisibleInExcalidrawModelPicker
                    && agentConfig.allowedModels.contains(model)
                    && (!model.requiresMaxAIPlan || Store.shared.canUseExtraHighAIModel)
                    && (!requiresImageInput || model.supportsExcalidrawImageInput)
            }
            let selected: SupportedModel
            if let preferredModel {
                selected = preferredModel
            } else {
                let tier = preferences.tier(for: conversationID) ?? preferences.defaultTier
                selected = SupportedModel.nearestExcalidrawFallback(
                    to: tier,
                    from: agentConfig.allowedModels.filter(canUse)
                ) ?? tier.canonicalModel
            }
            guard !canUse(selected) else { return selected }
            throw AIChatRetryModelUnavailableError(
                model: selected,
                requiresImageInput: requiresImageInput
            )
        }
    }

    private func retryUserContent(forSourceMessageID messageID: String) -> ChatMessageContent? {
        guard let messages = conversation?.messages else { return nil }
        if let directUser = messages.compactMap(Self.contentMessage).first(where: {
            $0.id == messageID && $0.role == .user
        }) {
            return directUser
        }
        guard let sourceIndex = messages.firstIndex(where: { $0.id == messageID }) else {
            return nil
        }
        return messages[..<sourceIndex].reversed().compactMap(Self.contentMessage).first {
            $0.role == .user
        }
    }

    private func lastUserContent() -> ChatMessageContent? {
        conversation?.messages.reversed().compactMap(Self.contentMessage).first {
            $0.role == .user
        }
    }

    private static func contentMessage(_ message: ChatMessage) -> ChatMessageContent? {
        guard case .content(let content) = message else { return nil }
        return content
    }

    private func refreshConversationToolsIfNeeded(
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

    func retryTransientError(_ error: AIChatState.TransientError) {
        guard AIChatAvailability.canUseAI else { return }
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
            resumeGeneration(modelOverride: error.retryModel)
        } else {
            aiChatState.requestDraft(
                error.retryPrompt,
                files: error.retryFiles,
                draftKey: aiChatState.promptDraftKey(
                    conversationID: error.conversationID,
                    fileScope: nil
                )
            )
        }
    }

    @MainActor
    func cancelAIWorkForDisabledAI() {
        if let id = fileState.aiChatConversationID {
            llmState.cancelGeneration(conversationID: id)
            aiChatState.markGenerationCancelled(conversationID: id)
            aiChatState.unmarkCompacting(conversationID: id)
        }
        aiActionTask?.cancel()
        aiActionTask = nil
        aiChatState.pendingQueue.removeAll()
        aiChatState.cancelEditing(conversationID: fileState.aiChatConversationID)
    }
    
    func requestScrollToBottomIfNeeded(_ newBottomID: String?) {
        guard let newBottomID else { return }
        guard newBottomID != lastBottomID else { return }
        // First observation wires the current tail identity only. It can happen
        // while mounting existing history, so it must not animate the viewport.
        let wasFirstObservation = (lastBottomID == nil)
        lastBottomID = newBottomID
        guard isPinnedToBottom else { return }
        guard !wasFirstObservation else { return }
        requestScrollToBottom(animated: true)
    }

    func requestScrollToBottom(animated: Bool) {
        if animated {
            isAutoScrollingToBottom = true
            Task { @MainActor in
                // Plain scroll requests do not await a continuation, so reset
                // the transient "auto-scrolling" UI flag after the host settles.
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

private struct AIChatRetryModelUnavailableError: LocalizedError {
    let model: SupportedModel
    let requiresImageInput: Bool

    var errorDescription: String? {
        if requiresImageInput, !model.supportsExcalidrawImageInput {
            return "The original model for this retry cannot read image input."
        }
        return "The original model for this retry is no longer available."
    }
}
