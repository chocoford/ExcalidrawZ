//
//  WebViewCoordinator.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import SwiftUI
import WebKit

import OSLog

import SVGView

extension ExcalidrawView {
    class Coordinator: NSObject {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ExcalidrawWebViewCoordinator")
        
        var parent: ExcalidrawView
        var webView: ExcalidrawWebView = .init(frame: .zero, configuration: .init()) { _ in } toolbarActionHandler2: { _ in }
        lazy var webActor = ExcalidrawWebActor(coordinator: self)
                
        init(_ parent: ExcalidrawView) {
            self.parent = parent
            super.init()
            self.configWebView()
        }
        
        var downloadCache: [String : Data] = [:]
        var downloads: [URLRequest : URL] = [:]
        var flyingBlobsRequest: [String : (String) -> Void] = [:]
        var flyingSVGRequests: [String : (String) -> Void] = [:]
        
        var previousFileID: UUID? = nil
        private var lastVersion: Int = 0
        
        internal var lastTool: ExcalidrawTool?
        
        func configWebView() {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            
            let userContentController = WKUserContentController()
                        
            userContentController.add(self, name: "excalidrawZ")
            
            config.userContentController = userContentController
            
            self.webView = ExcalidrawWebView(frame: .zero, configuration: config) { num in
                Task {
                    try? await self.toggleToolbarAction(key: num)
                }
            } toolbarActionHandler2: { char in
                Task {
                    try? await self.toggleToolbarAction(key: char)
                }
            }
            if #available(macOS 13.3, *) {
                self.webView.isInspectable = true
            } else {
            }
            
            self.webView.navigationDelegate = self
            self.webView.uiDelegate = self
            
            DispatchQueue.main.async {
#if DEBUG
                self.webView.load(URLRequest(url: URL(string: "http://localhost:8486/index.html")!))
#else
                self.webView.load(URLRequest(url: URL(string: "http://localhost:8487/index.html")!))
#endif
            }
        }
    }
}

actor ExcalidrawWebActor {
    var excalidrawCoordinator: ExcalidrawView.Coordinator
    
    init(coordinator: ExcalidrawView.Coordinator) {
        self.excalidrawCoordinator = coordinator
    }
    
    var loadedFileID: File.ID?
    var webView: ExcalidrawWebView { excalidrawCoordinator.webView }
    
    func loadFile(id: File.ID, data: Data, force: Bool = false) async throws {
        let webView = webView
        guard loadedFileID != id || force else { return }
        self.loadedFileID = id
        let startDate = Date()
        print("Load file<\(String(describing: id)), \(data.count)>, force: \(force), Thread: \(Thread().description)")
        var buffer = [UInt8].init(repeating: 0, count: data.count)
        data.copyBytes(to: &buffer, count: data.count)
        let buf = buffer
        await MainActor.run {
            webView.evaluateJavaScript("window.excalidrawZHelper.loadFile(\(buf)); 0;")
        }
        print("load file done. time cost", Date.now.timeIntervalSince(startDate))
    }
}

/// Keep stateless
extension ExcalidrawView.Coordinator {
    
    func loadFile(from file: File?, force: Bool = false) {
        guard !self.parent.isLoading else { return }
        guard let fileID = file?.id,
            let data = file?.content else { return }
        Task.detached {
            do {
                try await self.webActor.loadFile(id: fileID, data: data, force: force)
            } catch {
                await self.parent.onError(error)
            }
        }
        
//        try await withThrowingTaskGroup(of: Bool.self) { taskGroup in
//            taskGroup.addTask {
//                try await self.webActor.loadFile(from: file, force: force)
//                return true
//            }
//            
//            taskGroup.addTask {
//                try await Task.sleep(nanoseconds: UInt64(50 * 1e+6))
//                if (file?.content?.count ?? 0) > 500000 {
//                    await MainActor.run {
//                        print("setting self.parent.isLoadingFile = true")
//                        self.parent.isLoadingFile = true
//                    }
//                }
//                return false
//            }
//            
//            if try await taskGroup.next() == true {
//                taskGroup.cancelAll()
//            } else {
//                try await taskGroup.waitForAll()
//            }
//        }
//        
//        if await self.parent.isLoadingFile {
//            await MainActor.run {
//                self.parent.isLoadingFile = false
//            }
//        }
        
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
    
    @MainActor
    func toggleToolbarAction(key: Int) async throws {
        print(#function)
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction(\(key)); 0;")
    }
    @MainActor
    func toggleToolbarAction(key: Character) async throws {
        print(#function)
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('\(key.uppercased())'); 0;")
    }
    
    func exportElementsToPNG(id: String, elements: [ExcalidrawElement]) async throws -> NSImage {
        let script = try "window.excalidrawZHelper.exportElementsToBlob('\(id)', \(elements.jsonStringified())); 0;"
        self.logger.debug("\(#function), script:\n\(script)")
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
        let dataString: String = await withCheckedContinuation { continuation in
            self.flyingBlobsRequest[id] = { data in
                continuation.resume(returning: data)
                self.flyingBlobsRequest.removeValue(forKey: id)
            }
        }
        guard let data = Data(base64Encoded: dataString),
              let image = NSImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
        
    }
    
    func exportElementsToSVG(id: String, elements: [ExcalidrawElement]) async throws -> NSImage {
        let script = try "window.excalidrawZHelper.exportElementsToSvg('\(id)', \(elements.jsonStringified())); 0;"
        self.logger.debug("\(#function), script:\n\(script)")
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
        let dataString: String = await withCheckedContinuation { continuation in
            self.flyingSVGRequests[id] = { data in
                continuation.resume(returning: data)
                self.flyingSVGRequests.removeValue(forKey: id)
            }
        }
        guard let data = Data(base64Encoded: dataString),
              let image = NSImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
        
    }
}
