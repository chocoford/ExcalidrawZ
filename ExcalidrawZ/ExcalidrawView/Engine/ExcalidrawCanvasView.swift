//
//  ExcalidrawCanvasView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
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
    var onError: (Error) -> Void
    var interactionEnabled: Bool
    
    
    // MARK: - State
    
    @StateObject private var excalidrawCore = ExcalidrawCore()
    @State private var hasSetupCore = false
    
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
        onError: @escaping (Error) -> Void
    ) {
        self.type = type
        self._file = file
        self.savingType = savingType
        self._loadingState = loadingState
        self.interactionEnabled = interactionEnabled
        self.onError = onError
    }
    
    // MARK: - Body
    
    var body: some View {
        ExcalidrawViewRepresentable()
            .modifier(MediaItemSyncModifier())
            .environmentObject(excalidrawCore)
#if os(macOS)
            .onWindowEvent(.didBecomeKey) { _ in
                applyColorMode()
            }
#endif
            .onReceive(
                NotificationCenter.default.publisher(for: .forceReloadExcalidrawFile)
            ) { _ in
                Task { await excalidrawCore.loadFile(from: file, force: true) }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .captureCurrentDrawingSettings)
            ) { _ in
                Task {
                    await captureCurrentDrawingSettings()
                }
            }
            .onChange(of: interactionEnabled) { enabled in
                Task {
                    try? await excalidrawCore.toggleWebPointerEvents(enabled: enabled)
                }
            }
            .onChange(of: file) { newFile in
                handleFileChange(newFile)
            }
            .onChange(of: colorScheme) { newValue in
                // self.logger.info("color scheme changed: \(newValue)")
                // will trigger when ios move app to background
                applyColorMode(colorScheme: newValue)
            }
            .onChange(of: appPreference.excalidrawAppearance) { _ in
                applyColorMode()
            }
            .onChange(of: loadingState) { state in
                if state == .loaded {
                    applyAllSettings()
                    if let file {
                        handleFileChange(file)
                    }
                }
            }
#if os(iOS)
            .onChange(of: scenePhase) { scenePhase in
                if scenePhase == .active {
                    applyColorMode(scenePhase: scenePhase)
                }
            }
#endif
            .task {
                await listenToLoadingState()
            }
            .task {
                await listenToErrors()
            }
            .onAppear {
                setupCore()
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
        toolState.excalidrawWebCoordinator = excalidrawCore
        switch type {
            case .normal:
                exportState.excalidrawWebCoordinator = excalidrawCore
                fileState.excalidrawWebCoordinator = excalidrawCore
                canvasPreferencesState.coordinator = excalidrawCore
            case .collaboration:
                exportState.excalidrawCollaborationWebCoordinator = excalidrawCore
                fileState.excalidrawCollaborationWebCoordinator = excalidrawCore
        }
    }
    
    // MARK: - Async Listeners
    
    private func listenToLoadingState() async {
        for await isLoading in excalidrawCore.$isLoading.values {
            await MainActor.run {
                loadingState = isLoading ? .loading : .loaded
            }

            if !isLoading, type == .normal {
                Task { await syncCanvasPrefsFromWeb() }
                await MainActor.run { syncCanvasDrawingSettingsFromFile() }
            }

#if os(iOS)
            if !isLoading {
                try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.5))
                try? await excalidrawCore.toggleToolbarAction(key: "h")
            }
#endif
        }
    }

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
                onError(error)
            }
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleFileChange(_ newFile: ExcalidrawFile?) {
        guard !excalidrawCore.webView.isLoading else { return }

        if type == .collaboration {
            if newFile?.roomID?.isEmpty == false {
                // has roomID
            }
            return
        }

        guard let newFile else { return }

        // Only reload the scene when switching to a different file.
        if excalidrawCore.previousFileID?.uuidString != newFile.id {
            excalidrawCore.previousFileID = UUID(uuidString: newFile.id)
            // Switching files within the same WebView session doesn't toggle the
            // WebView-level `isLoading`, so the sync hooked to that signal won't
            // fire. Now that `loadFile` properly awaits Excalidraw's scene
            // application, we can chain the re-sync directly.
            Task {
                await excalidrawCore.loadFile(from: newFile)
                if type == .normal {
                    await syncCanvasPrefsFromWeb()
                    await MainActor.run { syncCanvasDrawingSettingsFromFile() }
                }
            }
        }
    }
    
    // MARK: - Settings Application
    
    private func applyAllSettings() {
        applyFonts()
        applyColorMode()
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
        let colorScheme = scheme ?? colorScheme
        let scenePhase = phase ?? scenePhase
        guard loadingState == .loaded, scenePhase == .active else { return }

        Task {
            do {
                let isDark: Bool
                if appPreference.excalidrawAppearance == .auto {
                    isDark = colorScheme == .dark
                } else {
                    isDark = (appPreference.excalidrawAppearance.colorScheme ?? colorScheme) == .dark
                }
                self.logger.info("apply color mode: \(isDark ? "dark" : "light")")
                try await excalidrawCore.changeColorMode(dark: isDark)
            } catch {
                onError(error)
            }
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


