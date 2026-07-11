//
//  PromptInputView+CompactIOSFloatingInput.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/05.
//

#if os(iOS)
import SwiftUI
import PhotosUI
import ChocofordUI
import SFSafeSymbols
import UIKit

extension PromptInputView {
    private var compactIOSFloatingCircleControlLength: CGFloat { 44 }
    private var compactIOSFloatingInlineControlLabelLength: CGFloat { 16 }
    private var compactIOSFloatingInlineControlSymbolSize: CGFloat { 13 }
    private var compactIOSFloatingPrimaryActionLength: CGFloat { 42 }
    private var compactIOSFloatingPrimaryActionIconLength: CGFloat { 18 }
    private var compactIOSFloatingPrimaryActionTrailingPadding: CGFloat { 2 }
    private var compactIOSFloatingInlineActionTrailingPadding: CGFloat {
        compactIOSFloatingPrimaryActionTrailingPadding
        + (compactIOSFloatingPrimaryActionLength - compactIOSFloatingCircleControlLength) / 2
    }
    private var compactIOSFloatingExpandedInputMinHeight: CGFloat { 44 }
    private var compactIOSFloatingInputMaxHeight: CGFloat { 168 }
    private var compactIOSFloatingFullscreenInputMinHeight: CGFloat { 220 }
    private var compactIOSFloatingFullscreenInputMaxHeight: CGFloat { 520 }


    private var compactIOSFloatingShowsLowCreditsCapsule: Bool {
        guard let balance = llmState.creditsInfo?.balance else { return false }
        return balance < LowCreditsBannerView.defaultThreshold
    }

    var compactIOSFloatingInputIsExpanded: Bool {
        return promptDraftState.hasImages
        || (promptDraftState.hasContent && !compactIOSFloatingTextAreaIsSingleLine)
    }

