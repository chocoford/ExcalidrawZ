//
//  CompactExcalidrawBottomToolbarContent.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/07.
//

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

import ChocofordUI
import LLMKit
import SFSafeSymbols
import UIKit

struct CompactExcalidrawBottomToolbarContent: ToolbarContent {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerSize) private var containerSize

    @EnvironmentObject private var appPreference: AppPreference
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var toolState: ToolState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var aiChatState: AIChatState
    @EnvironmentObject private var llmState: LLMStateObject
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if fileState.currentActiveFile != nil {
                if toolState.inDragMode {
                    if layoutState.isCompactAIChatToolbarPresented,
                       canPresentCompactAIChatToolbarInput {
                        if compactAIChatIsReplying {
                            compactAIChatToolbarFullscreenButton
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                            Spacer(minLength: 0)
                        } else if layoutState.isCompactAIChatInputEditing {
                            Spacer(minLength: 0)
                        } else {
                            compactAIChatToolbarAttachmentMenu
                            Spacer(minLength: 0)
                            compactAIChatToolbarPlaceholder
                                .frame(maxWidth: .infinity)
                            Spacer(minLength: 0)
                        }
                        if !compactAIChatIsReplying || compactAIChatShowsStopButton {
                            compactAIChatToolbarCloseButton
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    } else {
                        compactDragModeControls
                    }
                } else if let activatedTool = toolState.activatedTool, activatedTool != .cursor {
                    activeToolControls(activatedTool)
                } else {
                    cursorToolControls
                }
            }
        }
    }

    @ViewBuilder
    private func activeToolControls(_ activatedTool: ExcalidrawTool) -> some View {
        activeToolLockButton

        Spacer(minLength: 0)

        Text(activatedTool.localization)
            .frame(maxWidth: .infinity, alignment: .center)

        Spacer(minLength: 0)

        Button {
            if activatedTool == .arrow {
                Task {
                    try? await toolState.excalidrawWebCoordinator?.toggleToolbarAction(key: "\u{1B}")
                }
            }
            toolState.setActivedTool(.cursor)
        } label: {
            Label(.localizable(.generalButtonCancel), systemSymbol: .checkmark)
        }
        .modernButtonStyle(style: .glassProminent, shape: .circle)
    }

    @ViewBuilder
    private var activeToolLockButton: some View {
        Button {
            toolState.toggleToolLock()
        } label: {
            if #available(iOS 17.0, *) {
                Image(systemSymbol: toolState.isToolLocked ? .lock : .lockOpen)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemSymbol: toolState.isToolLocked ? .lock : .lockOpen)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(toolState.isToolLocked ? Color.accentColor : Color.primary)
        .help("\(String(localizable: .toolbarButtonLockToolHelp)) - Q")
        .accessibilityLabel(Text(localizable: .toolbarButtonLockToolLabel))
        .animation(.default, value: toolState.isToolLocked)
    }

    @ViewBuilder
    private var cursorToolControls: some View {
        HStack(spacing: 20) {
            Button {
                toolState.setActivedTool(.freedraw)
            } label: {
                Label(.localizable(.toolbarDraw), systemSymbol: .pencilAndOutline)
            }

            Spacer()

            Menu {
                shapeAndToolMenuItems
            } label: {
                if toolState.activatedTool == .cursor {
                    Label(.localizable(.toolbarShapesAndTools), systemSymbol: .squareOnCircle)
                } else {
                    activeShape()
                        .foregroundStyle(Color.accentColor)
                }
            }
            .menuOrder(.fixed)

            Spacer()

            ExcalidrawToolbarMoreToolsMenu()

            Spacer()

            if toolState.activatedTool == .cursor {
                if let coordinator = toolState.excalidrawWebCoordinator {
                    CursorModeTrailingButton(coordinator: coordinator) {
                        toolState.setActivedTool(.hand)
                    }
                } else {
                    Button {
                        toolState.setActivedTool(.hand)
                    } label: {
                        Text(.localizable(.generalButtonDone))
                    }
                }
            } else {
                Button {
                    toolState.setActivedTool(.cursor)
                } label: {
                    Text(.localizable(.generalButtonCancel))
                }
            }
        }
    }

    @ViewBuilder
    private var compactDragModeControls: some View {
        compactStatusBar
        
        Spacer(minLength: 0)

        ViewThatFits(in: .horizontal) {
            compactExpandedInspectorControls
            compactCollapsedInspectorControls
        }

        Spacer(minLength: 0)
        
        compactEditButton
    }

    @ViewBuilder
    private var compactExpandedInspectorControls: some View {
        HStack(spacing: 8) {
            compactInspectorTabButton(
                tab: .preference,
                icon: .sliderHorizontal3,
                title: String(localizable: .canvasPreferencesTitle)
            )
            compactInspectorTabButton(
                tab: .search,
                icon: .magnifyingglass,
                title: String(localizable: .searchButtonTitle)
            )
            .keyboardShortcut("f", modifiers: .command)
            compactInspectorTabButton(
                tab: .library,
                icon: .book,
                title: String(localizable: .librariesTitle)
            )
            compactInspectorTabButton(
                tab: .history,
                icon: .clockArrowCirclepath,
                title: String(localizable: .checkpoints)
            )
            compactInspectorTabButton(
                tab: .aiChat,
                icon: .sparkles,
                title: "AI Chat",
                action: toggleCompactAIChatPresentation
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var compactCollapsedInspectorControls: some View {
        HStack(spacing: 20) {
            compactInspectorTabButton(
                tab: .library,
                icon: .book,
                title: String(localizable: .librariesTitle)
            )
            compactInspectorTabButton(
                tab: .aiChat,
                icon: .sparkles,
                title: "AI Chat",
                action: toggleCompactAIChatPresentation
            )
            compactInspectorTabsMenu()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var compactStatusBar: some View {
        if let activeFile = fileState.currentActiveFile {
            FileICloudSyncStatusIndicator(file: activeFile)
                .frame(width: 28, height: 28)
        }
    }

    @ViewBuilder
    private var compactAIChatToolbarAttachmentMenu: some View {
        CompactAIChatToolbarAttachmentMenu {
            layoutState.enterCompactAIChatInputEditing()
        }
    }

    @ViewBuilder
    private var compactAIChatToolbarPlaceholder: some View {
        CompactAIChatToolbarPlaceholderButton(draftState: compactAIChatDraftState) {
            layoutState.enterCompactAIChatInputEditing()
        }
    }

    @ViewBuilder
    private var compactAIChatToolbarFullscreenButton: some View {
        NavigationLink(value: EditorRoute.aiChat) {
            Image(systemSymbol: .rectangleExpandVertical)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .foregroundStyle(Color.primary)
        .help(.localizable(.aiChatButtonFullscreen))
        .accessibilityLabel(Text(localizable: .aiChatButtonFullscreen))
    }

    @ViewBuilder
    private var compactAIChatToolbarCloseButton: some View {
        Button {
            if compactAIChatShowsStopButton {
                stopCompactAIChatGeneration()
            } else {
                layoutState.exitCompactAIChatToolbar()
            }
        } label: {
            ZStack {
                if compactAIChatShowsStopButton {
                    Image(systemSymbol: .stopFill)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    Image(systemSymbol: .xmark)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .foregroundStyle(compactAIChatShowsStopButton ? Color.accentColor : Color.primary)
        .help(compactAIChatToolbarTrailingTitle)
        .animation(.smooth(duration: 0.2), value: compactAIChatShowsStopButton)
    }

    @ViewBuilder
    private var compactEditButton: some View {
        Button {
            if case .file(let file) = fileState.currentActiveFile, file.inTrash {
                layoutState.isResotreAlertIsPresented.toggle()
            } else {
                toolState.setActivedTool(.cursor)
            }
        } label: {
            Label(.localizable(.toolbarEdit), systemSymbol: .pencil)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .modernButtonStyle(style: .glassProminent, size: .small, shape: .circle)
        .help(String(localizable: .toolbarEdit))
    }

    @ViewBuilder
    private func compactInspectorTabButton(
        tab: LayoutState.InspectorTab,
        icon: SFSymbol,
        title: String,
        action: (() -> Void)? = nil
    ) -> some View {
        let isDisabled = compactInspectorTabIsDisabled(tab)
        let isActive = compactInspectorTabIsActive(tab)

        Button {
            guard !isDisabled else { return }
            if let action {
                action()
            } else {
                layoutState.toggleInspector(tab)
            }
        } label: {
            Label(title, systemSymbol: icon)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .help(title)
        .opacity(isDisabled && !isActive ? 0.55 : 1)
        .allowsHitTesting(!isDisabled)
    }

    @ViewBuilder
    private func compactInspectorTabsMenu() -> some View {
        Menu {
            compactInspectorTabMenuButton(
                tab: .preference,
                icon: .sliderHorizontal3,
                title: String(localizable: .canvasPreferencesTitle)
            )
            compactInspectorTabMenuButton(
                tab: .search,
                icon: .magnifyingglass,
                title: String(localizable: .searchButtonTitle)
            )
            .keyboardShortcut("f", modifiers: .command)
            compactInspectorTabMenuButton(
                tab: .history,
                icon: .clockArrowCirclepath,
                title: String(localizable: .checkpoints)
            )
        } label: {
            Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(compactCollapsedInspectorTabsContainActive ? Color.accentColor : Color.primary)
        }
            .fixedSize()
            .menuIndicator(.hidden)
            .help(String(localizable: .generalButtonMore))
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private func compactInspectorTabMenuButton(
        tab: LayoutState.InspectorTab,
        icon: SFSymbol,
        title: String
    ) -> some View {
        let isDisabled = compactInspectorTabIsDisabled(tab)
        Button {
            guard !isDisabled else { return }
            layoutState.toggleInspector(tab)
        } label: {
            Label(title, systemSymbol: icon)
        }
        .disabled(isDisabled)
    }

    private var compactCollapsedInspectorTabsContainActive: Bool {
        [LayoutState.InspectorTab.preference, .search, .history].contains { tab in
            compactInspectorTabIsActive(tab)
        }
    }

    private func compactInspectorTabIsDisabled(_ tab: LayoutState.InspectorTab) -> Bool {
        switch tab {
            case .history:
                return fileState.currentActiveFile == nil
            default:
                return false
        }
    }

    private func compactInspectorTabIsActive(_ tab: LayoutState.InspectorTab) -> Bool {
        if tab == .aiChat, layoutState.isCompactAIChatToolbarPresented {
            return true
        }
        if tab == .aiChat, layoutState.isAIChatIslandMode {
            return true
        }
        return layoutState.isInspectorPresented && layoutState.activeInspectorTab == tab
    }

    private var canPresentCompactAIChatToolbarInput: Bool {
        usesCompactIOSBottomToolbar &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    private var usesCompactIOSBottomToolbar: Bool {
        ExcalidrawToolbarLayoutPolicy.usesCompactIOSBottomToolbar(
            horizontalSizeClass: containerHorizontalSizeClass,
            containerWidth: containerSize.width
        )
    }

    private var compactAIChatDraftState: AIChatPromptDraftState {
        aiChatState.promptDraftState(
            conversationID: fileState.aiChatConversationID,
            fileScope: fileState.currentActiveFile?.aiConversationFileScope
        )
    }

    private var compactAIChatIsGenerating: Bool {
        guard let conversationID = fileState.aiChatConversationID else { return false }
        return llmState.isRunning(conversationID: conversationID)
    }

    private var compactAIChatIsReplying: Bool {
        compactAIChatIsGenerating ||
            layoutState.isCompactAIChatReplyTickerVisible ||
            layoutState.isCompactAIChatReplyStartPending
    }

    private var compactAIChatShowsStopButton: Bool {
        compactAIChatIsGenerating || layoutState.isCompactAIChatReplyStartPending
    }

    private var compactAIChatToolbarTrailingTitle: String {
        compactAIChatShowsStopButton ? "Stop AI generation" : String(localizable: .generalButtonClose)
    }

    private func stopCompactAIChatGeneration() {
        let wasGenerating = compactAIChatIsGenerating
        layoutState.isCompactAIChatReplyStartPending = false
        guard let conversationID = fileState.aiChatConversationID else {
            layoutState.isCompactAIChatReplyTickerVisible = false
            return
        }
        llmState.cancelGeneration(conversationID: conversationID)
        aiChatState.markGenerationCancelled(conversationID: conversationID)
        if !wasGenerating {
            layoutState.isCompactAIChatReplyTickerVisible = false
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            aiChatState.pendingQueue.removeAll()
        }
    }

    private func toggleCompactAIChatPresentation() {
        if layoutState.isCompactAIChatToolbarPresented {
            if layoutState.isCompactAIChatInputEditing {
                layoutState.exitCompactAIChatToolbar()
            } else {
                layoutState.enterCompactAIChatInputEditing()
            }
        } else if canPresentCompactAIChatToolbarInput {
            if !toolState.inDragMode {
                toolState.setActivedTool(.hand)
            }
            layoutState.enterCompactAIChatToolbar()
        } else if layoutState.isAIChatIslandMode {
            layoutState.isAIChatIslandMode = false
        } else {
            layoutState.toggleInspector(.aiChat)
        }
    }

    @ViewBuilder
    private var shapeAndToolMenuItems: some View {
        ForEach(compactShapeAndToolMenuTools, id: \.self) { tool in
            Button {
                toolState.setActivedTool(tool)
            } label: {
                toolMenuLabel(tool)
            }
        }
    }

    private var compactShapeAndToolMenuTools: [ExcalidrawTool] {
        appPreference.toolbarToolOrder.tools.filter { tool in
            switch tool {
                case .cursor, .freedraw, .hand, .lasso:
                    false
                default:
                    true
            }
        }
    }

    @ViewBuilder
    private func activeShape() -> some View {
        if let tool = toolState.activatedTool,
           tool != .cursor {
            toolMenuLabel(tool)
        } else {
            Label(.localizable(.toolbarShapes), systemSymbol: .squareOnCircle)
        }
    }

    @ViewBuilder
    private func toolMenuLabel(_ tool: ExcalidrawTool) -> some View {
        Label {
            Text(tool.localization)
        } icon: {
            Image(systemSymbol: tool.menuSystemSymbol)
        }
    }
}

private struct CompactAIChatToolbarPlaceholderButton: View {
    @ObservedObject var draftState: AIChatPromptDraftState

    let onBeginEditing: () -> Void

    private var displayText: String {
        let text = draftState.text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localizable: .aiChatInputPlaceholder) : text
    }

    var body: some View {
        Button {
            onBeginEditing()
        } label: {
            Label {
                Text(displayText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(systemSymbol: .sparkles)
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("AI Chat")
    }
}

struct CompactExcalidrawBottomToolbarStateModifier: ViewModifier {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerSize) private var containerSize
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var toolState: ToolState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var lockedContentState: LockedContentStateStore
    @ObservedObject private var aiChatPreferences = AIChatPreferences.shared

    private var canPresentCompactAIChatToolbarInput: Bool {
        usesCompactIOSBottomToolbar &&
            lockedContentState.activeFileLockState != .locked &&
            fileState.currentActiveFile != nil &&
            AIChatAvailability.isAvailable &&
            aiChatPreferences.isAIEnabled &&
            !fileState.currentActiveFileIsInTrash
    }

    private var usesCompactIOSBottomToolbar: Bool {
        ExcalidrawToolbarLayoutPolicy.usesCompactIOSBottomToolbar(
            horizontalSizeClass: containerHorizontalSizeClass,
            containerWidth: containerSize.width
        )
    }

    private var shouldShowCompactAIChatToolbarInput: Bool {
        layoutState.isCompactAIChatToolbarPresented && canPresentCompactAIChatToolbarInput
    }

    func body(content: Content) -> some View {
        content
            .watch(value: toolState.activatedTool) { newValue in
                guard usesCompactIOSBottomToolbar else { return }
                syncActiveTool(newValue)
            }
            .watch(value: toolState.inDragMode) { inDragMode in
                guard !inDragMode else { return }
                layoutState.exitCompactAIChatToolbar()
            }
            .watch(value: fileState.currentActiveFile?.id) { _ in
                layoutState.exitCompactAIChatToolbar()
            }
            .watch(value: lockedContentState.activeFileLockState) { lockState in
                guard lockState == .locked else { return }
                layoutState.exitCompactAIChatToolbar()
            }
            .watch(value: canPresentCompactAIChatToolbarInput) { canPresent in
                guard !canPresent else { return }
                layoutState.exitCompactAIChatToolbar()
            }
            .watch(value: shouldShowCompactAIChatToolbarInput) { shouldShowInput in
                guard shouldShowInput else { return }
                enterCompactAIChatInputEditingIfNeeded()
            }
            .watch(value: layoutState.isCompactAIChatToolbarPresented) { isPresented in
                guard isPresented else { return }
                guard canPresentCompactAIChatToolbarInput else {
                    layoutState.exitCompactAIChatToolbar()
                    return
                }
                if !toolState.inDragMode {
                    toolState.setActivedTool(.hand)
                }
                enterCompactAIChatInputEditingIfNeeded()
            }
    }

    private func enterCompactAIChatInputEditingIfNeeded() {
        guard shouldShowCompactAIChatToolbarInput,
              !layoutState.isCompactAIChatInputEditing
        else {
            return
        }
        layoutState.enterCompactAIChatInputEditing()
    }

    private func syncActiveTool(_ newValue: ExcalidrawTool?) {
        if newValue == nil {
            toolState.setActivedTool(.cursor)
        }

        guard let tool = newValue else { return }
        let webCoordinator = toolState.excalidrawWebCoordinator

        guard tool != webCoordinator?.lastTool else { return }
        Task {
            do {
                try await toolState.toggleTool(tool)
            } catch {
                alertToast(error)
            }
        }
    }
}

private struct CompactAIChatToolbarAttachmentMenu: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var aiChatState: AIChatState

    @State private var isImagePickerPresented = false
    @State private var isPhotoLibraryPickerPresented = false
    @State private var selectedPhotoPickerItems: [PhotosPickerItem] = []
    @State private var isCameraPickerPresented = false

    let onAttachImages: () -> Void

    private var promptDraftKey: String {
        aiChatState.promptDraftKey(
            conversationID: fileState.aiChatConversationID,
            fileScope: fileState.currentActiveFile?.aiConversationFileScope
        )
    }

    var body: some View {
        ZStack {
            Menu {
                Button {
                    beginAttachmentPickerPresentation()
                    isImagePickerPresented = true
                } label: {
                    Label(.localizable(.exportSheetButtonFile), systemSymbol: .doc)
                }

                Button {
                    presentPhotoLibraryPicker()
                } label: {
                    Label(.localizable(.aiChatInputAttachmentMenuItemPhotoLibrary), systemSymbol: .photoOnRectangle)
                }

                Button {
                    beginAttachmentPickerPresentation()
                    isCameraPickerPresented = true
                } label: {
                    Label(.localizable(.aiChatInputAttachmentMenuItemCamera), systemSymbol: .camera)
                }
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            } label: {
                Label(.localizable(.aiChatInputAttachmentMenuButtonAdd), systemSymbol: .plus)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)

            Color.clear
                .frame(width: 0, height: 0)
                .photosPicker(
                    isPresented: $isPhotoLibraryPickerPresented,
                    selection: $selectedPhotoPickerItems,
                    matching: .images
                )
        }
        .disabled(fileState.isAIChatConversationLoading || fileState.currentActiveFileIsInTrash)
        .fileImporter(
            isPresented: $isImagePickerPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            finishAttachmentPickerPresentation()
            handleImagePickerResult(result)
        }
        .sheet(isPresented: $isCameraPickerPresented, onDismiss: {
            finishAttachmentPickerPresentation()
        }) {
            AIChatCameraImagePicker { image in
                handleCameraImage(image)
            }
            .ignoresSafeArea()
        }
        .watch(value: isPhotoLibraryPickerPresented) { _, isPresented in
            guard !isPresented else { return }
            finishAttachmentPickerPresentation()
        }
        .watch(value: selectedPhotoPickerItems.map(\.itemIdentifier)) { _ in
            handlePhotoPickerItems(selectedPhotoPickerItems)
        }
    }

    @MainActor
    private func presentPhotoLibraryPicker() {
        beginAttachmentPickerPresentation()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            isPhotoLibraryPickerPresented = true
        }
    }

    @MainActor
    private func beginAttachmentPickerPresentation() {
        layoutState.isCompactAIChatAttachmentPickerPresented = true
    }

    @MainActor
    private func finishAttachmentPickerPresentation() {
        layoutState.isCompactAIChatAttachmentPickerPresented = false
    }

    @MainActor
    private func handleImagePickerResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let images = urls.compactMap { AIChatAttachmentImageImporter.pendingImage(from: $0) }
        appendImages(images)
    }

    @MainActor
    private func handlePhotoPickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            let images = await AIChatAttachmentImageImporter.pendingImages(from: items)
            await MainActor.run {
                selectedPhotoPickerItems = []
                appendImages(images)
            }
        }
    }

    @MainActor
    private func handleCameraImage(_ image: UIImage?) {
        guard let image else { return }
        appendImages([
            AIChatAttachmentImageImporter.pendingImage(from: image)
        ])
    }

    @MainActor
    private func appendImages(_ images: [PendingPastedImage]) {
        guard !images.isEmpty else { return }
        aiChatState.requestAppendDraftImages(images, draftKey: promptDraftKey)
        onAttachImages()
    }
}
#endif
