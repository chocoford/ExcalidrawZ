//
//  ExcalidrawCanvasView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
import ChocofordUI
import Logging
import UniformTypeIdentifiers


struct ExcalidrawCanvasView: View {
    @AppStorage("addedFontsData") private var addedFontsData: Data = Data()

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var exportState: ExportState
    @EnvironmentObject var toolState: ToolState
    @EnvironmentObject var canvasPreferencesState: CanvasPreferencesState
    @Environment(\.excalidrawNativeViewportInsets) private var nativeViewportInsets
#if os(iOS)
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
#endif

    let logger = Logger(label: "ExcalidrawCanvasView")
    
    typealias Coordinator = ExcalidrawCore
    
    enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case error(Error)
        
        static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
            if case .idle = lhs, case .idle = rhs {
                return true
            }
            if case .loading = lhs, case .loading = rhs {
                return true
            }
            if case .loaded = lhs, case .loaded = rhs {
                return true
            }
            if case .error = lhs, case .error = rhs {
                return true
            }
            return false
        }
    }
    
    enum ExcalidrawType {
        case normal
        case collaboration
    }
    
    var type: ExcalidrawType
    var roomIDBinding: Binding<String>?
    @Binding var file: ExcalidrawFile?
    @Binding var loadingState: LoadingState
    var savingType: UTType
    var onDocumentLoadFinished: (String) -> Void
    var onError: (Error) -> Void
    var interactionEnabled: Bool
    
    
    // MARK: - State
    
    @StateObject private var excalidrawCore = ExcalidrawCore()
    @State private var hasSetupCore = false
    @State private var pendingErrorEvent: IdentifiableError?
    
    // MARK: - Computed Properties
    
    private var addedFonts: [String] {
        (try? JSONDecoder().decode([String].self, from: addedFontsData)) ?? []
    }
    
    // MARK: - Init
    
    init(
        type: ExcalidrawType = .normal,
        file: Binding<ExcalidrawFile?>,
        savingType: UTType = .excalidrawFile,
        loadingState: Binding<LoadingState>,
        interactionEnabled: Bool = true,
        onDocumentLoadFinished: @escaping (String) -> Void = { _ in },
        onError: @escaping (Error) -> Void
    ) {
        self.type = type
        self._file = file
        self.savingType = savingType
        self._loadingState = loadingState
        self.interactionEnabled = interactionEnabled
        self.onDocumentLoadFinished = onDocumentLoadFinished
        self.onError = onError
    }
    
    // MARK: - Body
    
    var body: some View {
        ExcalidrawViewRepresentable(nativeInteractionEnabled: interactionEnabled)
            .modifier(MediaItemSyncModifier())
            .modifier(MathImageEditSheetViewModifier(coordinator: excalidrawCore, onError: onError))
            .environmentObject(excalidrawCore)
#if os(macOS)
            .onWindowEvent(.didBecomeKey) { _ in
                applyColorMode()
            }
#endif
            .onReceive(
                NotificationCenter.default.publisher(for: .forceReloadExcalidrawFile)
            ) { _ in
                let targetFile = file
                Task {
                    await excalidrawCore.documentSyncController.load(targetFile, force: true)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .captureCurrentDrawingSettings)
            ) { _ in
                Task {
                    await captureCurrentDrawingSettings()
                }
            }
            .watch(value: interactionEnabled) { enabled in
                updateToolStateCoordinatorBinding(isEnabled: enabled)
                Task {
                    try? await excalidrawCore.toggleWebPointerEvents(enabled: enabled)
                }
            }
            .watch(value: file?.id) { _ in
                handleFileChange(file)
            }
            .watch(value: colorScheme) { newValue in
                // self.logger.info("color scheme changed: \(newValue)")
                // will trigger when ios move app to background
                applyColorMode(colorScheme: newValue)
            }
            .watch(value: appPreference.excalidrawAppearance) { _ in
                applyColorMode()
            }
            .watch(value: addedFontsData) { _ in
                applyFonts()
            }
            .watch(value: nativeViewportInsets, initial: true) { _, _ in
                applyNativeViewportInsets()
            }
            .watch(value: loadingState) { state in
                if state == .loaded {
                    applyAllSettings()
                    applyNativeViewportInsets()
                }
            }
            .watch(value: scenePhase) { scenePhase in
#if os(iOS)
                if scenePhase == .active {
                    applyColorMode(scenePhase: scenePhase)
                }
#endif
                if scenePhase == .background {
                    Task {
                        await excalidrawCore.documentSyncController
                            .flushPendingDirtySnapshot(reason: "sceneBackground", force: true)
                    }
                }
            }
            .watch(value: pendingErrorEvent) { event in
                guard let event else { return }
                onError(event.error)
            }
            .task {
                await listenToLoadingState()
            }
            .task {
                await listenToDocumentLoadEvents()
            }
            .task {
                await listenToErrors()
            }
            .onAppear {
                setupCore()
                updateToolStateCoordinatorBinding(isEnabled: interactionEnabled)
            }
            .onDisappear {
                clearToolStateCoordinatorBindingIfNeeded()
            }
    }
    
    // MARK: - Setup Methods
    
    private func setupCore() {
        guard !hasSetupCore else { return }
        hasSetupCore = true
        excalidrawCore.setup(parent: self)
        setupCoordinators()
    }
    
    private func setupCoordinators() {
        switch type {
            case .normal:
                exportState.excalidrawWebCoordinator = excalidrawCore
                fileState.excalidrawWebCoordinator = excalidrawCore
                canvasPreferencesState.coordinator = excalidrawCore
            case .collaboration:
                exportState.excalidrawCollaborationWebCoordinator = excalidrawCore
                fileState.excalidrawCollaborationWebCoordinator = excalidrawCore
        }
        updateToolStateCoordinatorBinding(isEnabled: interactionEnabled)
    }

    @MainActor
    private func updateToolStateCoordinatorBinding(isEnabled: Bool) {
        if isEnabled {
            toolState.excalidrawWebCoordinator = excalidrawCore
            if type == .collaboration {
                exportState.excalidrawCollaborationWebCoordinator = excalidrawCore
                fileState.excalidrawCollaborationWebCoordinator = excalidrawCore
            }
        } else {
            clearToolStateCoordinatorBindingIfNeeded()
        }
    }

    @MainActor
    private func clearToolStateCoordinatorBindingIfNeeded() {
        if toolState.excalidrawWebCoordinator === excalidrawCore {
            toolState.excalidrawWebCoordinator = nil
        }
    }
    
    // MARK: - Async Listeners
    
    private func listenToLoadingState() async {
        var previousIsLoading: Bool?

        for await isLoading in excalidrawCore.$isLoading.values {
            if isLoading, previousIsLoading != true {
                excalidrawCore.documentSyncController.resetFileLoadState()
            }

            let hasPendingFileLoad = excalidrawCore.documentSyncController.hasPendingFileLoad
            await MainActor.run {
                loadingState = (isLoading || hasPendingFileLoad) ? .loading : .loaded
            }

            if !isLoading,
               previousIsLoading != false,
               !hasPendingFileLoad,
               type == .normal {
                await MainActor.run {
                    handleFileChange(file)
                }
            }

#if os(iOS)
            if !isLoading, !hasPendingFileLoad {
                await applyPencilInteractionModeAfterLoadIfNeeded()
                await enterCompactDragModeAfterLoadIfNeeded()
            }
#endif

            previousIsLoading = isLoading
        }
    }

    private func listenToDocumentLoadEvents() async {
        guard type == .normal else { return }

        for await event in excalidrawCore.documentSyncController.loadEvents {
            switch event {
                case .started(let fileID):
                    let isCurrent = await MainActor.run { file?.id == fileID }
                    guard isCurrent else { continue }
                    await MainActor.run {
                        loadingState = .loading
                    }

                case .finished(let fileID, let succeeded):
                    let isCurrent = await MainActor.run { file?.id == fileID }
                    guard isCurrent else { continue }

                    if succeeded {
                        await applyLoadedFilePresentationSettings()
                    }

                    await MainActor.run {
                        loadingState = .loaded
                        if succeeded {
                            onDocumentLoadFinished(fileID)
                        }
                    }

#if os(iOS)
                    if succeeded {
                        await enterCompactDragModeAfterLoadIfNeeded()
                    }
#endif

                case .reset:
                    let isCoreLoading = await MainActor.run { excalidrawCore.isLoading }
                    await MainActor.run {
                        loadingState = isCoreLoading ? .loading : .loaded
                    }
            }
        }
    }

