//
//  PromptInputView+ActionBar.swift
//  ExcalidrawZ
//
//  Bottom controls of the prompt input: attachment menu (paperclip),
//  context-usage ring, model picker, and the primary send/stop button.
//  Extracted from `PromptInputView` so the main file stays focused on
//  composition + state and isn't dominated by control glue.
//
//  Everything here is an `extension` of `PromptInputView` and uses its
//  private state directly (`isImagePickerPresented`, `agentConfig`,
//  `pendingTierSelection`, etc.) — no parameters threaded through, just
//  the same scope split across files.
//

import SwiftUI
import ChocofordUI
import LLMKit
import LLMCore
import SFSafeSymbols

extension PromptInputView {
    private var actionBarIconFrameLength: CGFloat { 18 }
    private var actionBarLeadingControlSpacing: CGFloat { 4 }
    private var primaryActionButtonSize: ModernButtonStyleModifier.Size? {
#if os(iOS)
        .regular
#else
        nil
#endif
    }

    /// Left half of the action row: attachment menu, context-usage ring,
    /// model picker. Wrapped in an HStack so the whole group can take a
    /// shared `buttonStyle` from the caller (`.accessoryBar` on macOS 14+,
    /// `.plain` below).
    @ViewBuilder
    func actionBarLeading() -> some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.actionBarLeading")

        HStack(spacing: actionBarLeadingControlSpacing) {
            attachmentMenu

            ContextUsageRing(
                maxContextTokens: activeModelContextWindowTokens,
                onTap: conversationID != nil && !isCompactingContext
                    ? { compactCurrentContext() }
                    : nil,
                usedTokens: activeConversationEstimatedTokenUsage
            )

            fileAccessToggleButton

            modelPicker

#if DEBUG
            debugChatContextButton
#endif
        }
    }

    @ViewBuilder
    var fileAccessToggleButton: some View {
        Button {
            toggleAIFileAccess()
        } label: {
            if #available(macOS 14.0, *) {
                Image(systemSymbol: activeFileAccessAllowsAI ? .eye : .eyeSlash)
                    .font(.caption)
                    .frame(width: actionBarIconFrameLength, height: actionBarIconFrameLength)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: activeFileAccessAllowsAI ? .eye : .eyeSlash)
                    .font(.caption)
                    .frame(width: actionBarIconFrameLength, height: actionBarIconFrameLength)
            }
        }
        .promptActionBarHoverEffect()
        .foregroundStyle(activeFileAccessAllowsAI ? .primary : .secondary)
        .tint(activeFileAccessAllowsAI ? .accentColor : .secondary.opacity(0.75))
        .disabled(!hasActiveFileForAIAccessControl || !canToggleAIFileAccess)
        .help(fileAccessHelpText)
        .accessibilityLabel(Text(localizable: .aiChatButtonAIVisibility))
        .accessibilityValue(Text(fileAccessHelpText))
        .modifier(FeatureDiscoveryTipModifier(
            kind: .aiFileVisibility,
            isEnabled: hasActiveFileForAIAccessControl && canToggleAIFileAccess
        ))
    }

    @MainActor
    func toggleAIFileAccess() {
        guard hasActiveFileForAIAccessControl, canToggleAIFileAccess else { return }
        prefs.setAllowsFileAccess(
            !activeFileAccessAllowsAI,
            for: fileState.currentActiveFile
        )
    }

    @MainActor
    var fileAccessHelpText: String {
        guard hasActiveFileForAIAccessControl else {
            return String(localizable: .aiChatFileAccessHelpNoActiveFile)
        }

        guard canToggleAIFileAccess else {
            return String(localizable: .aiChatFileAccessHelpLockedFile)
        }

        if activeFileAccessAllowsAI {
            return String(localizable: .aiChatFileAccessHelpAccessAllowed)
        } else {
            return String(localizable: .aiChatFileAccessHelpAccessDenied)
        }
    }

    @MainActor
    private var activeConversationEstimatedTokenUsage: Int? {
        guard let conversationID else { return nil }
        return llmState.estimatedTokenUsage(in: conversationID)
    }

    /// Bottom-left attachment menu. Currently has only "Image" — clicking
    /// it opens the system file picker constrained to `UTType.image`,
    /// then appends accepted images to the prompt draft owner. Future
    /// entries (file uploads, canvas snapshots, etc.) drop in here as
    /// additional `Button`s.
    /// We deliberately don't use the `primaryAction:` closure form —
    /// the icon doesn't have a single "default" action; tapping it
    /// just opens the menu.
    @ViewBuilder
    var attachmentMenu: some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.attachmentMenu")

#if os(iOS)
        AIChatAttachmentMenu(
            canInsertImages: canInsertImages,
            isFileImporterPresented: $isImagePickerPresented,
            selectedPhotoPickerItems: $iOSSelectedPhotoPickerItems,
            isPhotoLibraryPickerPresented: $isIOSPhotoLibraryPickerPresented,
            isCameraPickerPresented: $isIOSCameraPickerPresented,
            onImagesPicked: appendAttachmentImages,
            onImageInputUnavailable: showImageInputUnavailableToast
        ) {
            Image(systemSymbol: .paperclip)
                .font(.caption)
                .frame(width: actionBarIconFrameLength, height: actionBarIconFrameLength)
        }
        .promptActionBarHoverEffect()

#else
        AIChatAttachmentMenu(
            canInsertImages: canInsertImages,
            isFileImporterPresented: $isImagePickerPresented,
            onImagesPicked: appendAttachmentImages,
            onImageInputUnavailable: showImageInputUnavailableToast
        ) {
            Image(systemSymbol: .paperclip)
                .font(.caption)
                .frame(width: actionBarIconFrameLength, height: actionBarIconFrameLength)
        }
        .promptActionBarHoverEffect()

