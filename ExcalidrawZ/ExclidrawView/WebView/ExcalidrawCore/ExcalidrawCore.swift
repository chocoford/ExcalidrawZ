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

typealias CollaborationInfo = ExcalidrawCore.CollaborationInfo

actor ExportImageManager {
    var flyingRequests: [String : (String) -> Void] = [:]
    
    public func requestExport(id: String) async -> String {
        await withCheckedContinuation { continuation in
            self.flyingRequests[id] = { data in
                continuation.resume(returning: data)
            }
        }
    }
    
    public func responseExport(id: String, blobString: String) {
        self.flyingRequests[id]?(blobString)
    }
}
actor AllMediaTransferManager {
    var flyingRequests: [String : ([ExcalidrawFile.ResourceFile]) -> Void] = [:]
    
    public func requestExport(id: String) async -> [ExcalidrawFile.ResourceFile] {
        await withCheckedContinuation { continuation in
            self.flyingRequests[id] = { data in
                continuation.resume(returning: data)
            }
        }
    }
    
    public func responseExport(id: String, resourceFiles: [ExcalidrawFile.ResourceFile]) {
        self.flyingRequests[id]?(resourceFiles)
    }
}

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
    var webView: ExcalidrawWebView = .init(frame: .zero, configuration: .init()) { _ in }
    lazy var webActor = ExcalidrawWebActor(coordinator: self)
    
    init(_ parent: ExcalidrawView?) {
        self.parent = parent
        self.publishError = { error in }
        super.init()
        self.configWebView()
        
        switch parent?.type {
            case .normal:
                Publishers.CombineLatest($isNavigating, $isDocumentLoaded)
                    .map { isNavigating, isDocumentLoaded in
                        isNavigating || !isDocumentLoaded
                    }
                    .assign(to: &$isLoading)
            case .collaboration:
                Publishers.CombineLatest(
                    Publishers.CombineLatest($isNavigating, $isDocumentLoaded)
                        .map { $0 || !$1 },
                    $isCollabEnabled
                )
                .map { $0 || !$1 }
                .assign(to: &$isLoading)
            default:
                break
        }
    }
    
    @Published var isNavigating = true
    @Published var isDocumentLoaded = false
    @Published var isCollabEnabled = false
    @Published private(set) var isLoading: Bool = false
    
    var downloadCache: [String : Data] = [:]
    var downloads: [URLRequest : URL] = [:]
    
    let blobRequestQueue = DispatchQueue(label: "BlobRequestQueue", qos: .background)
    var exportImageManager = ExportImageManager()
    var allMediaTransferManager = AllMediaTransferManager()
    
    @Published var canUndo = false
    @Published var canRedo = false
    
    var previousFileID: UUID? = nil
    private var lastVersion: Int = 0
    
    var hasInjectIndexedDBData = false
    
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
        
//        
//        do {
//            let jsCode = """
//            (function() {
//                const originalWindowOpen = window.open;
//                window.open = function(url, name, features) {
//                    console.log(url);
//                    if (!url || url.trim() === "") {
//                        console.log("拦截到空 URL 的 window.open 调用");
//
//                        return null;
//                    }
//                    return originalWindowOpen.call(window, url, name, features);
//                };
//            })();
//            """
//            let openURLHandlerScript = WKUserScript(
//                source: jsCode,
//                injectionTime: .atDocumentStart,
//                forMainFrameOnly: false
//            )
//            userContentController.addUserScript(openURLHandlerScript)
//            userContentController.add(self, name: "openURLHandler")
//        } catch {
//            logger.error("Config openURLHandler failed: \(error)")
//        }
        
        config.userContentController = userContentController
        
        self.webView = ExcalidrawWebView(
            frame: .zero,
            configuration: config
        ) { key in
            switch key {
                case .number(let int):
                    Task {
                        try? await self.toggleToolbarAction(key: int)
                    }
                case .char(let character):
                    Task {
                        try? await self.toggleToolbarAction(key: character)
                    }
                case .space:
                    Task {
                        try? await self.toggleToolbarAction(key: " ")
                    }
                case .escape:
                    Task {
                        try? await self.toggleToolbarAction(key: "\u{1B}")
                    }
            }
        }
#if DEBUG
        if #available(macOS 13.3, iOS 16.4, *) {
            self.webView.isInspectable = true
        } else {
        }
