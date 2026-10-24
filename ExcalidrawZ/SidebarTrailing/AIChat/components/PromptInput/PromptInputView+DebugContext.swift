//
//  PromptInputView+DebugContext.swift
//  ExcalidrawZ
//

#if DEBUG
import SwiftUI
import LLMCore
import LLMKit

extension PromptInputView {
    @ViewBuilder
    var debugChatContextButton: some View {
        Button {
            generateDebugChatContext()
        } label: {
            if isGeneratingDebugContext {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption)
                    .frame(width: 18, height: 18)
            }
        }
        .disabled(isGeneratingDebugContext)
        .help(String(localizable: .debugChatContextHelp))
#if os(iOS)
        .frame(minWidth: 32, minHeight: 32)
        .contentShape(Rectangle())
        .hoverEffect()
#endif
    }

    var debugChatContextSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(.localizable(.debugChatContextTitle))
                        .font(.headline)
                    Text(.localizable(.debugChatContextMessage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !debugContextText.isEmpty {
                    CopyFeedbackButton(
                        text: debugContextText,
                        help: String(localizable: .debugChatContextCopyHelp),
                        iconFrame: CGSize(width: 16, height: 16),
                        iconFont: .body
                    )
                    .buttonStyle(.plain)
                }

                Button {
                    isDebugContextPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localizable: .generalButtonClose))
            }

            sheetBody
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 480)
    }

    @ViewBuilder
    private var sheetBody: some View {
        if isGeneratingDebugContext {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text(.localizable(.debugChatContextGenerating))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !debugContextError.isEmpty {
            Text(debugContextError)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        } else {
            ScrollView {
                Text(debugContextText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.quaternary)
            }
        }
    }

    @MainActor
    func generateDebugChatContext() {
        guard !isGeneratingDebugContext else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            isDebugContextPresented = true
        }
        isGeneratingDebugContext = true
        debugContextError = ""

        Task { @MainActor in
            do {
                debugContextText = try await makeDebugChatContextText()
            } catch {
                debugContextText = ""
                debugContextError = error.localizedDescription
            }
            isGeneratingDebugContext = false
        }
    }

    @MainActor
    private func makeDebugChatContextText() async throws -> String {
        guard let conversationID else {
            throw DebugChatContextError.noConversation
        }

        let prompt = promptDraftState.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = PastedImageHelpers.buildFiles(from: promptDraftState.images)

        await loadAgentConfigIfNeeded()

        guard let modelOption = modelSelectionForSend(files: files) else {
            throw AIChatModelProfileUnavailableError()
        }
        let model = modelOption.model
        let canIncludeActiveFileContext = await activeFileAllowsAIContext()
        let invocationPlan = AIChatInvocationPlan.make(
            fileState: fileState,
            preferredInteractionMode: prefs.interactionMode(for: fileState.currentActiveFile),
            includesCurrentFileContext: canIncludeActiveFileContext
        )
        try await refreshExistingConversationToolsIfNeeded(
            conversationID: conversationID,
            supportsImageInput: modelOption.supportsImageInput,
            mode: invocationPlan.interactionMode,
            includesCurrentFileContext: invocationPlan.includesCurrentFileContext
        )
        let userMessage = ChatMessage.content(
            ChatMessageContent(
                id: UUID().uuidString,
                role: .user,
                content: prompt,
                files: files
            )
        )

        let snapshot = try await llmState.debugChatContext(
            to: conversationID,
            model: model,
            message: userMessage,
            filePreparationMode: .activeContextOnly
        )

        return try Self.formatDebugChatContextSnapshot(
            snapshot,
            invocationPlan: invocationPlan,
            attachmentCount: files.count
        )
    }

    private static func formatDebugChatContextSnapshot(
        _ snapshot: DebugChatContextSnapshot,
        invocationPlan: AIChatInvocationPlan,
        attachmentCount: Int
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(snapshot)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return """
        // LLMKit debugChatContext snapshot
        // filePreparationMode: \(snapshot.filePreparationMode.rawValue)
        // interactionMode: \(invocationPlan.interactionMode.rawValue)
        // canvasTarget: \(invocationPlan.toolCanvasTarget.rawValue)
        // includesCurrentFileContext: \(invocationPlan.includesCurrentFileContext)
        // attachments: \(attachmentCount)

        \(json)
        """
    }
}

private enum DebugChatContextError: LocalizedError {
    case noConversation

    var errorDescription: String? {
        switch self {
        case .noConversation:
            String(localizable: .debugChatContextNoConversationError)
        }
    }
}
#endif
