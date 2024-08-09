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

struct ExcalidrawWebView {
    @Environment(\.colorScheme) var colorScheme
    
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var exportState: ExportState

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebView")
    
    @Binding var isLoading: Bool
    
    var onError: (Error) -> Void
    
    init(isLoading: Binding<Bool>, onError: @escaping (Error) -> Void) {
        self._isLoading = isLoading
        self.onError = onError
    }
}

#if os(macOS)
extension ExcalidrawWebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    func makeNSView(context: Context) -> WKWebView {
        return context.coordinator.webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let webView = context.coordinator.webView
        context.coordinator.parent = self
        exportState.excalidrawWebCoordinator = context.coordinator
        
        guard !webView.isLoading else { return }
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
        }
        Task {
            do {
                try await context.coordinator.loadFile(from: fileState.currentFile)
            } catch {
                self.onError(error)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

#elseif os(iOS)

#endif
