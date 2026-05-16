//
//  PromptInputView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/10/26.
//
//  The prompt block at the bottom of every chat surface (inspector +
//  island). Owns input text + paste / pasted images, the send Task,
//  and the current model pick. The implementation is split across
//  files; this one keeps the struct definition, state, and
//  composition (`body` / `content`):
//
//   - `PromptInputStyle.swift` — visual presets + backdrop sentinel
//   - `PromptInputView+ActionBar.swift` — bottom controls (paperclip,
//     ring, model picker, send/stop button)
//   - `PromptInputView+InputField.swift` — TextArea + paste plumbing
//   - `PromptInputView+Send.swift` — sendMessage / startSend / compact /
//     queue drainer / auto-compact threshold check
//
//  All extensions reach into the struct's state directly — that's why
//  most stored properties below aren't `private` (Swift's `private`
//  doesn't reach extensions in other files). They stay file-internal
//  via the module boundary instead.
//

import SwiftUI
import UniformTypeIdentifiers

import ChocofordUI
import LLMKit
import LLMCore

struct ExcalidrawChatInvocationContext: ChatInvocationContext {
    var currentFileData: Data?
    var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    var selectedElementIDs: [String]? = nil
    var currentFileID: UUID? = nil
    var currentModelSupportsImageInput: Bool = true
}

struct AIChatInputCapabilityError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    
    static var noModelCanReadImages: Self {
        AIChatInputCapabilityError(
            message: String(
                localizable: .aiChatErrorNoModelCanReadImages
            )
        )
    }
}

struct PromptInputView<Background: View, Header: View>: View {
    @EnvironmentObject var llmState: LLMStateObject
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var aiChatState: AIChatState
    @EnvironmentObject var store: Store
    @Environment(\.alertToast) var alertToast

