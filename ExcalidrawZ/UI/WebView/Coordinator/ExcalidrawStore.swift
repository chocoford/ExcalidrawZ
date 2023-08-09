//
//  WebViewCoordinator.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import SwiftUI
import WebKit
import ComposableArchitecture

import OSLog
extension ExcalidrawWebView {
    class Coordinator: NSObject, ObservableObject {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ExcalidrawWebViewCoordinator")
        
        var parent: ExcalidrawWebView
        var webView: WKWebView = .init()
        
        init(_ parent: ExcalidrawWebView) {
            self.parent = parent
            super.init()
            self.configWebView()
        }
        
        var downloadCache: [String : Data] = [:]
        var downloads: [URLRequest : URL] = [:]
        
        var previousFileID: UUID? = nil
        private var lastVersion: Int = 0
        
        func configWebView() {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
//            if let url = Bundle.main.url(forResource: "webViewTools", withExtension: "js"),
//               let script = try? String(contentsOf: url) {
//                let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
//                config.userContentController.addUserScript(userScript)
//            }
            config.userContentController.add(self, name: "excalidrawZ")
            
            self.webView = WKWebView(frame: .zero, configuration: config)
            if #available(macOS 13.3, *) {
                self.webView.isInspectable = true
            } else {
            }
            
            self.webView.navigationDelegate = self
            self.webView.uiDelegate = self
            
//            self.webView.load(.init(url: URL(string: "https://excalidraw.com")!))
            
            let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "excalidrawCore")!
            print(url, url.deletingLastPathComponent())
            DispatchQueue.main.async {
                self.webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }
    }
}

/// Keep stateless
extension ExcalidrawWebView.Coordinator {
    @MainActor
    func loadFile(from file: File?) async throws {
        if self.webView.isLoading { return }
        guard let file = file, let data = file.content else { return }
        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        try await self.webView.evaluateJavaScript("window.excalidrawZHelper.loadFile(\(buffer)); 0;")
    }
    
    /// Load current `File`.
    ///
    /// This function will simulate the *file drop* operation to `excalidraw.com`.
    /// It evaluates `javascript` code that dispatch `DragEvent` to the specific `HTMLElement`.
//    @MainActor
//    func loadCurrentFile() async {
//        self.previousFileID = state.currentFile.id
//        logger.info("loadCurrentFile: \(state.currentFile.name ?? "nil")")
//        
//        do {
//            try? await self.loadFile(from: state.currentFile)
//            try await Task.sleep(nanoseconds: 1 * 10^6)
//            self.parent.store.send(.delegate(.onFinishLoading))
//        } catch {
//            dump(error)
//        }
//    }
    
    /// Save `currentFile` or creating if neccessary.
    ///
    /// This function will get the local storage of `excalidraw.com`.
    /// Then it will set the data got from local storage to `currentFile`.
    @MainActor
    func saveCurrentFile() async throws {
        let _ = try await self.webView.evaluateJavaScript("window.excalidrawZHelper.saveFile(); 0;")
    }
    
    /// `true` if is dark mode.
    @MainActor
    func getIsDark() async throws -> Bool {
        if self.webView.isLoading { return false }
        let res = try await self.webView.evaluateJavaScript("window.excalidrawZHelper.getIsDark()")
        if let isDark = res as? Bool {
            return isDark
        } else {
            return false
        }
    }
    
//    @MainActor
//    func saveTheme() async throws {
//        let isExcalidrawDark = try await getIsDark()
//        let isAppDark = self.parent.colorScheme == .dark
//        let isSameTheme = isExcalidrawDark && isAppDark || !isExcalidrawDark && !isAppDark
//        if !isSameTheme {
//            self.parent.appearance = isExcalidrawDark ? .dark : .light
//            self.parent.loading = true
//            /// without reload will lead to wierd blank view.
//            webView.reload()
//        }
//    }
    
    @MainActor
    func changeColorMode(dark: Bool) async throws {
        if self.webView.isLoading { return }
        let isDark = try await getIsDark()
        guard isDark != dark else { return }
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleColorTheme(\"\(dark ? "dark" : "light")\"); 0;")
    }
    
    @MainActor
    func exportPNG() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.exportImage(); 0;")
    }
}