#if os(iOS)
    @MainActor
    private func applyPencilInteractionModeAfterLoadIfNeeded() async {
        guard toolState.inPenMode else { return }
        do {
            try await toolState.setPencilInteractionMode(toolState.pencilInteractionMode)
        } catch {
            logger.warning("Failed to apply Apple Pencil interaction mode after load: \(error)")
        }
    }

    @MainActor
    private func enterCompactDragModeAfterLoadIfNeeded() async {
        guard containerHorizontalSizeClass == .compact,
              type == .normal,
              file != nil,
              !toolState.inPenMode else {
            return
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard containerHorizontalSizeClass == .compact,
              type == .normal,
              file != nil,
              !toolState.inPenMode else {
            return
        }
        do {
            try await excalidrawCore.activateHandTool()
            toolState.setActivedTool(.hand)
        } catch {
            logger.warning("Failed to enter compact drag mode after load: \(error)")
        }
    }
#endif

    /// Pull the active file's canvas preferences and reconcile our Swift mirror.
    /// Called after each canvas load so a file switch can't leave stale prefs in the UI.
    private func syncCanvasPrefsFromWeb() async {
        guard let snapshot = try? await excalidrawCore.fetchCanvasPreferences() else {
            return
        }
        canvasPreferencesState.apply(snapshot)
    }

    /// Drawing prefs come from the file's own JSON appState — not from a web read.
    /// Excalidraw's `restoreAppState` carries `currentItem*` values forward from the
    /// previous file as defaults, so reading live state would surface stale values.
    ///
    /// Two writes happen here:
    ///   - **mirror** gets just the file's values (pristine; the inspector's
    ///     `matches()` does its own cascade for comparison).
    ///   - **web** gets the *effective* state (file → global → ui-defaults) so
    ///     actual drawing uses the right colors even for fields the file doesn't
    ///     explicitly set, and any `restoreAppState` contamination is overwritten.
    @MainActor
    private func syncCanvasDrawingSettingsFromFile() {
        let fileSettings = file?.content.map(UserDrawingSettings.from(fileContent:))
            ?? UserDrawingSettings()
        canvasPreferencesState.drawingSettings.apply(fileSettings)

        let effective = fileSettings
            .filling(defaults: appPreference.customDrawingSettings)
            .filling(defaults: .uiDefaults)
        Task {
            try? await excalidrawCore.applyUserSettings(effective)
        }
    }
    
    private func listenToErrors() async {
        for await error in excalidrawCore.errorStream {
            await MainActor.run {
                pendingErrorEvent = IdentifiableError(error)
            }
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleFileChange(_ newFile: ExcalidrawFile?) {
        if type == .collaboration {
            if newFile?.roomID?.isEmpty == false {
                // has roomID
            }
            return
        }

        guard let newFile else {
            excalidrawCore.documentSyncController.resetFileLoadState()
            return
        }
        guard fileState.currentActiveFile?.id == newFile.id else {
            return
        }

        guard excalidrawCore.documentSyncController.currentLoadedFileID != newFile.id else {
            return
        }

        // Only reload the scene when switching to a different file.
        //
        // Commit the loaded file id only after the JS side reports that this file
        // is loaded. If the first open races WebView readiness, keeping this nil
        // lets the ready callback or the retry loop re-attempt the load.
        // Switching files within the same WebView session doesn't toggle the
        // WebView-level `isLoading`, so the sync hooked to that signal won't
        // fire. Now that `loadFile` properly awaits Excalidraw's scene
        // application, we can chain the re-sync directly.
        loadingState = .loading
        Task {
            await excalidrawCore.documentSyncController.load(newFile)
        }
    }
    
    // MARK: - Settings Application
    
    private func applyAllSettings() {
        applyFonts()
        applyColorMode()
    }

    private func applyNativeViewportInsets() {
        let insets = nativeViewportInsets
        Task {
            try? await excalidrawCore.setNativeViewportInsets(insets)
        }
    }

    private func applyLoadedFilePresentationSettings() async {
        await applyColorModeAsync()

        guard type == .normal else { return }
        await syncCanvasPrefsFromWeb()
        await MainActor.run {
            syncCanvasDrawingSettingsFromFile()
        }
    }
    
    private func applyFonts() {
        guard loadingState == .loaded else { return }

        Task {
            do {
                try await excalidrawCore.setAvailableFonts(fontFamilies: addedFonts)
            } catch {
                onError(error)
            }
        }
    }
    
    private func applyColorMode(
        colorScheme scheme: ColorScheme? = nil,
        scenePhase phase: ScenePhase? = nil
    ) {
        Task {
            await applyColorModeAsync(colorScheme: scheme, scenePhase: phase)
        }
    }

    private func applyColorModeAsync(
        colorScheme scheme: ColorScheme? = nil,
        scenePhase phase: ScenePhase? = nil
    ) async {
        let colorScheme = scheme ?? colorScheme
        let scenePhase = phase ?? scenePhase
        guard loadingState == .loaded, scenePhase == .active else { return }

        do {
            let isDark: Bool
            if appPreference.excalidrawAppearance == .auto {
                isDark = colorScheme == .dark
            } else {
                isDark = (appPreference.excalidrawAppearance.colorScheme ?? colorScheme) == .dark
            }
            self.logger.debug("Apply color mode: \(isDark ? "dark" : "light")")
            try await excalidrawCore.changeColorMode(dark: isDark)
        } catch {
            onError(error)
        }
    }

    /// Capture current drawing settings from Excalidraw and save to preferences
    @MainActor
    private func captureCurrentDrawingSettings() async {
        guard loadingState == .loaded else {
            logger.warning("Cannot capture settings: Excalidraw not loaded")
            return
        }

        do {
            let settings = try await excalidrawCore.fetchCurrentUserSettings()
            appPreference.customDrawingSettings = settings
            logger.info("Successfully captured current drawing settings")
        } catch {
            logger.error("Failed to capture drawing settings: \(error)")
            onError(error)
        }
    }
}
