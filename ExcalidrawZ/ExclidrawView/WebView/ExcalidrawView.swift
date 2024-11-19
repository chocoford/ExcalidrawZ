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
    var shouldHandleInput = false
    var toolbarActionHandler: (Int) -> Void
    var toolbarActionHandler2: (Character) -> Void
    
    init(
        frame: CGRect,
        configuration: WKWebViewConfiguration,
        toolbarActionHandler: @escaping (Int) -> Void,
        toolbarActionHandler2: @escaping (Character) -> Void
    ) {
        self.toolbarActionHandler = toolbarActionHandler
        self.toolbarActionHandler2 = toolbarActionHandler2
        super.init(frame: frame, configuration: configuration)
#if canImport(UIKit)
        self.scrollView.isScrollEnabled = false
#endif
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
#if canImport(UIKit)
    override var safeAreaInsets: UIEdgeInsets {
//        .init(top: 0, left: 0, bottom: -40, right: 0)
        .zero
    }
#endif
    
    
#if canImport(AppKit)
    override func keyDown(with event: NSEvent) {
        if shouldHandleInput,
           let char = event.characters {
            if let num = Int(char), num >= 0, num <= 9 {
                self.toolbarActionHandler(num)
            } else if ExcalidrawTool.allCases.compactMap({$0.keyEquivalent}).contains(where: {$0 == Character(char)}) {
                self.toolbarActionHandler2(Character(char))
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
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var exportState: ExportState
    @EnvironmentObject var toolState: ToolState

    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "WebView"
    )
    
    @Binding var file: ExcalidrawFile
    @Binding var isLoading: Bool
    
    var savingType: UTType
    
    var onError: (Error) -> Void
    
    // TODO: isLoadingFile is not used yet.
    init(
        file: Binding<ExcalidrawFile>,
        savingType: UTType = .excalidrawFile,
        isLoadingPage: Binding<Bool>,
        isLoadingFile: Binding<Bool>? = nil,
        onError: @escaping (Error) -> Void
    ) {
        self._file = file
        self.savingType = savingType
        self._isLoading = isLoadingPage
        self.onError = onError
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

#if os(macOS)
extension ExcalidrawView: NSViewRepresentable {

    func makeNSView(context: Context) -> ExcalidrawWebView {
        DispatchQueue.main.async {
            cancellables.insert(
                context.coordinator.$isLoading.sink { newValue in
                    DispatchQueue.main.async {
                        self.isLoading = newValue
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
    
    func updateNSView(_ nsView: ExcalidrawWebView, context: Context) {
        let webView = context.coordinator.webView
        context.coordinator.parent = self
        exportState.excalidrawWebCoordinator = context.coordinator
        fileState.excalidrawWebCoordinator = context.coordinator
        toolState.excalidrawWebCoordinator = context.coordinator
        guard !webView.isLoading, !isLoading else { return }
        Task {
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
                    try await context.coordinator.toggleInvertImageSwitch(autoInvert: true)
                } else {
                    try await context.coordinator.toggleInvertImageSwitch(autoInvert: false)
                }
            } catch {
                self.onError(error)
            }
        }
        context.coordinator.loadFile(from: file)
        if context.coordinator.lastTool != toolState.activatedTool {
            Task {
                do {
                    if let rawValue = toolState.activatedTool?.rawValue {
                        if rawValue < 10 {
                            try await context.coordinator.toggleToolbarAction(key: rawValue)
                        } else if let keyEquivalent = toolState.activatedTool?.keyEquivalent {
                            try await context.coordinator.toggleToolbarAction(key: keyEquivalent)
                        }
                        context.coordinator.lastTool = toolState.activatedTool
                    }
                } catch {
                    self.onError(error)
                }
            }
        }
    }

    func makeCoordinator() -> ExcalidrawCore {
        ExcalidrawCore(self)
    }
}
#elseif os(iOS)
extension ExcalidrawView: UIViewRepresentable {
    func makeUIView(context: Context) -> ExcalidrawWebView {
        DispatchQueue.main.async {
            cancellables.insert(
                context.coordinator.$isLoading.sink { newValue in
                    DispatchQueue.main.async {
                        self.isLoading = newValue
                        if !newValue, horizontalSizeClass == .compact {
                            Task { @MainActor in
                                try? await context.coordinator.toggleToolbarAction(key: "h")
                            }
                        }
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
    
    func updateUIView(_ uiView: ExcalidrawWebView, context: Context) {
        let webView = context.coordinator.webView
        context.coordinator.parent = self
        exportState.excalidrawWebCoordinator = context.coordinator
        fileState.excalidrawWebCoordinator = context.coordinator
        toolState.excalidrawWebCoordinator = context.coordinator
        guard !webView.isLoading, !isLoading else { return }
        Task {
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
                    try await context.coordinator.toggleInvertImageSwitch(autoInvert: true)
                } else {
                    try await context.coordinator.toggleInvertImageSwitch(autoInvert: false)
                }
            } catch {
                self.onError(error)
            }
        }
        context.coordinator.loadFile(from: file)
        
        
        if !toolState.inDragMode,
           context.coordinator.lastTool != toolState.activatedTool {
            Task {
                do {
                    if let rawValue = toolState.activatedTool?.rawValue {
                        if rawValue < 10 {
                            try await context.coordinator.toggleToolbarAction(key: rawValue)
                        } else if let keyEquivalent = toolState.activatedTool?.keyEquivalent {
                            try await context.coordinator.toggleToolbarAction(key: keyEquivalent)
                        }
                        context.coordinator.lastTool = toolState.activatedTool
                    }
                } catch {
                    self.onError(error)
                }
            }
        }
    }
    
    func makeCoordinator() -> ExcalidrawCore {
        ExcalidrawCore(
            self
        )
    }
}
#endif
