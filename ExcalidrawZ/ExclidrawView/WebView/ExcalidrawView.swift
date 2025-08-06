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
import OSLog
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

struct ExcalidrawView {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    @AppStorage("addedFontsData") private var addedFontsData: Data = Data()
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var exportState: ExportState
    @EnvironmentObject var toolState: ToolState

    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "WebView"
    )
    
    var roomIDBinding: Binding<String>?
    @Binding var file: ExcalidrawFile?
    
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
    @Binding var loadingState: LoadingState
    
    var savingType: UTType
    var onError: (Error) -> Void
    
    var interactionEnabled: Bool
    
    enum ExcalidrawType {
        case normal
        case collaboration
    }
    var type: ExcalidrawType
    
    // TODO: isLoadingFile is not used yet.
    init(
        type: ExcalidrawType = .normal,
        roomID: Binding<String>? = nil,
        file: Binding<ExcalidrawFile?>,
        savingType: UTType = .excalidrawFile,
        loadingState: Binding<LoadingState>,
        interactionEnabled: Bool = true,
        onError: @escaping (Error) -> Void
    ) {
        self.type = type
        self.roomIDBinding = roomID
        self._file = file
        self.savingType = savingType
        self._loadingState = loadingState
        self.interactionEnabled = interactionEnabled
        self.onError = onError
    }
    
    var addedFonts: [String] {
        (try? JSONDecoder().decode([String].self, from: addedFontsData)) ?? []
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

extension ExcalidrawView {
    func makeExcalidrawWebView(context: Context) -> ExcalidrawWebView {
        DispatchQueue.main.async {
            cancellables.insert(
                context.coordinator.$isLoading.sink { newValue in
                    DispatchQueue.main.async {
                        self.loadingState = newValue ? .loading : .loaded
#if os(iOS)
                        if !newValue/*, horizontalSizeClass == .compact*/ {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.5))
                                try? await context.coordinator.toggleToolbarAction(key: "h")
                            }
                        }
#endif
                    }
                }
            )
            Task {
                for await error in context.coordinator.errorStream {
                    self.onError(error)
                }
            }
        }
        return context.coordinator.webView
    }
    
    func updateExcalidrawWebView(_ webView: ExcalidrawWebView, context: Context) {
        
        Task {
            try? await context.coordinator.toggleWebPointerEvents(enabled: interactionEnabled)
        }
        context.coordinator.parent = self
        // Move to `ContentViewDetail`
        if self.interactionEnabled {
            toolState.excalidrawWebCoordinator = context.coordinator
        }
        switch self.type {
            case .normal:
                exportState.excalidrawWebCoordinator = context.coordinator
                fileState.excalidrawWebCoordinator = context.coordinator
                // toolState.excalidrawWebCoordinator = context.coordinator
            case .collaboration:
                if self.interactionEnabled {
                    exportState.excalidrawCollaborationWebCoordinator = context.coordinator
                    fileState.excalidrawCollaborationWebCoordinator = context.coordinator
                }
        }
        guard !webView.isLoading, case .loaded = loadingState else { return }
        Task {
            // inject fonts
            do {
                let fontFamilies = addedFonts
                try await context.coordinator.setAvailableFonts(fontFamilies: fontFamilies)
            } catch {
                self.onError(error)
            }
            
            do {
                if appPreference.excalidrawAppearance == .auto {
                    try await context.coordinator.changeColorMode(dark: colorScheme == .dark)
                } else {
                    try await context.coordinator.changeColorMode(dark: appPreference.excalidrawAppearance.colorScheme ?? colorScheme == .dark)
                }
            } catch {
                self.onError(error)
            }
            do {
                if appPreference.autoInvertImage,
                   appPreference.excalidrawAppearance == .dark || colorScheme == .dark && appPreference.excalidrawAppearance == .auto {
                    try await context.coordinator.applyAntiInvertImageSettings(payload: appPreference.antiInvertImageSettings)
                    try await context.coordinator.toggleInvertImageSwitch(autoInvert: true)
                } else {
                    try await context.coordinator.applyAntiInvertImageSettings(payload: appPreference.antiInvertImageSettings)
                    try await context.coordinator.toggleInvertImageSwitch(autoInvert: false)
                }
            } catch {
                self.onError(error)
            }
        }
        if type == .collaboration {
            if file?.roomID?.isEmpty == false {
                // has roomID
            } else {
                // context.coordinator.loadFile(from: file)
            }
        } else if let file {
            context.coordinator.loadFile(from: file)
        }
    }
    
    func makeCoordinator() -> ExcalidrawCore {
        ExcalidrawCore(self)
    }
}

#if os(macOS)
extension ExcalidrawView: NSViewRepresentable {

    func makeNSView(context: Context) -> ExcalidrawWebView {
        makeExcalidrawWebView(context: context)
    }
    
    func updateNSView(_ nsView: ExcalidrawWebView, context: Context) {
        updateExcalidrawWebView(nsView, context: context)
    }
}
#elseif os(iOS)
extension ExcalidrawView: UIViewRepresentable {
    func makeUIView(context: Context) -> ExcalidrawWebView {
        makeExcalidrawWebView(context: context)
    }
    
    func updateUIView(_ uiView: ExcalidrawWebView, context: Context) {
        updateExcalidrawWebView(uiView, context: context)
    }
}
#endif