#endif
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        
#if os(iOS)
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        self.webView.addInteraction(pencilInteraction)
#endif
        
        DispatchQueue.main.async {
            self.refresh()
        }
    }
    
    public func refresh() {
        let request: URLRequest
        switch self.parent?.type {
            case .normal:
#if DEBUG
                request = URLRequest(url: URL(string: "http://127.0.0.1:8486/index.html")!)
#else
                request = URLRequest(url: URL(string: "http://127.0.0.1:8487/index.html")!)
#endif
                self.webView.load(request)
            case .collaboration:
                var url = Secrets.shared.collabURL
                if let roomID = self.parent?.file?.roomID,
                   !roomID.isEmpty {
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    components?.fragment = "room=\(roomID)"
                    if let newURL = components?.url {
                        url = newURL
                    }
                    self.isCollabEnabled = true
                }
                request = URLRequest(url: url)
                self.logger.info("[ExcalidrawCore] navigate to \(url), roomID: \(String(describing: self.parent?.file?.roomID))")
                self.webView.load(request)
            case nil:
                break
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
    
    @MainActor
    func changeColorMode(dark: Bool) async throws {
        if self.webView.isLoading { return }
        let isDark = try await getIsDark()
        guard isDark != dark else { return }
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleColorTheme(\"\(dark ? "dark" : "light")\"); 0;")
    }
    
    /// Make Image be the same as light mode.
    /// autoInvert: Invert the current inverted image in dark mode.
    @MainActor
    func toggleInvertImageSwitch(autoInvert: Bool) async throws {
        if self.webView.isLoading { return }
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleImageInvertSwitch(\(autoInvert)); 0;")
    }
    @MainActor
    func applyAntiInvertImageSettings(payload: AntiInvertImageSettings) async throws {
        if self.webView.isLoading { return }
        let payload = try payload.jsonStringified()
        // print("[applyAntiInvertImageSettings] payload: ", payload)
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleAntiInvertImageSettings(\(payload)); 0;")
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
        let imageData = try await self.exportElementsToPNGData(elements: file.elements, colorScheme: .light)
        return imageData //NSImage(data: imageData)
    }
    
    @MainActor
    func toggleToolbarAction(key: Int) async throws {
        print(#function, key)
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction(\(key)); 0;")
    }
    
    @MainActor
    func toggleToolbarAction(key: Character) async throws {
        guard !self.isLoading else { return }
        print(#function, key)
        if key == "\u{1B}" {
            try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('Escape'); 0;")
        } else if key == " " {
            try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('Space'); 0;")
        } else {
            try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('\(key.uppercased())'); 0;")
        }
    }
    
    @MainActor
    func toggleDeleteAction() async throws {
        guard !self.isLoading else { return }
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('Backspace'); 0;")
    }
    
    enum ExtraTool: String {
        case webEmbed = "webEmbed"
        case text2Diagram = "text2diagram"
        case mermaid = "mermaid"
        case magicFrame = "wireframe"
    }
    @MainActor
    func toggleToolbarAction(tool: ExtraTool) async throws {
        guard !self.isLoading else { return }
        print(#function, tool)
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleToolbarAction('\(tool.rawValue)'); 0;")
    }
    
    func exportElementsToPNGData(
        elements: [ExcalidrawElement],
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> Data {
        let id = UUID().uuidString
        let script = try "window.excalidrawZHelper.exportElementsToBlob('\(id)', \(elements.jsonStringified()), \(embedScene), \(withBackground), \(colorScheme == .dark)); 0;"
        self.logger.debug("\(#function), script:\n\(script)")
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
//        let dataString: String = await withCheckedContinuation { continuation in
//            blobRequestQueue.async {
//                self.flyingBlobsRequest[id] = { data in
//                    continuation.resume(returning: data)
//                    self.flyingBlobsRequest.removeValue(forKey: id)
//                }
//            }
//        }
        let dataString = await exportImageManager.requestExport(id: id)
        guard let data = Data(base64Encoded: dataString) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
    }
    
    func exportElementsToPNG(
        elements: [ExcalidrawElement],
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> PlatformImage {
        let data = try await self.exportElementsToPNGData(
            elements: elements,
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme
        )
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
    }
    
    func exportElementsToSVGData(
        elements: [ExcalidrawElement],
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> Data {
        let id = UUID().uuidString
        let script = try "window.excalidrawZHelper.exportElementsToSvg('\(id)', \(elements.jsonStringified()), \(embedScene), \(withBackground), \(colorScheme == .dark)); 0;"
        self.logger.debug("\(#function)")
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript(script)
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
        let svg = await exportImageManager.requestExport(id: id)
        let minisizedSvg = removeWidthAndHeight(from: svg).trimmingCharacters(in: .whitespacesAndNewlines)
        
        func removeWidthAndHeight(from svgContent: String) -> String {
            // 正则表达式确保匹配 `<svg>` 标签上的 width 和 height 属性
            let regexPattern = #"<svg([^>]*)\s+(width="[^"]*")\s*([^>]*)>"#
            
            do {
                // 创建正则表达式
                let regex = try NSRegularExpression(pattern: regexPattern, options: [])
                
                // 替换 `width` 和 `height`，保留 `<svg>` 标签其他属性
                let tempResult = regex.stringByReplacingMatches(
                    in: svgContent,
                    options: [],
                    range: NSRange(location: 0, length: svgContent.utf16.count),
                    withTemplate: "<svg$1 $3>"
                )
                
                // 再次处理可能分开的 height
                let finalRegexPattern = #"<svg([^>]*)\s+(height="[^"]*")\s*([^>]*)>"#
                let finalResult = try NSRegularExpression(pattern: finalRegexPattern, options: []).stringByReplacingMatches(
                    in: tempResult,
                    options: [],
                    range: NSRange(location: 0, length: tempResult.utf16.count),
                    withTemplate: "<svg$1 $3>"
                )
                
                return finalResult
            } catch {
                print("Error creating regex: \(error)")
                return svgContent
            }
        }
        
        guard let data = minisizedSvg.data(using: .utf8) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
        
    }
    func exportElementsToSVG(
        elements: [ExcalidrawElement],
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> PlatformImage {
        let data = try await exportElementsToSVGData(
            elements: elements,
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme
        )
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
        
    }
    
    /// Get Excadliraw Indexed DB Data
    func getExcalidrawStore() async throws -> [ExcalidrawFile.ResourceFile] {
        print(#function)
        
        let id = UUID().uuidString
        
        Task { @MainActor in
            do {
                try await webView.evaluateJavaScript("window.excalidrawZHelper.getAllMedias('\(id)'); 0;")
            } catch {
                self.logger.error("\(String(describing: error))")
            }
        }
        
        let files: [ExcalidrawFile.ResourceFile] = await allMediaTransferManager.requestExport(id: id)
        return files
    }
    
    /// Insert media files to IndexedDB
    @MainActor
    func insertMediaFiles(_ files: [ExcalidrawFile.ResourceFile]) async throws {
        print("insertMediaFiles: \(files.count)")
        let jsonStringified = try files.jsonStringified()
        try await webView.evaluateJavaScript("window.excalidrawZHelper.insertMedias('\(jsonStringified)'); 0;")
    }
    
    @MainActor
    func performUndo() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.undo(); 0;")
    }
    @MainActor
    func performRedo() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.redo(); 0;")
    }
    @MainActor
    func connectPencil(enabled: Bool) async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.connectPencil(\(enabled)); 0;")
    }
    @MainActor
    func togglePenMode(enabled: Bool) async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.togglePenMode(\(enabled)); 0;")
    }
    @MainActor
    public func toggleActionsMenu(isPresented: Bool) async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.toggleActionsMenu(\(isPresented)); 0;")
    }
    @MainActor
    public func togglePencilInterationMode(mode: ToolState.PencilInteractionMode) async throws {
        try await webView.evaluateJavaScript(
            "window.excalidrawZHelper.togglePencilInterationMode(\(mode.rawValue)); 0;"
        )
    }
    @MainActor
    public func loadImageToExcalidrawCanvas(imageData: Data, type: String) async throws {
        var buffer = [UInt8].init(repeating: 0, count: imageData.count)
        imageData.copyBytes(to: &buffer, count: imageData.count)
        let buf = buffer
        try await webView.evaluateJavaScript("window.excalidrawZHelper.loadImageBuffer(\(buf), '\(type)'); 0;")
    }
    
    // Collab
    @MainActor
    public func openCollabMode() async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.openCollabMode(); 0;")
    }
    
    struct CollaborationInfo: Codable, Hashable {
        var username: String
    }
    
    @MainActor
    public func getCollaborationInfo() async throws -> CollaborationInfo {
        guard let res = try await webView.evaluateJavaScript("window.excalidrawZHelper.getExcalidrawCollabInfo();") else {
            return CollaborationInfo(username: "")
        }
        if JSONSerialization.isValidJSONObject(res) {
            let data = try JSONSerialization.data(withJSONObject: res)
            return try JSONDecoder().decode(CollaborationInfo.self, from: data)
        } else {
            return CollaborationInfo(username: "")
        }
    }
    
    
    @MainActor
    public func setCollaborationInfo(_ info: CollaborationInfo) async throws {
        try await webView.evaluateJavaScript(
            "window.excalidrawZHelper.setExcalidrawCollabInfo(\(info.jsonStringified())); 0;"
        )
    }
    
    @MainActor
    public func followCollborator(_ collaborator: Collaborator) async throws {
        try await webView.evaluateJavaScript("window.excalidrawZHelper.followCollaborator(\(collaborator.jsonStringified())); 0;")
    }
    
    @MainActor
    func reload() {
         webView.evaluateJavaScript("location.reload(); 0;")
    }
    
    @MainActor
    func toggleWebPointerEvents(enabled: Bool) async throws {
        try await webView.evaluateJavaScript("document.body.style = '\(enabled ? "" : "pointer-events: none;")'; 0;")
    }
}


