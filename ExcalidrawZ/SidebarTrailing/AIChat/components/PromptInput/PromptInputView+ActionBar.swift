//
//  PromptInputView+ActionBar.swift
//  ExcalidrawZ
//
//  Input controls, shared hit areas and send/stop presentation.
//  Model menus and route changes live in PromptInputView+ModelPicker.swift.
//

import SwiftUI
import ChocofordUI
import LLMKit
import LLMCore
import SFSafeSymbols

extension PromptInputView {
    var actionBarIconFrameLength: CGFloat { 18 }
    private var actionBarLeadingControlSpacing: CGFloat {
#if os(macOS)
        2
#else
        4
#endif
    }
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
#if os(macOS)
                .buttonStyle(PromptActionBarIconButtonStyle())
#endif
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
#if os(macOS)
        .buttonStyle(PromptActionBarIconButtonStyle())
        .foregroundStyle(activeFileAccessAllowsAI ? Color.accentColor : Color.secondary)
#else
        .foregroundStyle(activeFileAccessAllowsAI ? .primary : .secondary)
        .tint(activeFileAccessAllowsAI ? .accentColor : .secondary.opacity(0.75))
#endif
        .modifier(PromptActionBarHoverEffect())
        .disabled(!hasActiveFileForAIAccessControl || !canToggleAIFileAccess)
        .help(fileAccessHelpText)
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
        .modifier(PromptActionBarHoverEffect())

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
        .menuStyle(.button)
        .buttonStyle(PromptActionBarIconButtonStyle())
        .foregroundStyle(.secondary)

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
        // Stop is always enabled while generating. Send needs text.
        .disabled(!primaryActionIsStop && (!hasInputText || isUpdatingConversationRoute))
    }
}

#if os(macOS)
/// Menu and Button use the same surface instead of their different native bezels.
private struct PromptActionBarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PromptActionBarIconSurface(isPressed: configuration.isPressed))
    }
}

private struct PromptActionBarIconSurface: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: 28, height: 28)
            .background {
                Capsule()
                    .fill(Color.primary.opacity(
                        isEnabled && (isHovered || isPressed) ? (isPressed ? 0.12 : 0.06) : 0
                    ))
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }
}
#endif

/// Shared hit area for model selection and the adjacent input controls.
struct PromptActionBarHoverEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .frame(minWidth: 32, minHeight: 32)
            .contentShape(Rectangle())
            .hoverEffect()
#else
        content
#endif
    }
}