    @Binding var conversationID: String?
    /// Pending-send queue, owned by the host so they can render the
    /// `PendingQueueView` wherever (and however) they want — inspector
    /// vs island place it differently. PromptInputView appends here when
    /// the user sends mid-stream, drains here when an in-flight reply
    /// finishes, and clears here on stop.
    @Binding var pendingQueue: [PendingQueueMessage]
    let style: PromptInputStyle<Background>
    let header: Header

    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>,
        style: PromptInputStyle<Background>,
        @ViewBuilder header: () -> Header
    ) {
        self._conversationID = conversationID
        self._pendingQueue = pendingQueue
        self.style = style
        self.header = header()
    }

    /// Drives the system image-picker sheet from the attachment menu.
    /// Selected files are resolved here, then appended to the draft owner
    /// through `AIChatState` so the parent view does not subscribe to
    /// high-frequency draft text/image changes.
    @State var isImagePickerPresented: Bool = false
    @State var agentConfig: DomainAgentConfigResponse?

    /// User's model pick made *before* a conversation has been created
    /// (i.e., a fresh chat). Promoted to a per-conversation override in
    /// `AIChatPreferences` the moment `startSend` mints a conversation id.
    /// Once the conversation exists, the picker writes straight to prefs.
    @State var pendingModelSelection: SupportedModel?

    /// Global default + per-conversation overrides, persisted across
    /// launches. Drives `activeModel` and reflected back from picker
    /// taps / Settings changes.
    @ObservedObject var prefs = AIChatPreferences.shared

    /// In-flight send task. While non-nil, the assistant is generating a reply.
    /// Cancelling this task propagates Swift cooperative cancellation through
    /// `llmState.sendMessage`'s stream consumer, which terminates the request.
    @State var currentTask: Task<Void, Never>?
    /// Draft text/images are stored in a reference object, but this parent
    /// keeps it as plain `@State` so object publishes do not invalidate the
    /// whole prompt view. Only `PromptDraftInputField` observes it.
    @State var promptDraftState = AIChatPromptDraftState()
    @State var draftHasContent: Bool = false
    @State var draftHasImages: Bool = false
    @State var draftSendRequestToken: Int = 0

    @FocusState var isInputFocused: Bool

    /// Server-side agent identifier; the backend resolves system prompt + agent
    /// config from this. Tools list still ships from the client because tool
    /// implementations are local. Pulled from `ExcalidrawAgentConfig` so this
    /// view, the persistence layer's restore path, and any future agent
    /// callers can't drift apart.
    var agentID: String { ExcalidrawAgentConfig.agentID }

    /// Resolved model used for the next request, in priority order:
    ///   1. Per-conversation override stored in `AIChatPreferences`
    ///   2. Pending pick made before a conversation exists
    ///   3. User's global default (Settings → AI)
    /// Picker writes directly into either (1) or (2); (3) is mutated
    /// from Settings only.
    @MainActor
    var activeModel: SupportedModel {
        AIChatRenderDebug.measure("prompt.activeModel") {
            fallbackModelIfNeeded(selectedModelBeforeFallback)
        }
    }

    @MainActor
    func canSelectModel(_ model: SupportedModel) -> Bool {
        canSelectModel(model, requiresImageInput: requiresImageInputModel)
    }

    @MainActor
    func canSelectModel(_ model: SupportedModel, requiresImageInput: Bool) -> Bool {
        model.isVisibleInExcalidrawModelPicker
            && (agentConfig?.allowedModels.contains(model) ?? true)
            && canUsePlan(for: model)
            && (!requiresImageInput || model.supportsExcalidrawImageInput)
    }

    @MainActor
    func canUsePlan(for model: SupportedModel) -> Bool {
        !model.requiresMaxAIPlan || store.canUseExtraHighAIModel
    }

    @MainActor
    func fallbackModelIfNeeded(_ model: SupportedModel) -> SupportedModel {
        fallbackModelIfNeeded(model, requiresImageInput: requiresImageInputModel)
    }

    @MainActor
    func fallbackModelIfNeeded(
        _ model: SupportedModel,
        requiresImageInput: Bool
    ) -> SupportedModel {
        guard !canSelectModel(model, requiresImageInput: requiresImageInput) else { return model }

        let candidates = AIChatRenderDebug.measure("prompt.fallbackModel.candidates") {
            let availableModels = agentConfig?.allowedModels ?? []
            return availableModels.filter {
                canSelectModel($0, requiresImageInput: requiresImageInput)
            }
        }
        return SupportedModel.nearestExcalidrawFallback(to: model, from: candidates)
            ?? .claudeSonnet4_6
    }

    @MainActor
    func modelForSend(files: [ChatMessageContent.File]) -> SupportedModel {
        return fallbackModelIfNeeded(
            selectedModelBeforeFallback,
            requiresImageInput: requiresImageInputModel || files.containsImageInput
        )
    }

    @MainActor
    var selectedModelBeforeFallback: SupportedModel {
        prefs.model(for: conversationID)
            ?? pendingModelSelection
            ?? prefs.defaultModel
    }

    @MainActor
    @discardableResult
    func upgradeModelForImageInputIfNeeded() -> Bool {
        guard canInsertImages else { return false }
        let selectedModel = selectedModelBeforeFallback
        guard !selectedModel.supportsExcalidrawImageInput else { return true }

        let upgradedModel = fallbackModelIfNeeded(selectedModel, requiresImageInput: true)
        guard upgradedModel.supportsExcalidrawImageInput else { return false }

        if let id = conversationID {
            prefs.setModel(upgradedModel, for: id)
        } else {
            pendingModelSelection = upgradedModel
        }
        return true
    }

    @MainActor
    var requiresImageInputModel: Bool {
        AIChatRenderDebug.measure("prompt.requiresImageInputModel") {
            draftHasImages
                || pendingQueue.contains(where: { $0.files.containsImageInput })
                || conversationContainsImageInput
        }
    }

    @MainActor
    var canInsertImages: Bool {
        guard let agentConfig else { return true }
        return AIChatRenderDebug.measure("prompt.canInsertImages") {
            agentConfig.allowedModels.contains {
                $0.isVisibleInExcalidrawModelPicker
                    && canUsePlan(for: $0)
                    && $0.supportsExcalidrawImageInput
            }
        }
    }

    @MainActor
    var conversationContainsImageInput: Bool {
        AIChatRenderDebug.measure("prompt.conversationContainsImageInput") {
            conversation?.messages.contains { message in
                message.files?.containsImageInput == true
            } ?? false
        }
    }

    var conversation: Conversation? {
        guard let conversationID else { return nil }
        return AIChatRenderDebug.measure("prompt.getConversation") {
            llmState.getConversation(by: conversationID)
        }
    }

    var currentFileData: Data? {
        get async throws {
            let canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = {
                switch fileState.currentActiveFile {
                    case .collaborationFile:
                        .collaboration
                    default:
                        .normal
                }
            }()
            return try await CurrentExcalidrawDataResolver.resolve(
                fileState: fileState,
                canvasTarget: canvasTarget
            )
        }
    }

    /// True when this view's conversation is currently being compacted.
    /// Derived from the app-scoped `AIChatState.compactingConversationIDs`
    /// set rather than a local @State so `AIChatView` can render the
    /// "compacting…" indicator off the same publisher — a single
    /// PromptInputView can't reach the chat list above it.
    var isCompactingContext: Bool {
        aiChatState.isCompacting(conversationID: conversationID)
    }

    var body: some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.body")

        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                content()
            } else {
                content()
                    .padding(8)
            }
        }
        .task {
            await loadAgentConfigIfNeeded()
        }
    }

    @MainActor
    func updateDraftSummary(hasContent: Bool, hasImages: Bool) {
        if draftHasContent != hasContent {
            draftHasContent = hasContent
        }
        if draftHasImages != hasImages {
            draftHasImages = hasImages
        }
    }

    @MainActor @ViewBuilder
    private func content() -> some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.content")

        VStack(spacing: 6) {
            if AIChatRenderDebug.useMinimalPromptInput {
                debugMinimalInputBox
            } else if style.showsLowCreditsBanner {
                VStack(spacing: 0) {
                    LowCreditsBannerView(peekBottom: 18)
                        .padding(.horizontal, 10)
                        .font(.caption)
                        .offset(y: 18)

                    inputBox
                }
            } else {
                inputBox
            }

            if !AIChatRenderDebug.useMinimalPromptInput,
               !AIChatRenderDebug.hidePromptActionBar {
                HStack {
                    if #available(macOS 14.0, iOS 17.0, *) {
                        actionBarLeading()
                            .buttonBorderShape(.roundedRectangle(radius: 6))
                            .buttonStyle(.accessoryBar)
                    } else {
                        actionBarLeading()
                            .buttonStyle(.plain)
                    }

                    Spacer()

                    primaryActionButton()
                }
                .controlSize(.large)
            }
        }
    }
}

// MARK: - Default-style convenience

extension PromptInputView where Header == EmptyView {
    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>,
        style: PromptInputStyle<Background>
    ) {
        self.init(
            conversationID: conversationID,
            pendingQueue: pendingQueue,
            style: style,
            header: { EmptyView() }
        )
    }
}

extension PromptInputView where Background == PlatformDefaultPromptBackground, Header == EmptyView {
    /// Style-less convenience init — picks `.inspector` so existing call
    /// sites keep working without forcing the caller to think about
    /// `Background` at all.
    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>
    ) {
        self.init(
            conversationID: conversationID,
            pendingQueue: pendingQueue,
            style: .inspector
        )
    }
}
extension PromptInputView where Background == PlatformDefaultPromptBackground {
    /// Style-less convenience init with a header slot. Used by the inspector
    /// to attach contextual chrome (edit/revert state) to the prompt block
    /// without making PromptInputView own that chat-level state.
    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>,
        @ViewBuilder header: () -> Header
    ) {
        self.init(
            conversationID: conversationID,
            pendingQueue: pendingQueue,
            style: .inspector,
            header: header
        )
    }
}
