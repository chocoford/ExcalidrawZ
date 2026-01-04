//
//  WebView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import SwiftUI
import WebKit
import Combine
import Logging
import QuartzCore
import UniformTypeIdentifiers

class ExcalidrawWebView: WKWebView {
    var shouldHandleInput = true
    
    enum ToolbarActionKey {
        case number(Int)
        case char(Character)
        case space, escape
    }
    var toolbarActionHandler: (ToolbarActionKey) -> Void
    
    init(
        frame: CGRect,
        configuration: WKWebViewConfiguration,
        toolbarActionHandler: @escaping (ToolbarActionKey) -> Void
    ) {
        self.toolbarActionHandler = toolbarActionHandler
        super.init(frame: frame, configuration: configuration)
#if canImport(UIKit)
        self.scrollView.isScrollEnabled = false
        self.scrollView.backgroundColor = .clear
#endif
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
#if canImport(UIKit)
    override var safeAreaInsets: UIEdgeInsets { .zero }
#endif
    
#if canImport(AppKit)
    override func keyDown(with event: NSEvent) {
        if shouldHandleInput,
           let char = event.characters {
            if let num = Int(char), num >= 0, num <= 9 {
                self.toolbarActionHandler(.number(num))
            } else if ExcalidrawTool.allCases.compactMap({$0.keyEquivalent}).contains(where: {$0 == Character(char)}), !char.isEmpty {
                self.toolbarActionHandler(.char(Character(char)))
            } else if Character(char) == Character(" ") {
                // TODO: migrate to excalidrawZHelper
                self.toolbarActionHandler(.space)
            } else if Character(char) == Character("q") {
                // TODO: migrate to excalidrawZHelper
                self.toolbarActionHandler(.char("q"))
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
#endif
}

extension Notification.Name {
    static let forceReloadExcalidrawFile = Notification.Name("ForceReloadExcalidrawFile")
}

struct ExcalidrawView: View {
    @AppStorage("addedFontsData") private var addedFontsData: Data = Data()
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var exportState: ExportState
    @EnvironmentObject var toolState: ToolState

    let logger = Logger(label: "ExcalidrawView")
    
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
                excalidrawCore.loadFile(from: file, force: true)
            }
            .onChange(of: interactionEnabled) { enabled in
                Task {
                    try? await excalidrawCore.toggleWebPointerEvents(enabled: enabled)
                }
            }
            .onChange(of: file) { newFile in
                handleFileChange(newFile)
            }
            .onChange(of: colorScheme) { _ in
                applyColorMode()
            }
            .onChange(of: appPreference.excalidrawAppearance) { _ in
                applyColorMode()
            }
            .onChange(of: appPreference.autoInvertImage) { _ in
                applyImageInversion()
            }
            .onChange(of: appPreference.antiInvertImageSettings) { _ in
                applyImageInversion()
            }
            .onChange(of: loadingState) { state in
                if state == .loaded {
                    applyAllSettings()
                }
            }
//#if os(macOS)
//            .onChange(of: scenePhase) { scenePhase in
//                if scenePhase == .active {
//                    applyColorMode()
//                }
//            }
//#endif
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
            
#if os(iOS)
            if !isLoading {
                try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.5))
                try? await excalidrawCore.toggleToolbarAction(key: "h")
            }
#endif
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
        } else if let newFile {
            excalidrawCore.loadFile(from: newFile)
        }
    }
    
    // MARK: - Settings Application
    
    private func applyAllSettings() {
        applyFonts()
        applyColorMode()
        applyImageInversion()
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
    
    private func applyColorMode() {
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
    
    private func applyImageInversion() {
        guard loadingState == .loaded, scenePhase == .active else { return }

        Task {
            do {
                let shouldInvert = appPreference.autoInvertImage &&
                (appPreference.excalidrawAppearance == .dark ||
                 (colorScheme == .dark && appPreference.excalidrawAppearance == .auto))

                try await excalidrawCore.applyAntiInvertImageSettings(
                    payload: appPreference.antiInvertImageSettings
                )
                try await excalidrawCore.toggleInvertImageSwitch(autoInvert: shouldInvert)
            } catch {
                onError(error)
            }
        }
    }
}


/// Minimal wrapper to bridge WKWebView to SwiftUI
struct ExcalidrawViewRepresentable {
    @EnvironmentObject private var core: ExcalidrawCore
    
    func makeExcalidrawWebView(context: Context) -> ExcalidrawWebView {
        return context.coordinator.webView
    }
    
    func updateExcalidrawWebView(_ webView: ExcalidrawWebView, context: Context) {
    }
    
    func makeCoordinator() -> ExcalidrawCore {
        return core
    }
}

#if os(macOS)
extension ExcalidrawViewRepresentable: NSViewRepresentable {
    
    func makeNSView(context: Context) -> ExcalidrawWebView {
        makeExcalidrawWebView(context: context)
    }
    
    func updateNSView(_ nsView: ExcalidrawWebView, context: Context) {
        updateExcalidrawWebView(nsView, context: context)
    }
}
#elseif os(iOS)
extension ExcalidrawViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> ExcalidrawWebView {
        makeExcalidrawWebView(context: context)
    }
    
    func updateUIView(_ uiView: ExcalidrawWebView, context: Context) {
        updateExcalidrawWebView(uiView, context: context)
    }
}
#endif
