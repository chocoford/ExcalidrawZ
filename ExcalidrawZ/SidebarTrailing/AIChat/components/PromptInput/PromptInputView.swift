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

#if os(iOS)
import PhotosUI
#endif

struct ExcalidrawChatInvocationContext: ChatInvocationContext, Sendable {
    var currentFileData: Data?
    var canvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    var readCanvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget? = nil
    var selectedElementIDs: [String]? = nil
    var currentFileID: UUID? = nil
    var hasActiveFile: Bool = false
    var currentModelSupportsImageInput: Bool = true
    var isCurrentFileContextProtected: Bool = false
    var imageAttachments: [AIChatImageAttachmentReference] = []
}

struct AIChatInvocationPlan: Sendable {
    let interactionMode: AIChatInteractionMode
    let userCanvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    let toolCanvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    let readCanvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget
    let includesCurrentFileContext: Bool
    let hasActiveFile: Bool
    let selectedElementIDs: [String]?
    let currentFileID: UUID?

    var requiresFreshToolCanvas: Bool {
        toolCanvasTarget.targetsProposalCanvas
    }

    var usesMutationSession: Bool {
        interactionMode.usesMutationSession
    }

    var selectedElementCount: Int {
        includesCurrentFileContext ? selectedElementIDs?.count ?? 0 : 0
    }

    var isCurrentFileContextProtected: Bool {
        hasActiveFile && !includesCurrentFileContext
    }

    @MainActor
    static func make(
        fileState: FileState,
        preferredInteractionMode: AIChatInteractionMode,
        includesCurrentFileContext: Bool
    ) -> Self {
        ExcalidrawCoordinatorRegistry.shared.update(
            normal: fileState.excalidrawWebCoordinator,
            collaboration: fileState.excalidrawCollaborationWebCoordinator
        )

        let activeFile = fileState.currentActiveFile
        let userCanvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = {
            switch activeFile {
                case .collaborationFile:
                    .collaboration
                default:
                    .normal
            }
        }()
        let interactionMode: AIChatInteractionMode = includesCurrentFileContext
            ? preferredInteractionMode
            : .ask
        let toolCanvasTarget: ExcalidrawCoordinatorRegistry.CanvasTarget = interactionMode == .ask
            ? .proposal
            : userCanvasTarget
        let coordinator: ExcalidrawCanvasView.Coordinator? = switch userCanvasTarget {
            case .normal:
                fileState.excalidrawWebCoordinator
            case .collaboration:
                fileState.excalidrawCollaborationWebCoordinator
            case .proposal:
                nil
        }
        let ids = coordinator?.selectedElementIDs ?? []
        let currentFileID: UUID? = {
            if case .file(let file) = activeFile {
                return file.id
            }
            return nil
        }()

        return AIChatInvocationPlan(
            interactionMode: interactionMode,
            userCanvasTarget: userCanvasTarget,
            toolCanvasTarget: toolCanvasTarget,
            readCanvasTarget: userCanvasTarget,
            includesCurrentFileContext: includesCurrentFileContext,
            hasActiveFile: activeFile != nil,
            selectedElementIDs: ids.isEmpty ? nil : ids,
            currentFileID: currentFileID
        )
    }

    @MainActor
    func makeContext(
        fileState: FileState,
        model: SupportedModel,
        supportsImageInput: Bool? = nil,
        imageAttachments: [AIChatImageAttachmentReference] = []
    ) async throws -> ExcalidrawChatInvocationContext {
        if requiresFreshToolCanvas {
            await AIProposalSandbox.resetCanvasIfAvailable()
        }

        let currentFileData: Data? = if includesCurrentFileContext {
            try await CurrentExcalidrawDataResolver.resolve(
                fileState: fileState,
                canvasTarget: userCanvasTarget
            )
        } else {
            nil
        }

        return ExcalidrawChatInvocationContext(
            currentFileData: currentFileData,
            canvasTarget: toolCanvasTarget,
            readCanvasTarget: readCanvasTarget,
            selectedElementIDs: includesCurrentFileContext ? selectedElementIDs : nil,
            currentFileID: includesCurrentFileContext ? currentFileID : nil,
            hasActiveFile: hasActiveFile,
            currentModelSupportsImageInput: supportsImageInput ?? model.supportsExcalidrawImageInput,
            isCurrentFileContextProtected: isCurrentFileContextProtected,
            imageAttachments: imageAttachments
        )
    }
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
    @EnvironmentObject var lockedContentState: LockedContentStateStore
    @Environment(\.alertToast) var alertToast

