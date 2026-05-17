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
    func restoreFileForRevert(userMessageID: String) async throws {
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
        guard let id = fileState.aiChatConversationID else { return }
        let retryContent = retryUserContent(forSourceMessageID: messageID)

        aiChatState.clearTransientError(for: id)
        aiChatState.clearGenerationCancellation(for: id)
        Task {
            do {
                let model = try await retryModel(conversationID: id)
                try await refreshConversationToolsIfNeeded(
                    conversationID: id,
                    model: model
                )
                let context = try await makeInvocationContext(model: model)
                try await llmState.regenerateMessage(
                    in: id,
                    fromMessageID: messageID,
                    model: model,
                    stream: true,
                    context: context
                )
            } catch {
                await MainActor.run {
                    aiChatState.presentTransientError(
                        error,
                        conversationID: id,
                        userMessageID: retryContent?.id ?? messageID,
                        retryPrompt: retryContent?.content ?? "",
                        retryFiles: retryContent?.files ?? []
                    )
                }
            }
        }
    }

    func resumeGeneration() {
        guard let id = fileState.aiChatConversationID else { return }
        let retryContent = lastUserContent()

        aiChatState.clearTransientError(for: id)
        aiChatState.clearGenerationCancellation(for: id)
        Task {
            do {
                let model = try await retryModel(conversationID: id)
                try await refreshConversationToolsIfNeeded(
                    conversationID: id,
                    model: model
                )
                let context = try await makeInvocationContext(model: model)
                try await llmState.resumeGeneration(
                    in: id,
                    model: model,
                    stream: true,
                    context: context
                )
            } catch {
                await MainActor.run {
                    aiChatState.presentTransientError(
                        error,
                        conversationID: id,
                        userMessageID: retryContent?.id ?? "",
                        retryPrompt: retryContent?.content ?? "",
                        retryFiles: retryContent?.files ?? []
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

    private func retryModel(conversationID: String) async throws -> SupportedModel {
        let agentConfig = try await LLMClient.shared.getDomainAgentConfig(agentID: "excalidraw-canvas")
        return await MainActor.run {
            let requiresImageInput = conversation?.messages.contains { message in
                message.files?.containsImageInput == true
            } ?? false
            let selected = AIChatPreferences.shared.model(for: conversationID) ?? agentConfig.defaultModel
            let canUse: (SupportedModel) -> Bool = { model in
                model.isVisibleInExcalidrawModelPicker
                    && agentConfig.allowedModels.contains(model)
                    && (!model.requiresMaxAIPlan || Store.shared.canUseExtraHighAIModel)
                    && (!requiresImageInput || model.supportsExcalidrawImageInput)
            }
            guard !canUse(selected) else { return selected }
            let candidates = agentConfig.allowedModels.filter(canUse)
            return SupportedModel.nearestExcalidrawFallback(to: selected, from: candidates)
                ?? .claudeSonnet4_6
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
            resumeGeneration()
        } else {
            aiChatState.requestDraft(error.retryPrompt, files: error.retryFiles)
        }
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
