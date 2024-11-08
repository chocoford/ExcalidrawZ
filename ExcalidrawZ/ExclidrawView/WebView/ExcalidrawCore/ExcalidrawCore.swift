//
//  WebViewCoordinator.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import SwiftUI
import WebKit
import OSLog
import Combine

import SVGView

class ExcalidrawCore: NSObject, ObservableObject {
#if canImport(AppKit)
    typealias PlatformImage = NSImage
#elseif canImport(UIKit)
    typealias PlatformImage = UIImage
#endif
    
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ExcalidrawCore")
    
    var parent: ExcalidrawView?
    lazy var errorStream: AsyncStream<Error> = {
        AsyncStream { continuation in
            publishError = {
                continuation.yield($0)
            }
        }
    }()
    internal var publishError: (_ error: Error) -> Void
    var webView: ExcalidrawWebView = .init(frame: .zero, configuration: .init()) { _ in } toolbarActionHandler2: { _ in }
    lazy var webActor = ExcalidrawWebActor(coordinator: self)
    
    init(_ parent: ExcalidrawView?) {
        self.parent = parent
        self.publishError = { error in }
        super.init()
        self.configWebView()
        
        Publishers.CombineLatest($isNavigating, $isDocumentLoaded)
            .map { isNavigating, isDocumentLoaded in
                isNavigating || !isDocumentLoaded
            }
            .assign(to: &$isLoading)
    }
    
    @Published var isNavigating = true
    @Published var isDocumentLoaded = false
    @Published private(set) var isLoading: Bool = false // { isNavigating || !isDocumentLoaded }
    
    var downloadCache: [String : Data] = [:]
    var downloads: [URLRequest : URL] = [:]
    
    let blobRequestQueue = DispatchQueue(label: "BlobRequestQueue", qos: .background)
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
        
        do {
            let consoleHandlerScript = try WKUserScript(
                source: String(
                    contentsOf: Bundle.main.url(forResource: "overwrite_console", withExtension: "js")!,
                    encoding: .utf8
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(consoleHandlerScript)
            userContentController.add(self, name: "consoleHandler")
            logger.info("Enable console handler.")
        } catch {
            logger.error("Config consoleHandler failed: \(error)")
        }
        
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
        if #available(macOS 13.3, iOS 16.4, *) {
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

/// Keep stateless
extension ExcalidrawCore {
    func loadFile(from file: ExcalidrawFile?, force: Bool = false) {
        guard !self.isLoading, !self.webView.isLoading else { return }
        guard let file = file,
              let data = file.content else { return }
        Task.detached {
            do {
                try await self.webActor.loadFile(id: file.id, data: data, force: force)
            } catch {
                self.publishError(error)
            }
        }
    }
    
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
    func loadLibraryItem(item: ExcalidrawLibrary) async throws {
        try await self.webView.evaluateJavaScript("window.excalidrawZHelper.loadLibraryItem(\(item.jsonStringified())); 0;")
    }
    
    @MainActor
    func exportPNG() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.exportImage(); 0;")
    }
    
    func exportPNGData() async throws -> Data? {
        guard let file = await self.parent?.file else {
            return nil
        }
        let imageData = try await self.exportElementsToPNGData(elements: file.elements)
        return imageData //NSImage(data: imageData)
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
    
    func exportElementsToPNGData(elements: [ExcalidrawElement], embedScene: Bool = false) async throws -> Data {
        let id = UUID().uuidString
        let script = try "window.excalidrawZHelper.exportElementsToBlob('\(id)', \(elements.jsonStringified()), \(embedScene)); 0;"
        self.logger.debug("\(#function), script:\n\(script)")
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
        let dataString: String = await withCheckedContinuation { continuation in
            blobRequestQueue.async {
                self.flyingBlobsRequest[id] = { data in
                    continuation.resume(returning: data)
                    self.flyingBlobsRequest.removeValue(forKey: id)
                }
            }
        }
        guard let data = Data(base64Encoded: dataString) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
    }
    
    func exportElementsToPNG(elements: [ExcalidrawElement], embedScene: Bool = false) async throws -> PlatformImage {
        let data = try await self.exportElementsToPNGData(elements: elements, embedScene: embedScene)
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
    }
    
    
    func exportElementsToSVGData(elements: [ExcalidrawElement], embedScene: Bool = false) async throws -> Data {
        let id = UUID().uuidString
        let script = try "window.excalidrawZHelper.exportElementsToSvg('\(id)', \(elements.jsonStringified()), \(embedScene)); 0;"
        self.logger.debug("\(#function)")
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
        let svg: String = await withCheckedContinuation { continuation in
            self.flyingSVGRequests[id] = { svg in
                continuation.resume(returning: svg)
                self.flyingSVGRequests.removeValue(forKey: id)
            }
        }
        var miniizedSvg = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "<defs[^>]*>.*?</defs>"
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(location: 0, length: svg.utf16.count)
            miniizedSvg = regex.stringByReplacingMatches(in: svg, options: [], range: range, withTemplate: "")
        } catch {
            print("Invalid regex: \(error.localizedDescription)")
        }

        guard let data = miniizedSvg.data(using: .utf8) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
        
    }
    func exportElementsToSVG(elements: [ExcalidrawElement], embedScene: Bool = false) async throws -> PlatformImage {
        let data = try await exportElementsToSVGData(elements: elements, embedScene: embedScene)
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
        
    }
}