    @Binding var conversationID: String?
    /// Pending-send queue, owned by the host so they can render the
    /// `PendingQueueView` wherever (and however) they want — inspector
    /// vs island place it differently. PromptInputView appends here when
    /// the user sends mid-stream, drains here when an in-flight reply
    /// finishes, and clears here on stop.
    @Binding var pendingQueue: [PendingQueueMessage]
    let style: PromptInputStyle<Background>
    let focusOnAppear: Bool
    let showsCompactIOSFullChatButton: Bool
    let dismissKeyboardOnSuccessfulSubmit: Bool
    let onSuccessfulSubmit: (() -> Void)?
    let header: Header

    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>,
        style: PromptInputStyle<Background>,
        focusOnAppear: Bool = false,
        showsCompactIOSFullChatButton: Bool = true,
        dismissKeyboardOnSuccessfulSubmit: Bool = false,
        onSuccessfulSubmit: (() -> Void)? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self._conversationID = conversationID
        self._pendingQueue = pendingQueue
        self.style = style
        self.focusOnAppear = focusOnAppear
        self.showsCompactIOSFullChatButton = showsCompactIOSFullChatButton
        self.dismissKeyboardOnSuccessfulSubmit = dismissKeyboardOnSuccessfulSubmit
        self.onSuccessfulSubmit = onSuccessfulSubmit
        self.header = header()
    }

    /// Drives the system image-picker sheet from the attachment menu.
    /// Selected files are resolved here, then appended to the draft owner
    /// through `AIChatState` so the parent view does not subscribe to
    /// high-frequency draft text/image changes.
    @State var isImagePickerPresented: Bool = false
    @State var agentConfig: DomainAgentConfigResponse?

    /// User's model-tier pick made *before* a conversation has been created
    /// (i.e., a fresh chat). Promoted to a per-conversation override in
    /// `AIChatPreferences` the moment `startSend` mints a conversation id.
    /// Once the conversation exists, the picker writes straight to prefs.
    @State var pendingTierSelection: ExcalidrawModelTier?

    /// Global default + per-conversation tier overrides, persisted across
    /// launches. Drives the active model profile and reflected back from picker
    /// taps / Settings changes.
    @ObservedObject var prefs = AIChatPreferences.shared

    /// In-flight send task. While non-nil, the assistant is generating a reply.
    /// Cancelling this task propagates Swift cooperative cancellation through
    /// `llmState.sendMessage`'s stream consumer, which terminates the request.
    @State var currentTask: Task<Void, Never>?
    @State var compactTask: Task<Void, Never>?
    @State var draftHasContent: Bool = false
    @State var draftHasImages: Bool = false
    @State var draftSendRequestToken: Int = 0
    @State var compactIOSFloatingDraftFieldHeight: CGFloat = 0
    @State var compactIOSFloatingTextAreaIsSingleLine: Bool = true
    @State var compactIOSFloatingTextAreaIsOverflowing: Bool = false
    @State var isCompactIOSFloatingFullscreenInputPresented: Bool = false
#if os(iOS)
    @EnvironmentObject var layoutState: LayoutState
    @State var iOSSelectedPhotoPickerItems: [PhotosPickerItem] = []
    @State var isIOSPhotoLibraryPickerPresented: Bool = false
    @State var isIOSCameraPickerPresented: Bool = false
#endif
    @Namespace var compactIOSFloatingInputNamespace
#if DEBUG
    @State var debugContextText: String = ""
    @State var debugContextError: String = ""
    @State var isDebugContextPresented: Bool = false
    @State var isGeneratingDebugContext: Bool = false