#endif
    }

    @MainActor
    func appendAttachmentImages(_ images: [PendingPastedImage]) {
        guard !images.isEmpty else { return }
        guard canInsertImages, upgradeModelForImageInputIfNeeded() else {
            showImageInputUnavailableToast()
            return
        }
        aiChatState.requestAppendDraftImages(images, draftKey: promptDraftKey)
    }

    @MainActor
    func showImageInputUnavailableToast() {
        alertToast(AIChatInputCapabilityError.noModelCanReadImages)
    }

    @ViewBuilder
    var modelPicker: some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.modelPicker")

        // Agent config hasn't loaded → show a quiet placeholder. Loading is fast
        // (one HTTP round-trip on first appearance) so a permanent skeleton would
        // be visual noise; we just render the active model name disabled.
        Menu {
            modelTierPickerButtons()
        } label: {
            HStack(spacing: 4) {
                Text(modelPickerTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: actionBarIconFrameLength)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .promptActionBarHoverEffect()
        .disabled(modelPickerTiers.isEmpty)
    }

    @MainActor
    var modelPickerTitle: String {
        activeModelProfileOption?.title ?? "..."
    }

    @MainActor
    var modelPickerTiers: [ExcalidrawModelTier] {
        guard agentConfig != nil else { return [] }
        let options = AIChatRenderDebug.measure("prompt.modelPicker.options") {
            availableModelOptions.filter {
                canShowModelOption($0, requiresImageInput: requiresImageInputModel)
            }
        }
        return ExcalidrawModelTier.pickerOrder.filter { tier in
            options.contains { $0.tier == tier }
        }
    }

    @MainActor
    var activeTierForModelPicker: ExcalidrawModelTier {
        activeModelProfileOption?.tier ?? selectedTierBeforeFallback
    }

    @MainActor
    @ViewBuilder
    func modelTierPickerButtons() -> some View {
        ForEach(modelPickerTiers) { tier in
            Button {
                pickTier(tier)
            } label: {
                if tier == activeTierForModelPicker {
                    Label(tier.name, systemSymbol: .checkmark)
                } else {
                    Text(tier.name)
                }
            }
            .disabled(!canSelectTier(tier))
        }
    }

    /// Route a tier pick to the right place: existing conversations get a
    /// stored override (so reopening that thread restores the pick); fresh
    /// chats just stage it in `pendingTierSelection` and get committed
    /// when `startSend` mints the conversation id.
    @MainActor
    func pickTier(_ tier: ExcalidrawModelTier) {
        guard canSelectTier(tier) else { return }

        if let id = conversationID {
            prefs.setTier(tier, for: id)
        } else {
            pendingTierSelection = tier
        }
    }

    @MainActor
    func canSelectTier(_ tier: ExcalidrawModelTier) -> Bool {
        availableModelOptions.contains { option in
            option.tier == tier && canSelectModelOption(option)
        }
    }

    func loadAgentConfigIfNeeded() async {
        guard AIChatAvailability.canUseAI else { return }
        guard agentConfig == nil else { return }
        do {
            let config = try await LLMClient.shared.getDomainAgentConfig(agentID: agentID)
            await MainActor.run {
                self.agentConfig = config
            }
        } catch is CancellationError {
        } catch {
            alertToast(
                .init(
                    displayMode: .hud,
                    type: .error(.red),
                    title: String(
                        localizable: .aiChatErrorLoadAgentConfigFailed(
                            error.localizedDescription
                        )
                    ),
                )
            )
        }
    }

    // MARK: - Primary action button

    /// True when the assistant is currently generating. Drives the icon swap
    /// (arrow ↔ stop) and gates whether `sendMessage` enqueues vs sends now.
    var isGenerating: Bool {
        currentTask != nil || isConversationStreaming
    }

    private var isConversationStreaming: Bool {
        guard let conversationID else { return false }
        return llmState.isRunning(conversationID: conversationID)
    }

    var hasInputText: Bool {
        // "Has input" now also counts pasted images even if the user
        // typed no prose. A message with just a screenshot and no
        // accompanying text is a legitimate send.
        draftHasContent
    }

    /// Shows stop only when generating *and* the input is empty. If the user
    /// is mid-typing a follow-up while a reply streams, we keep the send glyph
    /// — that click queues the message without interrupting the live stream.
    var primaryActionIsStop: Bool {
        isGenerating && !hasInputText
    }

    @ViewBuilder
    func primaryActionButton() -> some View {
        let _ = AIChatRenderDebug.hit("PromptInputView.primaryActionButton")

        Button {
            if primaryActionIsStop {
                cancelCurrentGeneration()
            } else {
                draftSendRequestToken += 1
            }
        } label: {
            if #available(macOS 14.0, *) {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .frame(width: 16, height: 16)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .frame(width: 16, height: 16)
            }
        }
        .modernButtonStyle(style: .glass, size: primaryActionButtonSize, shape: .circle)
        .accessibilityLabel(
            Text(localizable: primaryActionIsStop ? .aiChatButtonStop : .aiChatButtonSend)
        )
        // Stop is always enabled while generating. Send needs text.
        .disabled(!primaryActionIsStop && !hasInputText)
    }
}

private extension View {
    @ViewBuilder
    func promptActionBarHoverEffect() -> some View {
#if os(iOS)
        self
            .frame(minWidth: 32, minHeight: 32)
            .contentShape(Rectangle())
            .hoverEffect()
#else
        self
#endif
    }
}