    @ViewBuilder
    var compactIOSFloatingInputContent: some View {
        let isExpanded = compactIOSFloatingInputIsExpanded
        let isFullscreen = isCompactIOSFloatingFullscreenInputPresented
        let inputIsExpanded = isExpanded || isFullscreen

        VStack(alignment: .trailing, spacing: 5) {
            if !isFullscreen, !isExpanded {
                HStack(spacing: 0) {
                    if compactIOSFloatingShowsLowCreditsCapsule {
                        LowCreditsBannerView(presentation: .compactCapsule)
                        Spacer()
                    }
                    compactIOSFloatingInlineSettings
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .bottom, spacing: 7) {
                if !isFullscreen {
                    VStack(spacing: 7) {
                        if isExpanded {
                            compactIOSFloatingSettingsMenu
                                .transition(.opacity.combined(with: .scale))
                        }

                        compactIOSFloatingAttachmentMenu
                    }
                    .transition(.opacity.combined(with: .scale))
                }

                compactIOSFloatingTextInputSurface(
                    isExpanded: inputIsExpanded,
                    minHeight: compactIOSFloatingInputMinHeight(
                        isExpanded: isExpanded,
                        isFullscreen: isFullscreen
                    ),
                    maxTextAreaHeight: compactIOSFloatingTextAreaMaxHeight(
                        isFullscreen: isFullscreen
                    ),
                    showsExpandButton: isExpanded && compactIOSFloatingTextAreaIsOverflowing,
                    showsCollapseButton: isFullscreen
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.smooth(duration: 0.25), value: isCompactIOSFloatingFullscreenInputPresented)
    }


    @ViewBuilder
    private func compactIOSFloatingTextInputSurface(
        isExpanded: Bool,
        minHeight: CGFloat,
        maxTextAreaHeight: CGFloat,
        showsExpandButton: Bool,
        showsCollapseButton: Bool
    ) -> some View {
        PromptDraftInputField(
            draftKey: promptDraftKey,
            draftState: promptDraftState,
            showsAttachments: true,
            sendRequestToken: draftSendRequestToken,
            maxTextAreaHeight: maxTextAreaHeight,
            textInsets: compactIOSFloatingTextInsets(isExpanded: isExpanded),
            linesOverflow: $compactIOSFloatingTextAreaIsOverflowing,
            onTextAreaSingleLineChanged: { isSingleLine in
                compactIOSFloatingTextAreaIsSingleLine = isSingleLine
                if isSingleLine {
                    compactIOSFloatingTextAreaIsOverflowing = false
                }
            },
            focus: $isInputFocused,
            autofocus: focusOnAppear,
            onSubmit: { text, images in
                submitCompactIOSFloatingInputDraft(prompt: text, pastedImages: images)
            },
            onPaste: handlePastedItem,
            onSummaryChange: { hasContent, hasImages in
                updateDraftSummary(hasContent: hasContent, hasImages: hasImages)
            }
        )
        .id(ObjectIdentifier(promptDraftState))
        .transaction { transaction in
            transaction.animation = nil
        }
        .frame(
            maxWidth: .infinity,
            minHeight: minHeight,
            alignment: isExpanded ? .bottom : .center
        )
        .background(alignment: .bottom) {
            compactIOSFloatingTextInputBackground(isExpanded: isExpanded)
        }
        .clipShape(compactIOSFloatingTextInputShape(isExpanded: isExpanded))
        .overlay(alignment: isExpanded ? .bottomTrailing : .trailing) {
            compactIOSFloatingPrimaryActionButton
                .padding(.trailing, compactIOSFloatingPrimaryActionTrailingPadding)
                .padding(
                    .bottom,
                    isExpanded
                        ? (compactIOSFloatingCircleControlLength - compactIOSFloatingPrimaryActionLength) / 2
                        : 0
                )
        }
        .overlay(alignment: .topTrailing) {
            if showsCollapseButton {
                compactIOSFloatingCollapseFullscreenButton
                    .padding(.top, 6)
                    .padding(.trailing, compactIOSFloatingInlineActionTrailingPadding)
                    .transition(.opacity.combined(with: .scale))
            } else if showsExpandButton {
                compactIOSFloatingExpandFullscreenButton
                    .padding(.top, 6)
                    .padding(.trailing, compactIOSFloatingInlineActionTrailingPadding)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .contentShape(compactIOSFloatingTextInputShape(isExpanded: isExpanded))
        .matchedGeometryEffect(id: "compactIOSFloatingTextInputSurface", in: compactIOSFloatingInputNamespace)
    }

    private func compactIOSFloatingInputMinHeight(isExpanded: Bool, isFullscreen: Bool) -> CGFloat {
        if isFullscreen {
            return compactIOSFloatingFullscreenInputMinHeight
        }

        return isExpanded ? compactIOSFloatingExpandedInputMinHeight : compactIOSFloatingCircleControlLength
    }

    private func compactIOSFloatingTextAreaMaxHeight(isFullscreen: Bool = false) -> CGFloat {
        if isFullscreen {
            return compactIOSFloatingFullscreenInputMaxHeight
        }

        return compactIOSFloatingInputMaxHeight
    }

    private func compactIOSFloatingTextInsets(isExpanded: Bool) -> EdgeInsets {
        EdgeInsets(
            top: isExpanded ? 16 : 10,
            leading: 24,
            bottom: isExpanded ? 16 : 10,
            trailing: compactIOSFloatingPrimaryActionLength + 14
        )
    }

    @ViewBuilder
    private var compactIOSFloatingExpandFullscreenButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                isCompactIOSFloatingFullscreenInputPresented = true
            }
            refocusCompactIOSFloatingInput()
        } label: {
            Image(systemSymbol: .arrowUpLeftAndArrowDownRight)
                .font(.system(size: compactIOSFloatingInlineControlSymbolSize, weight: .semibold))
                .frame(
                    width: compactIOSFloatingInlineControlLabelLength,
                    height: compactIOSFloatingInlineControlLabelLength
                )
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
    }

    @ViewBuilder
    private var compactIOSFloatingCollapseFullscreenButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) {
                isCompactIOSFloatingFullscreenInputPresented = false
            }
            refocusCompactIOSFloatingInput()
        } label: {
            Image(systemSymbol: .arrowDownRightAndArrowUpLeft)
                .font(.system(size: compactIOSFloatingInlineControlSymbolSize, weight: .semibold))
                .frame(
                    width: compactIOSFloatingInlineControlLabelLength,
                    height: compactIOSFloatingInlineControlLabelLength
                )
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
    }

    private func refocusCompactIOSFloatingInput() {
        isInputFocused = true
        Task { @MainActor in
            await Task.yield()
            isInputFocused = true
        }
    }

    @MainActor
    private func submitCompactIOSFloatingInputDraft(
        prompt: String,
        pastedImages: [PendingPastedImage]
    ) -> Bool {
        let didSubmit = submitDraft(prompt: prompt, pastedImages: pastedImages)
        if didSubmit {
            onSuccessfulSubmit?()
            if dismissKeyboardOnSuccessfulSubmit {
                dismissCompactIOSFloatingKeyboard()
            }
        }
        return didSubmit
    }

    @ViewBuilder
    private func compactIOSFloatingTextInputBackground(isExpanded: Bool) -> some View {
        let shape = compactIOSFloatingTextInputShape(isExpanded: isExpanded)

        if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.regularMaterial)
        }
    }

    private func compactIOSFloatingTextInputShape(isExpanded: Bool) -> AnyShape {
        if isExpanded {
            AnyShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            AnyShape(Capsule())
        }
    }

    @ViewBuilder
    var compactIOSFloatingAttachmentMenu: some View {
        AIChatAttachmentMenu(
            canInsertImages: canInsertImages,
            isFileImporterPresented: $isImagePickerPresented,
            selectedPhotoPickerItems: $iOSSelectedPhotoPickerItems,
            isPhotoLibraryPickerPresented: $isIOSPhotoLibraryPickerPresented,
            isCameraPickerPresented: $isIOSCameraPickerPresented,
            onBeginPickerPresentation: {
                beginIOSAttachmentPickerPresentation()
            },
            onFilePickerDismiss: {
                finishIOSAttachmentPickerPresentation()
            },
            onPhotoPickerDismiss: {
                finishIOSAttachmentPickerPresentation()
            },
            onCameraPickerDismiss: {
                finishIOSAttachmentPickerPresentation()
            },
            onImagesPicked: appendAttachmentImages,
            onImageInputUnavailable: showImageInputUnavailableToast
        ) {
            Image(systemSymbol: .plus)
                .font(.system(size: 16, weight: .semibold))
                .frame(
                    width: compactIOSFloatingInlineControlLabelLength,
                    height: compactIOSFloatingInlineControlLabelLength
                )
                .padding(7)
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
    }

    @ViewBuilder
    var compactIOSFloatingInlineSettings: some View {
        HStack(spacing: 0) {
            compactIOSFloatingFileAccessButton

            compactIOSFloatingModelPicker

            if showsCompactIOSFullChatButton {
                compactIOSFloatingFullChatButton
            }

            if isInputFocused {
                compactIOSFloatingDismissKeyboardButton
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.smooth(duration: 0.18), value: isInputFocused)
    }

    @ViewBuilder
    var compactIOSFloatingPrimaryActionButton: some View {
        Button {
            if primaryActionIsStop {
                cancelCurrentGeneration()
            } else {
                draftSendRequestToken += 1
            }
        } label: {
            if #available(iOS 17.0, *) {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(
                        width: compactIOSFloatingPrimaryActionIconLength,
                        height: compactIOSFloatingPrimaryActionIconLength
                    )
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: primaryActionIsStop ? .stopFill : .arrowUp)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(
                        width: compactIOSFloatingPrimaryActionIconLength,
                        height: compactIOSFloatingPrimaryActionIconLength
                    )
            }
        }
        .modernButtonStyle(
            style: primaryActionIsStop ? .glass : .glassProminent,
            size: .regular,
            shape: .circle
        )
        .frame(
            width: compactIOSFloatingPrimaryActionLength,
            height: compactIOSFloatingPrimaryActionLength
        )
        .clipShape(Circle())
        .contentShape(Circle())
        .disabled(!primaryActionIsStop && !hasInputText)
    }

    @ViewBuilder
    var compactIOSFloatingFileAccessButton: some View {
        Button {
            toggleAIFileAccess()
        } label: {
            if #available(iOS 17.0, *) {
                Image(systemSymbol: activeFileAccessAllowsAI ? .eye : .eyeSlash)
                    .font(.system(size: compactIOSFloatingInlineControlSymbolSize, weight: .semibold))
                    .frame(
                        width: compactIOSFloatingInlineControlLabelLength,
                        height: compactIOSFloatingInlineControlLabelLength
                    )
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: activeFileAccessAllowsAI ? .eye : .eyeSlash)
                    .font(.system(size: compactIOSFloatingInlineControlSymbolSize, weight: .semibold))
                    .frame(
                        width: compactIOSFloatingInlineControlLabelLength,
                        height: compactIOSFloatingInlineControlLabelLength
                    )
            }
        }
        .foregroundStyle(activeFileAccessAllowsAI ? .primary : .secondary)
        .tint(activeFileAccessAllowsAI ? .accentColor : .secondary.opacity(0.75))
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
        .animation(.smooth(duration: 0.18), value: activeFileAccessAllowsAI)
        .disabled(!hasActiveFileForAIAccessControl || !canToggleAIFileAccess)
        .modifier(FeatureDiscoveryTipModifier(
            kind: .aiFileVisibility,
            isEnabled: hasActiveFileForAIAccessControl && canToggleAIFileAccess
        ))
    }

    @ViewBuilder
    var compactIOSFloatingModelPicker: some View {
        Menu {
            modelTierPickerButtons()
        } label: {
            Text(compactIOSFloatingModelPickerTitle)
                .font(.system(size: 11, weight: .semibold))
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(
                    width: compactIOSFloatingInlineControlLabelLength,
                    height: compactIOSFloatingInlineControlLabelLength
                )
        }
        .fixedSize()
        .menuIndicator(.hidden)
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
        .disabled(modelPickerTiers.isEmpty)
    }

    @MainActor
    var compactIOSFloatingModelPickerTitle: String {
        activeModelProfileOption?.tier.compactIOSFloatingShortLabel ?? "..."
    }

    @ViewBuilder
    var compactIOSFloatingFullChatButton: some View {
        Button {
            enterCompactIOSFloatingFullChat()
        } label: {
            Image(systemSymbol: .rectangleExpandVertical)
                .font(.system(size: compactIOSFloatingInlineControlSymbolSize, weight: .semibold))
                .frame(
                    width: compactIOSFloatingInlineControlLabelLength,
                    height: compactIOSFloatingInlineControlLabelLength
                )
                .contentShape(Circle())
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
        .help(.localizable(.aiChatButtonFullscreen))
        .accessibilityLabel(Text(localizable: .aiChatButtonFullscreen))
    }

    @ViewBuilder
    var compactIOSFloatingDismissKeyboardButton: some View {
        Button {
            dismissCompactIOSFloatingKeyboard()
        } label: {
            Image(systemSymbol: .keyboardChevronCompactDown)
                .font(.system(size: compactIOSFloatingInlineControlSymbolSize, weight: .semibold))
                .frame(
                    width: compactIOSFloatingInlineControlLabelLength,
                    height: compactIOSFloatingInlineControlLabelLength
                )
                .contentShape(Circle())
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
    }

    @MainActor
    private func dismissCompactIOSFloatingKeyboard() {
        isInputFocused = false
        guard layoutState.isCompactAIChatToolbarPresented,
              layoutState.isCompactAIChatInputEditing
        else {
            return
        }
        layoutState.exitCompactAIChatInputEditing()
    }

    private func enterCompactIOSFloatingFullChat() {
        dismissCompactIOSFloatingKeyboard()
        isCompactIOSFloatingFullscreenInputPresented = false
        layoutState.presentCompactAIChatFullChat()
    }

    @ViewBuilder
    var compactIOSFloatingSettingsMenu: some View {
        Menu {
            if showsIOSCompactContextMenuItem {
                Button {
                    compactCurrentContext()
                } label: {
                    if #available(iOS 18.0, *) {
                        Label(.localizable(.aiChatButtonCompactContext), systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
                    } else {
                        Label(.localizable(.aiChatButtonCompactContext), systemSymbol: .arrowTriangle2Circlepath)
                    }
                }
                .disabled(isCompactingContext)
            }

            Button {
                toggleAIFileAccess()
            } label: {
                Label(
                    .localizable(.aiChatButtonAIVisibility),
                    systemSymbol: activeFileAccessAllowsAI ? .eye : .eyeSlash
                )
            }
            .help(fileAccessHelpText)
            .disabled(!hasActiveFileForAIAccessControl || !canToggleAIFileAccess)

            Menu {
                modelTierPickerButtons()
            } label: {
                Text(modelPickerTitle)
            }

            if showsCompactIOSFullChatButton {
                Button {
                    enterCompactIOSFloatingFullChat()
                } label: {
                    Label(.localizable(.aiChatButtonFullscreen), systemSymbol: .rectangleExpandVertical)
                }
            }

#if DEBUG
            Button {
                generateDebugChatContext()
            } label: {
                Label("Debug Context", systemSymbol: .ladybug)
            }
#endif
        } label: {
            Image(systemSymbol: .listBullet)
                .font(.system(size: 16, weight: .semibold))
                .frame(
                    width: compactIOSFloatingInlineControlLabelLength,
                    height: compactIOSFloatingInlineControlLabelLength
                )
                .padding(7)
        }
        .fixedSize()
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
    }

    @MainActor
    private var showsIOSCompactContextMenuItem: Bool {
        guard let conversationID,
              let cap = activeModelContextWindowTokens,
              cap > 0
        else { return false }
        let used = llmState.estimatedTokenUsage(in: conversationID)
        return Double(used) / Double(cap) > 0.5
    }

    @MainActor
    private func beginIOSAttachmentPickerPresentation() {
        layoutState.isCompactAIChatAttachmentPickerPresented = true
        isInputFocused = true
    }

    @MainActor
    private func finishIOSAttachmentPickerPresentation(refocus: Bool = true) {
        guard layoutState.isCompactAIChatAttachmentPickerPresented else { return }
        layoutState.isCompactAIChatAttachmentPickerPresented = false
        guard refocus else { return }
        refocusCompactIOSFloatingInput()
    }

}

private extension ExcalidrawModelTier {
    var compactIOSFloatingShortLabel: String {
        switch self {
            case .low:
                return "L"
            case .medium:
                return "M"
            case .high:
                return "H"
            case .extraHigh:
                return "X"
        }
    }
}
#endif