#endif

    @FocusState var isInputFocused: Bool

    /// Server-side agent identifier; the backend resolves system prompt + agent
    /// config from this. Tools list still ships from the client because tool
    /// implementations are local. Pulled from `ExcalidrawAgentConfig` so this
    /// view, the persistence layer's restore path, and any future agent
    /// callers can't drift apart.
    var agentID: String { ExcalidrawAgentConfig.agentID }

    @MainActor
    var activeFileAccessAllowsAI: Bool {
        prefs.effectiveAllowsFileAccess(
            for: fileState.currentActiveFile,
            lockState: lockedContentState.activeFileLockState
        )
    }

    @MainActor
    var hasActiveFileForAIAccessControl: Bool {
        fileState.currentActiveFile != nil
    }

    @MainActor
    var canToggleAIFileAccess: Bool {
        lockedContentState.activeFileLockState == .plaintext
    }

    @MainActor
    func activeFileAllowsAIContext() async -> Bool {
        guard let activeFile = fileState.currentActiveFile else { return false }
        guard prefs.allowsFileAccess(for: activeFile) else { return false }
        return await LockedContentAIGuard.canAIRead(activeFile: activeFile)
    }

    /// Resolved model used for the next request, in priority order:
    ///   1. Per-conversation override stored in `AIChatPreferences`
    ///   2. Pending pick made before a conversation exists
    ///   3. User's global default (Settings → AI)
    /// Picker writes directly into either (1) or (2); (3) is mutated
    /// from Settings only.
    @MainActor
    var activeModelProfileOption: ExcalidrawModelProfileOption? {
        fallbackModelOptionIfNeeded(selectedTierBeforeFallback)
    }

    @MainActor
    var activeModelContextWindowTokens: Int? {
        activeModelProfileOption?.maxContextTokens
    }

    @MainActor
    var availableModelOptions: [ExcalidrawModelProfileOption] {
        agentConfig?.excalidrawModelOptions ?? []
    }

    @MainActor
    func canSelectModelOption(_ option: ExcalidrawModelProfileOption) -> Bool {
        canSelectModelOption(option, requiresImageInput: requiresImageInputModel)
    }

    @MainActor
    func canSelectModelOption(
        _ option: ExcalidrawModelProfileOption,
        requiresImageInput: Bool
    ) -> Bool {
        canShowModelOption(option, requiresImageInput: requiresImageInput)
            && canUsePlan(for: option)
    }

    @MainActor
    func canShowModelOption(
        _ option: ExcalidrawModelProfileOption,
        requiresImageInput: Bool
    ) -> Bool {
        option.isVisible
            && (!requiresImageInput || option.supportsImageInput)
    }

    @MainActor
    func canUsePlan(for option: ExcalidrawModelProfileOption) -> Bool {
        !option.requiresMaxAIPlan || store.canUseExtraHighAIModel
    }

    @MainActor
    func modelOption(for tier: ExcalidrawModelTier) -> ExcalidrawModelProfileOption? {
        availableModelOptions.first(where: { $0.profileID == tier.rawValue })
    }

    @MainActor
    func fallbackModelOptionIfNeeded(_ tier: ExcalidrawModelTier) -> ExcalidrawModelProfileOption? {
        fallbackModelOptionIfNeeded(tier, requiresImageInput: requiresImageInputModel)
    }

    @MainActor
    func fallbackModelOptionIfNeeded(
        _ tier: ExcalidrawModelTier,
        requiresImageInput: Bool
    ) -> ExcalidrawModelProfileOption? {
        if let preferred = modelOption(for: tier),
           canSelectModelOption(preferred, requiresImageInput: requiresImageInput) {
            return preferred
        }

        return AIChatRenderDebug.measure("prompt.fallbackModel.candidates") {
            availableModelOptions.filter {
                canSelectModelOption($0, requiresImageInput: requiresImageInput)
            }.first
        }
    }

    @MainActor
    func modelProfileOptionForSend(files: [ChatMessageContent.File]) -> ExcalidrawModelProfileOption? {
        fallbackModelOptionIfNeeded(
            selectedTierBeforeFallback,
            requiresImageInput: requiresImageInputModel || files.containsImageInput
        )
    }

    @MainActor
    var selectedTierBeforeFallback: ExcalidrawModelTier {
        prefs.tier(for: conversationID)
            ?? pendingTierSelection
            ?? prefs.defaultTier
    }

    @MainActor
    @discardableResult
    func upgradeModelForImageInputIfNeeded() -> Bool {
        guard canInsertImages else { return false }

        let selectedTier = selectedTierBeforeFallback
        guard let selectedOption = modelOption(for: selectedTier) else { return true }
        guard !selectedOption.supportsImageInput else { return true }

        guard let upgradedOption = fallbackModelOptionIfNeeded(selectedTier, requiresImageInput: true) else {
            return false
        }
        guard upgradedOption.supportsImageInput else { return false }
        let upgradedTier = upgradedOption.tier

        if let id = conversationID {
            prefs.setTier(upgradedTier, for: id)
        } else {
            pendingTierSelection = upgradedTier
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
            agentConfig.excalidrawModelOptions.contains {
                $0.isVisible
                    && canUsePlan(for: $0)
                    && $0.supportsImageInput
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

    /// True when this view's conversation is currently being compacted.
    /// Derived from the app-scoped `AIChatState.compactingConversationIDs`
    /// set rather than a local @State so `AIChatView` can render the
    /// "compacting…" indicator off the same publisher — a single
    /// PromptInputView can't reach the chat list above it.
    var isCompactingContext: Bool {
        aiChatState.isCompacting(conversationID: conversationID)
    }

    var promptDraftKey: String {
        aiChatState.promptDraftKey(
            conversationID: conversationID,
            fileScope: fileState.currentActiveFile?.aiConversationFileScope
        )
    }

    var promptDraftState: AIChatPromptDraftState {
        aiChatState.promptDraftState(forKey: promptDraftKey)
    }

    var usesCompactIOSFloatingInput: Bool {
#if os(iOS)
        style.layout == .compactIOS
#else
        false
#endif
    }

    var body: some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.body")

        bodyContent
        .task {
            if focusOnAppear {
                await Task.yield()
                await MainActor.run {
                    isInputFocused = true
                }
            }
            await loadAgentConfigIfNeeded()
        }
        .watch(value: prefs.isAIEnabled) { isEnabled in
            guard !isEnabled else { return }
            cancelCurrentGeneration()
        }
#if os(iOS)
        .watch(value: isInputFocused) { _, isFocused in
            handleCompactIOSInputFocusChanged(isFocused)
        }
#endif
#if DEBUG
        .sheet(isPresented: $isDebugContextPresented) {
            debugChatContextSheet
        }
#endif
    }

    @ViewBuilder
    private var bodyContent: some View {
#if os(iOS)
        if usesCompactIOSFloatingInput {
            compactIOSFloatingInputContent
        } else {
            regularBodyContent
        }
#else
        regularBodyContent
#endif
    }

#if os(iOS)
    @MainActor
    private func handleCompactIOSInputFocusChanged(_ isFocused: Bool) {
        guard usesCompactIOSFloatingInput else { return }
        guard !isFocused else { return }
        guard layoutState.isCompactAIChatToolbarPresented,
              layoutState.isCompactAIChatInputEditing,
              !layoutState.isCompactAIChatAttachmentPickerPresented
        else {
            return
        }
        layoutState.exitCompactAIChatInputEditing()
    }
#endif

    @ViewBuilder
    private var regularBodyContent: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                content()
            } else {
                content()
                    .padding(8)
            }
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

    @ViewBuilder
    private func content() -> some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.content")

        VStack(spacing: 6) {
            if AIChatRenderDebug.useMinimalPromptInput {
                debugMinimalInputBox
            } else {
                inputBox
            }

            if !AIChatRenderDebug.useMinimalPromptInput,
               !AIChatRenderDebug.hidePromptActionBar {
                HStack {
#if os(macOS)
                    if #available(macOS 14.0, *) {
                        actionBarLeading()
//                            .buttonBorderShape(.roundedRectangle(radius: 6))
                            .buttonStyle(.accessoryBar)
                    } else {
                        actionBarLeading()
                            .buttonStyle(.plain)
                    }
#else
                    actionBarLeading()
                        .buttonStyle(.plain)
#endif

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
        style: PromptInputStyle<Background>,
        focusOnAppear: Bool = false,
        showsCompactIOSFullChatButton: Bool = true,
        dismissKeyboardOnSuccessfulSubmit: Bool = false,
        onSuccessfulSubmit: (() -> Void)? = nil
    ) {
        self.init(
            conversationID: conversationID,
            pendingQueue: pendingQueue,
            style: style,
            focusOnAppear: focusOnAppear,
            showsCompactIOSFullChatButton: showsCompactIOSFullChatButton,
            dismissKeyboardOnSuccessfulSubmit: dismissKeyboardOnSuccessfulSubmit,
            onSuccessfulSubmit: onSuccessfulSubmit,
            header: { EmptyView() }
        )
    }
}

extension PromptInputView where Background == PlatformDefaultPromptBackground, Header == EmptyView {
    /// Style-less convenience init — picks `.regular` so existing call
    /// sites keep working without forcing the caller to think about
    /// `Background` at all.
    init(
        conversationID: Binding<String?>,
        pendingQueue: Binding<[PendingQueueMessage]>
    ) {
        self.init(
            conversationID: conversationID,
            pendingQueue: pendingQueue,
            style: .regular
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
        style: PromptInputStyle<PlatformDefaultPromptBackground> = .regular,
        showsCompactIOSFullChatButton: Bool = true,
        onSuccessfulSubmit: (() -> Void)? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.init(
            conversationID: conversationID,
            pendingQueue: pendingQueue,
            style: style,
            focusOnAppear: false,
            showsCompactIOSFullChatButton: showsCompactIOSFullChatButton,
            onSuccessfulSubmit: onSuccessfulSubmit,
            header: header
        )
    }
}
