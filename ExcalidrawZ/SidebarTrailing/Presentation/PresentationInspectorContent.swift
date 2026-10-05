//
//  PresentationInspectorContent.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/7/27.
//

import SwiftUI

import ChocofordUI
import SFSafeSymbols

struct PresentationInspectorContent: View {
    private struct LoadTaskIdentity: Hashable {
        let fileID: String?
        let coordinatorID: ObjectIdentifier?
        let usesDarkAppearance: Bool
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var appPreference: AppPreference

    @ObservedObject private var model: ExcalidrawPresentationModel
    @ObservedObject private var store = Store.shared
    @ObservedObject private var presentationController = ExcalidrawPresentationController.shared
    @State private var pendingReloadTask: Task<Void, Never>?
    // File switches can outlive the debounce window, so saves stay isolated by file.
    @State private var pendingConfigurationSaveTasks: [String: Task<Void, Never>] = [:]
    @State private var pendingConfigurationSaveIDs: [String: UUID] = [:]
    @State private var draggingSlideID: String?

    init(model: ExcalidrawPresentationModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    private var activeFileID: String? {
        fileState.currentActiveFile?.id
    }

    private var activeFileName: String {
        fileState.currentActiveFile?.name ?? String(localizable: .presentationTitle)
    }

    private var loadTaskIdentity: LoadTaskIdentity {
        LoadTaskIdentity(
            fileID: activeFileID,
            coordinatorID: activeCoordinator.map(ObjectIdentifier.init),
            usesDarkAppearance: colorScheme == .dark
        )
    }

    private var activeCoordinator: ExcalidrawCanvasView.Coordinator? {
        switch fileState.currentActiveFile {
            case .collaborationFile:
                fileState.excalidrawCollaborationWebCoordinator
            case .file, .localFile, .temporaryFile, .cloudStorageFile:
                fileState.excalidrawWebCoordinator
            case nil:
                nil
        }
    }

    private var usesInspectorToolbarChrome: Bool {
#if os(iOS)
        containerHorizontalSizeClass != .compact
#else
        appPreference.inspectorLayout == .sidebar
#endif
    }

    var body: some View {
        ZStack {
            if store.canUsePresentation {
                contentView
                    .transition(.opacity)
            } else {
                PresentationWelcomeView {
                    store.togglePaywall(reason: .presentation)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            if layoutState.isInspectorPresented {
#if os(macOS)
                ToolbarItemGroup(placement: .destructiveAction) {
                    openViewerButton
                }
#endif
                if usesInspectorToolbarChrome {
                    presentationHeaderToolbar
                }
                if store.canUsePresentation {
                    ToolbarItem(placement: .primaryAction) {
                        startPresentationButton
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var presentationHeaderToolbar: some ToolbarContent {
#if os(macOS)
        if #available(macOS 26.0, *) {
            // Match Library: separate the leading action from the title's glass background.
            ToolbarItemGroup(placement: .principal) {
                Spacer()
            }
        }
#endif
        InspectorHeaderToolbar(
            title: String(localizable: .presentationTitle),
            isInspectorPresented: layoutState.isInspectorPresented
        )
    }

    private var contentView: some View {
        content
            .task(id: loadTaskIdentity) {
                await reload()
            }
            .watch(value: activeFileID) { fileID in
                model.invalidateIfNeeded(for: fileID)
            }
            .overlay {
                if let activeCoordinator {
                    PresentationCanvasChangeObserver(
                        coordinator: activeCoordinator,
                        onContentChange: scheduleReload
                    )
                }
            }
            .watch(value: layoutState.isInspectorPresented) { isPresented in
                if isPresented,
                   layoutState.activeInspectorTab == .presentation {
                    scheduleReload()
                } else {
                    pendingReloadTask?.cancel()
                    pendingReloadTask = nil
                }
            }
            .onDisappear {
                pendingReloadTask?.cancel()
                pendingReloadTask = nil
            }
    }

#if os(macOS)
    private var canShowViewerTip: Bool {
        switch fileState.currentActiveFile {
            case .file, .localFile, .temporaryFile, .cloudStorageFile:
                true
            case .collaborationFile, nil:
                false
        }
    }

    private var openViewerButton: some View {
        Button {
            ViewerMirrorController.shared.prepareForOpeningViewer()
            openWindow(id: ViewerMirrorController.windowID)
        } label: {
            Label(
                String(localizable: .menubarOpenViewerWindow),
                systemSymbol: .macwindowOnRectangle
            )
            .labelStyle(.iconOnly)
        }
        .help(String(localizable: .menubarOpenViewerWindow))
        .modifier(FeatureDiscoveryTipModifier(
            kind: .viewerWindow,
            isEnabled: canShowViewerTip
        ))
    }
#endif

    private var startPresentationButton: some View {
        Button(action: startPresentation) {
            Label(
                String(localizable: .presentationStart),
                systemSymbol: .playFill
            )
            .labelStyle(.iconOnly)
        }
        .help(String(localizable: .presentationStart))
        .disabled(
            !model.isRepresenting(fileID: activeFileID) ||
            model.presentationSlides.isEmpty ||
            model.isLoading ||
            model.presentationSlides.contains { $0.image == nil }
        )
    }

    @ViewBuilder
    private var content: some View {
        if !model.isRepresenting(fileID: activeFileID) {
            PresentationInspectorPlaceholder(state: .loading)
        } else {
            switch model.state {
                case .idle,
                        .loading where model.slides.isEmpty:
                    PresentationInspectorPlaceholder(state: .loading)
                case .failed(let message):
                    PresentationInspectorPlaceholder(
                        state: .failed(message),
                        retry: retryLoading
                    )
                case .loaded where model.slides.isEmpty:
                    PresentationInspectorPlaceholder(state: .empty)
                default:
                    slideList
            }
        }
    }

    private var slideList: some View {
        PresentationSlideList(
            slides: model.slides,
            selectedSlideID: $model.selectedSlideID,
            draggingSlideID: $draggingSlideID,
            onMove: { sourceID, targetID in
                model.moveSlide(sourceID, to: targetID)
                scheduleConfigurationPersistence()
            },
            onDrop: finishConfigurationPersistence,
            onTransitionChange: { slideID, transition in
                model.setTransition(transition, for: slideID)
                finishConfigurationPersistence()
            },
            onTransitionDurationChange: { slideID, duration in
                model.setTransitionDuration(duration, for: slideID)
                scheduleConfigurationPersistence()
            },
            onTransitionDurationCommit: finishConfigurationPersistence
        )
    }

    private func reload() async {
        let fileID = activeFileID
        let contentChangeToken = activeCoordinator?.contentChangeToken
        model.invalidateIfNeeded(for: fileID)
        guard model.requiresLoad(
            fileID: fileID,
            contentChangeToken: contentChangeToken,
            colorScheme: colorScheme
        ) else {
            return
        }

        _ = await model.load(
            activeFile: fileState.currentActiveFile,
            coordinator: activeCoordinator,
            colorScheme: colorScheme,
            contentChangeToken: contentChangeToken
        )
    }

    private func scheduleReload() {
        guard layoutState.isInspectorPresented,
              layoutState.activeInspectorTab == .presentation else {
            return
        }

        pendingReloadTask?.cancel()
        pendingReloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    private func retryLoading() {
        Task {
            await reload()
        }
    }

    private func scheduleConfigurationPersistence() {
        guard let activeFile = fileState.currentActiveFile else {
            return
        }
        let fileID = activeFile.id
        let configuration = model.configuration
        pendingConfigurationSaveTasks[fileID]?.cancel()

        let saveID = UUID()
        pendingConfigurationSaveIDs[fileID] = saveID
        pendingConfigurationSaveTasks[fileID] = Task { @MainActor in
            defer {
                if pendingConfigurationSaveIDs[fileID] == saveID {
                    pendingConfigurationSaveTasks[fileID] = nil
                    pendingConfigurationSaveIDs[fileID] = nil
                }
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await persistConfiguration(
                configuration,
                for: activeFile
            )
        }
    }

    private func finishConfigurationPersistence() {
        guard let activeFile = fileState.currentActiveFile else {
            draggingSlideID = nil
            return
        }
        let fileID = activeFile.id
        let configuration = model.configuration
        draggingSlideID = nil
        pendingConfigurationSaveTasks[fileID]?.cancel()
        pendingConfigurationSaveTasks[fileID] = nil
        pendingConfigurationSaveIDs[fileID] = nil

        Task {
            await persistConfiguration(
                configuration,
                for: activeFile
            )
        }
    }

    private func startPresentation() {
        guard model.isRepresenting(fileID: activeFileID) else { return }
        presentationController.present(
            title: activeFileName,
            slides: model.presentationSlides,
            initialSlideID: model.initialPresentationSlideID
        )
    }

    private func persistConfiguration(
        _ configuration: ExcalidrawPresentationConfiguration,
        for activeFile: FileState.ActiveFile?
    ) async {
        do {
            try await model.persistConfiguration(
                configuration,
                for: activeFile
            )
        } catch {
            activeCoordinator?.publishError(error)
        }
    }
}

private struct PresentationCanvasChangeObserver: View {
    @ObservedObject var coordinator: ExcalidrawCore
    let onContentChange: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .watch(value: coordinator.contentChangeToken) { _ in
                onContentChange()
            }
    }
}
