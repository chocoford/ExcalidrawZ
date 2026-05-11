//
//  WebViewCoordinator.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/7/10.
//

import SwiftUI
import WebKit
import Logging
import Combine
import CoreData

typealias CollaborationInfo = ExcalidrawCore.CollaborationInfo
@MainActor
protocol AICameraSessionEventSink: AnyObject {
    func aiCameraSessionDidStart(_ info: ExcalidrawCore.AICameraSessionInfo)
    func aiCameraSessionDidUpdate(_ info: ExcalidrawCore.AICameraSessionInfo)
    func aiCameraSessionDidInterrupt(_ info: ExcalidrawCore.AICameraSessionInfo)
    func aiCameraSessionDidSettle(_ info: ExcalidrawCore.AICameraSessionInfo)
    func aiCameraSessionDidEnd(_ info: ExcalidrawCore.AICameraSessionInfo)
}

class ExcalidrawCore: NSObject, ObservableObject {
#if canImport(AppKit)
    typealias PlatformImage = NSImage
#elseif canImport(UIKit)
    typealias PlatformImage = UIImage
#endif
    
    let logger = Logger(label: "ExcalidrawCore")
    
    var parent: ExcalidrawCanvasView?
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
    
    override init() {
        self.publishError = { error in }
        super.init()
        self.configWebView()
    }
    
    @Published var isNavigating = true
    @Published var isDocumentLoaded = false
    @Published var isCollabEnabled = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var cameraState = CameraState()
    @Published private(set) var selectedElementIDs: [String] = []
    
    var downloadCache: [String : Data] = [:]
    var downloads: [URLRequest : URL] = [:]
    
    
    @Published var canUndo = false
    @Published var canRedo = false
    @Published private(set) var aiCameraSession = AICameraSessionInfo()
    
    var previousFileID: UUID? = nil
    private var lastVersion: Int = 0

    var hasInjectIndexedDBData = false

    // Track loaded MediaItem IDs for re-injection detection
    private var loadedMediaItemIDs: Set<String> = []

    internal var lastTool: ExcalidrawTool?
    weak var aiCameraEventSink: (any AICameraSessionEventSink)?
    
    @MainActor
    func setup(parent: ExcalidrawCanvasView) {
        self.parent = parent
        switch parent.type {
            case .normal:
                Publishers.CombineLatest($isNavigating, $isDocumentLoaded)
                    .map { isNavigating, isDocumentLoaded in
                        isNavigating || !isDocumentLoaded
                    }
                    .assign(to: &$isLoading)
            case .collaboration:
                Publishers.CombineLatest(
                    Publishers.CombineLatest($isNavigating, $isDocumentLoaded)
                        .map { isNavigating, isDocumentLoaded in
                            isNavigating || !isDocumentLoaded
                        },
                    $isCollabEnabled
                )
                .map { $0 || !$1 }
                .assign(to: &$isLoading)
        }
    }
    
    func configWebView() {
        logger.info("Configure Web View...")
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
            userContentController.add(self, name: "consoleHandler") // it is necessary
            logger.info("Enable console handler.")
        } catch {
            logger.error("Config consoleHandler failed: \(error)")
        }
        
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
        self.logger.info("refreshing...")
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
                self.logger.info("navigate to \(url), roomID: \(String(describing: self.parent?.file?.roomID))")
                self.webView.load(request)
            case nil:
                break
        }
    }
}

/// Keep stateless
extension ExcalidrawCore {
    struct JSONEncodingFailed: Error {}
    struct InvalidJavaScriptResult: Error {}

    struct CameraState: Codable, Hashable {
        var scrollX: Double = 0
        var scrollY: Double = 0
        var zoom: Double = 1
    }

    struct CameraPatch: Codable, Hashable {
        var scrollX: Double?
        var scrollY: Double?
        var zoom: Double?
    }

    struct CameraAnimationOptions: Codable, Hashable {
        var animate: Bool = true
        var duration: Int = 300
    }

    enum ScrollToElementMode: String, Codable, Hashable {
        case center
        case fitContent
        case fitViewport
    }

    struct ScrollToElementOptions: Codable, Hashable {
        var mode: ScrollToElementMode = .fitContent
        var animate: Bool = true
        var duration: Int = 300
        var viewportZoomFactor: Double?
        var minZoom: Double?
        var maxZoom: Double?
    }

    struct ZoomToFitOptions: Codable, Hashable {
        var animate: Bool = true
        var duration: Int = 300
        var viewportZoomFactor: Double = 0.9
    }

    enum AICameraZoomBehavior: String, Codable, Hashable {
        case preserve
        case gentle
        case fitWhenNeeded
    }

    enum AICameraSessionState: String, Codable, Hashable {
        case active
        case settling
        case interrupted
        case ended
    }

    enum AICameraEndMode: String, Codable, Hashable {
        case settle
        case immediate
    }

    struct AICameraViewportPadding: Codable, Hashable {
        var top: Double
        var right: Double
        var bottom: Double
        var left: Double

        init(top: Double, right: Double, bottom: Double, left: Double) {
            self.top = top
            self.right = right
            self.bottom = bottom
            self.left = left
        }

        init(all: Double) {
            self.init(top: all, right: all, bottom: all, left: all)
        }
    }

    enum AICameraPaddingValue: Codable, Hashable {
        case uniform(Double)
        case edges(AICameraViewportPadding)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self = .uniform(value)
            } else {
                self = .edges(try container.decode(AICameraViewportPadding.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
                case .uniform(let value):
                    try container.encode(value)
                case .edges(let value):
                    try container.encode(value)
            }
        }
    }

    struct AICameraSessionOptions: Codable, Hashable {
        var zoomBehavior: AICameraZoomBehavior = .fitWhenNeeded
        var followRate: Double?
        var viewportPadding: AICameraPaddingValue?
        var minZoom: Double?
        var maxZoom: Double?
        var safeAreaRatio: Double?
        var revision: Int?
    }

    struct AICameraTargetBox: Codable, Hashable {
        var type: String = "box"
        var minX: Double
        var minY: Double
        var maxX: Double
        var maxY: Double
    }

    struct AICameraTargetElements: Codable, Hashable {
        var type: String = "elements"
        var ids: [String]
    }

    enum AICameraTarget: Codable, Hashable {
        case box(AICameraTargetBox)
        case elements(AICameraTargetElements)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(AICameraTargetBox.self) {
                self = .box(value)
            } else {
                self = .elements(try container.decode(AICameraTargetElements.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
                case .box(let value):
                    try container.encode(value)
                case .elements(let value):
                    try container.encode(value)
            }
        }
    }

    struct AICameraBeginResponse: Codable, Hashable {
        var sessionId: String
        var state: AICameraSessionState
        var startedAt: JSONValue?
    }

    struct AICameraUpdateResponse: Codable, Hashable {
        var accepted: Bool
        var state: AICameraSessionState?
        var reason: String?
    }

    struct AICameraSessionInfo: Codable, Hashable {
        var sessionId: String?
        var state: AICameraSessionState?
        var startedAt: JSONValue?
        var mode: String?
        var reason: String?
        var eventType: String?
        var revision: Int?
        var stateBeforeInterrupt: AICameraSessionState?
        var camera: CameraState?
    }

    struct AICameraEndOptions: Codable, Hashable {
        var mode: AICameraEndMode = .settle
    }

    struct AICameraInterruptOptions: Codable, Hashable {
        var reason: String = "host_override"
    }

    enum CaptureUpdate: String, Codable, Hashable {
        case immediately = "IMMEDIATELY"
        case eventually = "EVENTUALLY"
        case never = "NEVER"
    }

    enum MermaidAnchor: String, Codable, Hashable {
        case topLeft = "top-left"
        case center
    }

    enum MermaidPosition: Codable, Hashable {
        case auto
        case viewportCenter
        case sceneCenter
        case point(MermaidPointPosition)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let rawValue = try? container.decode(String.self) {
                switch rawValue {
                    case "auto":
                        self = .auto
                    case "viewport-center":
                        self = .viewportCenter
                    case "scene-center":
                        self = .sceneCenter
                    default:
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "Unsupported Mermaid position: \(rawValue)"
                        )
                }
            } else {
                self = .point(try container.decode(MermaidPointPosition.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
                case .auto:
                    try container.encode("auto")
                case .viewportCenter:
                    try container.encode("viewport-center")
                case .sceneCenter:
                    try container.encode("scene-center")
                case .point(let value):
                    try container.encode(value)
            }
        }
    }

    struct MermaidPointPosition: Codable, Hashable {
        var x: Double
        var y: Double
        var anchor: MermaidAnchor?
    }

    enum MermaidFocus: Codable, Hashable {
        case enabled(Bool)
        case options(MermaidFocusOptions)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let enabled = try? container.decode(Bool.self) {
                self = .enabled(enabled)
            } else {
                self = .options(try container.decode(MermaidFocusOptions.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
                case .enabled(let value):
                    try container.encode(value)
                case .options(let value):
                    try container.encode(value)
            }
        }
    }

    struct MermaidFocusOptions: Codable, Hashable {
        var animate: Bool?
        var duration: Int?
        var viewportZoomFactor: Double?
    }

    struct MermaidInsertOptions: Codable, Hashable {
        var position: MermaidPosition?
        var focus: MermaidFocus?
        var regenerateIds: Bool?
        var mermaidConfig: JSONValue?
        var captureUpdate: CaptureUpdate?
    }

    struct MermaidConvertOptions: Codable, Hashable {
        var regenerateIds: Bool?
        var mermaidConfig: JSONValue?
    }

    struct MermaidPoint: Codable, Hashable {
        var x: Double
        var y: Double
    }

    struct MermaidBounds: Codable, Hashable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    struct MermaidInsertResult: Codable, Hashable {
        var elementIds: [String]
        var insertedAt: MermaidPoint
        var bounds: MermaidBounds
    }

    struct SkeletonInsertOptions: Codable, Hashable {
        var regenerateIds: Bool?
        var position: MermaidPosition?
        var focus: MermaidFocus?
        var files: [String: JSONValue]?
        var captureUpdate: CaptureUpdate?
        var sanitize: Bool?
    }

    struct SkeletonInsertResult: Codable, Hashable {
        var elementIds: [String]
        var insertedAt: MermaidPoint
        var bounds: MermaidBounds
    }

    struct MermaidConvertResult: Codable, Hashable {
        var elements: [JSONValue]
        var files: [String: JSONValue]
    }

    /// One-time copy of the current editor scene at the moment it was requested.
    /// This is not a persistent/live reference and must not drive autosave.
    struct CurrentFileSnapshot: Codable, Hashable {
        var dataString: String
        var elements: [JSONValue]
        var appState: JSONValue
        var files: [String: JSONValue]
    }

    struct ReplaceAllElementsOptions: Codable, Hashable {
        var captureUpdate: CaptureUpdate = .immediately
    }

    struct UpdateElementOperation: Codable, Hashable {
        var id: String
        var updates: [String: JSONValue]
    }

    enum JSONValue: Codable, Hashable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else {
                throw InvalidJavaScriptResult()
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
                case .string(let value):
                    try container.encode(value)
                case .number(let value):
                    try container.encode(value)
                case .bool(let value):
                    try container.encode(value)
                case .object(let value):
                    try container.encode(value)
                case .array(let value):
                    try container.encode(value)
                case .null:
                    try container.encodeNil()
            }
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw JSONEncodingFailed()
        }
        return jsonString
    }

    private func decodeJavaScriptResult<T: Decodable>(_ result: Any?, as type: T.Type) throws -> T {
        if let string = result as? String,
           let data = string.data(using: .utf8) {
            return try JSONDecoder().decode(type, from: data)
        }
        if let result,
           JSONSerialization.isValidJSONObject(result) {
            let data = try JSONSerialization.data(withJSONObject: result)
            return try JSONDecoder().decode(type, from: data)
        }
        throw InvalidJavaScriptResult()
    }

    func updateCameraState(_ camera: CameraState) {
        cameraState = camera
    }

    func updateSelectedElementIDs(_ ids: [String]) {
        selectedElementIDs = ids
    }

    func clearSelectedElementIDs() {
        selectedElementIDs = []
    }

    func updateAICameraSession(_ session: AICameraSessionInfo) {
        aiCameraSession = session
    }

    /// Loads a file into the web view and returns once Excalidraw has actually applied
    /// the new scene (the JS helper is async). Callers can chain follow-up work like
    /// re-syncing canvas preferences without resorting to a delay.
    /// The optional `LoadFileResult` exposes JS-side telemetry (element count, duration)
    /// — currently unused, but typed so we don't have to touch this signature again.
    @discardableResult
    func loadFile(from file: ExcalidrawFile?, force: Bool = false) async -> LoadFileResult? {
        let coreLoading = self.isLoading
        let webLoading = await self.webView.isLoading
        guard !coreLoading, !webLoading else {
            print("[aiDiag] core.loadFile → bailed: core.isLoading=\(coreLoading) webView.isLoading=\(webLoading) file.id=\(file?.id ?? "nil")")
            return nil
        }
        guard let file = file,
              let data = file.content else {
            print("[aiDiag] core.loadFile → bailed: file=\(file == nil ? "nil" : "non-nil") content=\(file?.content == nil ? "nil" : "\(file!.content!.count) bytes")")
            return nil
        }
        do {
            print("[aiDiag] core.loadFile → calling webActor.loadFile id=\(file.id) bytes=\(data.count) force=\(force)")
            let result = try await self.webActor.loadFile(id: file.id, data: data, force: force)
            print("[aiDiag] core.loadFile → webActor returned. id=\(file.id) result=\(result == nil ? "nil (already loaded)" : "elements=\(result!.elementCount)")")
            return result
        } catch {
            print("[aiDiag] core.loadFile → webActor THREW: \(error)")
            self.publishError(error)
            return nil
        }
    }
    
    /// Save `currentFile` or creating if neccessary.
    ///
    /// This function will get the local storage of `excalidraw.com`.
    /// Then it will set the data got from local storage to `currentFile`.
    /// Returns `{ dataString, elementCount }` from the JS side.
    @MainActor
    @discardableResult
    func saveCurrentFile() async throws -> SaveFileResult? {
        let raw = try await self.webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.saveFile();",
            arguments: [:],
            contentWorld: .page
        )
        return SaveFileResult(fromJS: raw)
    }

    /// Returns a one-time snapshot copy of the current live canvas without
    /// participating in the persistence/autosave flow. Use this for AI tools
    /// and debug reads that need editor state newer than the throttled
    /// `onStateChanged` broadcast.
    @MainActor
    func getCurrentFileSnapshot() async throws -> CurrentFileSnapshot {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let result = try await self.webView.callAsyncJavaScript(
            "return JSON.stringify(await window.excalidrawZHelper.getCurrentFileSnapshot());",
            arguments: [:],
            contentWorld: .page
        )
        return try decodeJavaScriptResult(result, as: CurrentFileSnapshot.self)
    }
    
    /// `true` if is dark mode.
    @MainActor
    func getIsDark() async throws -> Bool {
        if self.webView.isLoading { return false }
        let res = try await self.webView.callAsyncJavaScript(
            "return window.excalidrawZHelper.getIsDark();",
            arguments: [:],
            contentWorld: .page
        )
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
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleColorTheme(\"\(dark ? "dark" : "light")\");",
            arguments: [:],
            contentWorld: .page
        )
    }
    
    @MainActor
    @discardableResult
    func loadLibraryItem(item: ExcalidrawLibrary) async throws -> LoadLibraryItemResult? {
        let raw = try await self.webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.loadLibraryItem(\(item.jsonStringified()));",
            arguments: [:],
            contentWorld: .page
        )
        return LoadLibraryItemResult(fromJS: raw)
    }

    @MainActor
    func getCamera() async throws -> CameraState {
        guard !self.webView.isLoading else {
            return cameraState
        }
        let result = try await webView.callAsyncJavaScript(
            "return JSON.stringify(window.excalidrawZHelper.getCamera());",
            arguments: [:],
            contentWorld: .page
        )
        let camera = try decodeJavaScriptResult(result, as: CameraState.self)
        cameraState = camera
        return camera
    }

    @MainActor
    func setCamera(_ camera: CameraPatch) async throws {
        guard !self.webView.isLoading else { return }
        let payload = try encodeJSON(camera)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.setCamera(\(payload));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func scrollToCenter() async throws {
        guard !self.webView.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.scrollToCenter();",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func scrollToElement(id: String, options: ScrollToElementOptions = .init()) async throws {
        guard !self.webView.isLoading else { return }
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.scrollToElement('\(id)', \(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func zoomToFit(options: ZoomToFitOptions = .init()) async throws {
        guard !self.webView.isLoading else { return }
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.zoomToFit(\(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func zoomToFitElements(ids: [String], options: ZoomToFitOptions = .init()) async throws {
        guard !self.webView.isLoading else { return }
        let idsJSON = try encodeJSON(ids)
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.zoomToFitElements(\(idsJSON), \(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func zoomTo(_ scale: Double) async throws {
        guard !self.webView.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.zoomTo(\(scale));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func beginAICameraSession(options: AICameraSessionOptions = .init()) async throws -> AICameraBeginResponse {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let optionsJSON = try encodeJSON(options)
        let result = try await webView.callAsyncJavaScript(
            "return JSON.stringify(window.excalidrawZHelper.beginAICameraSession(\(optionsJSON)));",
            arguments: [:],
            contentWorld: .page
        )
        let response = try decodeJavaScriptResult(result, as: AICameraBeginResponse.self)
        aiCameraSession = .init(
            sessionId: response.sessionId,
            state: response.state,
            startedAt: response.startedAt
        )
        return response
    }

    @MainActor
    func updateAICameraTarget(
        sessionId: String,
        target: AICameraTarget,
        options: AICameraSessionOptions = .init()
    ) async throws -> AICameraUpdateResponse {
        guard !self.webView.isLoading else {
            return .init(accepted: false, state: nil, reason: "webview_loading")
        }
        let sessionIdJSON = try encodeJSON(sessionId)
        let targetJSON = try encodeJSON(target)
        let optionsJSON = try encodeJSON(options)
        let result = try await webView.callAsyncJavaScript(
            "return JSON.stringify(window.excalidrawZHelper.updateAICameraTarget(\(sessionIdJSON), \(targetJSON), \(optionsJSON)));",
            arguments: [:],
            contentWorld: .page
        )
        return try decodeJavaScriptResult(result, as: AICameraUpdateResponse.self)
    }

    @MainActor
    func endAICameraSession(
        sessionId: String,
        options: AICameraEndOptions = .init()
    ) async throws {
        guard !self.webView.isLoading else { return }
        let sessionIdJSON = try encodeJSON(sessionId)
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.endAICameraSession(\(sessionIdJSON), \(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func cancelAICameraSession(sessionId: String) async throws {
        guard !self.webView.isLoading else { return }
        let sessionIdJSON = try encodeJSON(sessionId)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.cancelAICameraSession(\(sessionIdJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func interruptAICameraSession(
        sessionId: String,
        options: AICameraInterruptOptions = .init()
    ) async throws {
        guard !self.webView.isLoading else { return }
        let sessionIdJSON = try encodeJSON(sessionId)
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.interruptAICameraSession(\(sessionIdJSON), \(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func getAICameraSession(sessionId: String? = nil) async throws -> AICameraSessionInfo? {
        guard !self.webView.isLoading else {
            return aiCameraSession.sessionId == nil ? nil : aiCameraSession
        }
        let body: String
        if let sessionId {
            let sessionIdJSON = try encodeJSON(sessionId)
            body = "return JSON.stringify(window.excalidrawZHelper.getAICameraSession(\(sessionIdJSON)));"
        } else {
            body = "return JSON.stringify(window.excalidrawZHelper.getAICameraSession());"
        }
        let result = try await webView.callAsyncJavaScript(
            body,
            arguments: [:],
            contentWorld: .page
        )
        guard !(result is NSNull) else { return nil }
        if let string = result as? String, string == "null" {
            return nil
        }
        let session = try decodeJavaScriptResult(result, as: AICameraSessionInfo.self)
        aiCameraSession = session
        return session
    }

    @MainActor
    func revealElement(id: String, options: ScrollToElementOptions = .init()) async throws {
        var mergedOptions = options
        mergedOptions.mode = .fitContent
        try await scrollToElement(id: id, options: mergedOptions)
    }

    @MainActor
    func focusElement(id: String, options: ScrollToElementOptions = .init()) async throws {
        var mergedOptions = options
        mergedOptions.mode = .fitViewport
        if mergedOptions.viewportZoomFactor == nil {
            mergedOptions.viewportZoomFactor = 0.6
        }
        try await scrollToElement(id: id, options: mergedOptions)
    }

    @MainActor
    func replaceAllElements(
        _ elements: [ExcalidrawElement],
        options: ReplaceAllElementsOptions = .init()
    ) async throws {
        guard !self.webView.isLoading else { return }
        let elementsJSON = try encodeJSON(elements)
        let optionsJSON = try encodeJSON(options)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.replaceAllElements(\(elementsJSON), \(optionsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func addElements(_ elements: [ExcalidrawElement]) async throws {
        guard !self.webView.isLoading, !elements.isEmpty else { return }
        let elementsJSON = try encodeJSON(elements)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.addElements(\(elementsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func updateElements(_ operations: [UpdateElementOperation]) async throws {
        guard !self.webView.isLoading, !operations.isEmpty else { return }
        let operationsJSON = try encodeJSON(operations)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.updateElements(\(operationsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func removeElements(ids: [String]) async throws {
        guard !self.webView.isLoading, !ids.isEmpty else { return }
        let idsJSON = try encodeJSON(ids)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.removeElements(\(idsJSON));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func insertFromMermaid(
        _ definition: String,
        options: MermaidInsertOptions = .init()
    ) async throws -> MermaidInsertResult {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let definitionJSON = try encodeJSON(definition)
        let optionsJSON = try encodeJSON(options)
        let result = try await webView.callAsyncJavaScript(
            "return JSON.stringify(await window.excalidrawZHelper.insertFromMermaid(\(definitionJSON), \(optionsJSON)));",
            arguments: [:],
            contentWorld: .page
        )
        return try decodeJavaScriptResult(result, as: MermaidInsertResult.self)
    }

    @MainActor
    func insertFromSkeleton(
        _ skeletons: JSONValue,
        options: SkeletonInsertOptions = .init()
    ) async throws -> SkeletonInsertResult {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let skeletonsJSON = try encodeJSON(skeletons)
        let optionsJSON = try encodeJSON(options)
        let result = try await webView.callAsyncJavaScript(
            "return JSON.stringify(await window.excalidrawZHelper.insertFromSkeleton(\(skeletonsJSON), \(optionsJSON)));",
            arguments: [:],
            contentWorld: .page
        )
        return try decodeJavaScriptResult(result, as: SkeletonInsertResult.self)
    }

    @MainActor
    func convertMermaidToExcalidraw(
        _ definition: String,
        options: MermaidConvertOptions = .init()
    ) async throws -> MermaidConvertResult {
        guard !self.webView.isLoading else {
            throw InvalidJavaScriptResult()
        }
        let definitionJSON = try encodeJSON(definition)
        let optionsJSON = try encodeJSON(options)
        let result = try await webView.callAsyncJavaScript(
            "return JSON.stringify(await window.excalidrawZHelper.convertMermaidToExcalidraw(\(definitionJSON), \(optionsJSON)));",
            arguments: [:],
            contentWorld: .page
        )
        return try decodeJavaScriptResult(result, as: MermaidConvertResult.self)
    }

    @MainActor
    func exportPNG() async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.exportImage();",
            arguments: [:],
            contentWorld: .page
        )
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
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleToolbarAction(\(key));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func toggleToolbarAction(key: Character) async throws {
        guard !self.isLoading else { return }
        print(#function, key)
        let toolbarKey: String
        if key == "\u{1B}" {
            toolbarKey = "Escape"
        } else if key == " " {
            toolbarKey = "Space"
        } else {
            toolbarKey = key.uppercased()
        }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleToolbarAction('\(toolbarKey)');",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    func toggleDeleteAction() async throws {
        guard !self.isLoading else { return }
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleToolbarAction('Backspace');",
            arguments: [:],
            contentWorld: .page
        )
    }

    enum ExtraTool: String {
        case webEmbed = "webEmbed"
        case text2Diagram = "text2diagram"
        case mermaid = "mermaid"
        case magicFrame = "wireframe"
        case lasso = "lasso"
    }
    @MainActor
    func toggleToolbarAction(tool: ExtraTool) async throws {
        guard !self.isLoading else { return }
        print(#function, tool)
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleToolbarAction('\(tool.rawValue)');",
            arguments: [:],
            contentWorld: .page
        )
    }
    
    func exportElementsToPNGData(
        elements: [ExcalidrawElement],
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme,
        exportScale: Int = 1
    ) async throws -> Data {
        let elementsJSON = try elements.jsonStringified()
        let filesJSON = try files?.jsonStringified() ?? "undefined"
        let script = """
        return await window.excalidrawZHelper.exportElementsToBlob(
            \(elementsJSON), \(filesJSON), {
                exportEmbedScene: \(embedScene),
                withBackground: \(withBackground),
                exportWithDarkMode: \(colorScheme == .dark),
                mimeType: 'image/png',
                quality: 100,
                exportScale: \(exportScale)
            }
        );
        """
        let raw = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            contentWorld: .page
        )
        guard let dict = raw as? [String: Any],
              let dataString = dict["blobData"] as? String,
              let data = Data(base64Encoded: dataString) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return data
    }
    
    func exportElementsToPNG(
        elements: [ExcalidrawElement],
        embedScene: Bool = false,
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        withBackground: Bool = true,
        colorScheme: ColorScheme,
        exportScale: Int = 1
    ) async throws -> PlatformImage {
        let data = try await self.exportElementsToPNGData(
            elements: elements,
            files: files,
            embedScene: embedScene,
            withBackground: withBackground,
            colorScheme: colorScheme,
            exportScale: exportScale
        )
        guard let image = PlatformImage(data: data) else {
            struct DecodeImageFailed: Error {}
            throw DecodeImageFailed()
        }
        return image
    }
    
    func exportElementsToSVGData(
        elements: [ExcalidrawElement],
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> Data {
        let elementsJSON = try elements.jsonStringified()
        let filesJSON = try files?.jsonStringified() ?? "undefined"
        let script = """
        return await window.excalidrawZHelper.exportElementsToSvg(
            \(elementsJSON), \(filesJSON),
            \(embedScene), \(withBackground), \(colorScheme == .dark)
        );
        """
        let raw = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            contentWorld: .page
        )
        guard let dict = raw as? [String: Any],
              let svg = dict["svg"] as? String else {
            struct ExportSVGFailed: Error {}
            throw ExportSVGFailed()
        }
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
        files: [String : ExcalidrawFile.ResourceFile]? = nil,
        embedScene: Bool = false,
        withBackground: Bool = true,
        colorScheme: ColorScheme
    ) async throws -> PlatformImage {
        let data = try await exportElementsToSVGData(
            elements: elements,
            files: files,
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
    
    /// Get Excalidraw Indexed DB Data
    func getExcalidrawStore() async throws -> [ExcalidrawFile.ResourceFile] {
        let raw = try await webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.getAllMedias();",
            arguments: [:],
            contentWorld: .page
        )
        guard let dict = raw as? [String: Any], let filesAny = dict["files"] else {
            struct GetAllMediasFailed: Error {}
            throw GetAllMediasFailed()
        }
        // The JS side already returns plain JSON-compatible objects; round-trip
        // through JSONSerialization to drive `Codable`.
        let data = try JSONSerialization.data(withJSONObject: filesAny)
        return try JSONDecoder().decode([ExcalidrawFile.ResourceFile].self, from: data)
    }
    
    /// Insert media files to IndexedDB
    @MainActor
    func insertMediaFiles(_ files: [ExcalidrawFile.ResourceFile]) async throws {
        logger.info("insertMediaFiles: \(files.count)")
        let jsonStringified = try files.jsonStringified()
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.insertMedias('\(jsonStringified)');",
            arguments: [:],
            contentWorld: .page
        )
    }

    /// Inject all MediaItems from CoreData to IndexedDB
    /// This method fetches all MediaItems and injects them into the WebView's IndexedDB
    /// Most work (fetching, loading files) runs on background threads for better performance
    /// - Returns: The count of injected MediaItems
    func injectAllMediaItems() async throws -> Int {
        logger.info("Starting MediaItem injection...")

        // Check WebView readiness on main thread
        let isReady = await MainActor.run {
            !isNavigating && (hasInjectIndexedDBData || isDocumentLoaded)
        }

        guard isReady else {
            logger.warning("WebView not ready for MediaItem injection, skipping")
            return 0
        }

        let context = PersistenceController.shared.newTaskContext()
        let allMedias = try await context.perform {
            let allMediasFetch = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            return try context.fetch(allMediasFetch)
        }
        let allMediaIDs = allMedias.compactMap(\.id)
        
        logger.info("Fetched \(allMedias.count) MediaItems from CoreData")

        // Load media items using async method with iCloud Drive support (concurrent)
        // This can run on background threads for better performance
        let mediaFiles = await withTaskGroup(of: ExcalidrawFile.ResourceFile?.self) { group in
            var files: [ExcalidrawFile.ResourceFile] = []
            
            for id in allMedias.map({$0.objectID}) {
                group.addTask {
                    if let mediaItem = context.object(with: id) as? MediaItem {
                        return try? await ExcalidrawFile.ResourceFile(mediaItem: mediaItem)
                    }
                    return nil
                }
            }

            for await resourceFile in group {
                if let resourceFile = resourceFile {
                    files.append(resourceFile)
                }
            }

            return files
        }

        // Insert to IndexedDB and update state on main thread
        await MainActor.run {
            Task { @MainActor in
                try? await self.insertMediaFiles(mediaFiles)
            }
            // Update loaded IDs
            self.loadedMediaItemIDs = Set(allMediaIDs)
            self.hasInjectIndexedDBData = true
        }

        logger.info("Successfully injected \(mediaFiles.count) MediaItems")
        return mediaFiles.count
    }

    /// Check if MediaItems have changed and re-inject if needed
    /// This is the public method that should be called when MediaItem changes are detected
    public func refreshMediaItemsIfNeeded() async throws {
        // Get current MediaItem IDs from CoreData on main thread
        let (currentIDs, loadedIDs) = try await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let fetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            fetchRequest.propertiesToFetch = ["id"]

            let currentMedias = try context.fetch(fetchRequest)
            let currentIDs = Set(currentMedias.compactMap { $0.id })

            return (currentIDs, self.loadedMediaItemIDs)
        }

        // Check if there are changes
        let hasChanges = currentIDs != loadedIDs

        if hasChanges {
            let addedCount = currentIDs.subtracting(loadedIDs).count
            let removedCount = loadedIDs.subtracting(currentIDs).count
            logger.info("MediaItem changes detected: +\(addedCount) added, -\(removedCount) removed, re-injecting...")

            _ = try await injectAllMediaItems()
        } else {
            logger.debug("No MediaItem changes detected, skipping injection")
        }
    }

    @MainActor
    func performUndo() async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.undo();",
            arguments: [:],
            contentWorld: .page
        )
    }
    @MainActor
    func performRedo() async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.redo();",
            arguments: [:],
            contentWorld: .page
        )
    }
    @MainActor
    func connectPencil(enabled: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.connectPencil(\(enabled));",
            arguments: [:],
            contentWorld: .page
        )
    }
    @MainActor
    func togglePenMode(enabled: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.togglePenMode(\(enabled));",
            arguments: [:],
            contentWorld: .page
        )
    }
    @MainActor
    public func toggleActionsMenu(isPresented: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.toggleActionsMenu(\(isPresented));",
            arguments: [:],
            contentWorld: .page
        )
    }
    @MainActor
    public func togglePencilInterationMode(mode: ToolState.PencilInteractionMode) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.togglePencilInterationMode(\(mode.rawValue));",
            arguments: [:],
            contentWorld: .page
        )
    }
    @MainActor
    @discardableResult
    public func loadImageToExcalidrawCanvas(imageData: Data, type: String) async throws -> LoadImageResult? {
        var buffer = [UInt8].init(repeating: 0, count: imageData.count)
        imageData.copyBytes(to: &buffer, count: imageData.count)
        let buf = buffer
        let raw = try await webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.loadImageBuffer(\(buf), type);",
            arguments: ["type": type],
            contentWorld: .page
        )
        return LoadImageResult(fromJS: raw)
    }
    
    // Font
    @MainActor
    public func setAvailableFonts(fontFamilies: [String]) async throws {
        guard !self.webView.isLoading else { return }
        let payload = try encodeJSON(fontFamilies)
        for attempt in 0..<5 {
            let result = try await webView.callAsyncJavaScript(
                """
                if (window.excalidrawZHelper?.setAvailableFonts) {
                    window.excalidrawZHelper.setAvailableFonts(\(payload));
                    return true;
                }
                return false;
                """,
                arguments: [:],
                contentWorld: .page
            )
            if let applied = result as? Bool, applied {
                return
            }
            if attempt < 4 {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        throw InvalidJavaScriptResult()
    }
    
    
    // Collab
    @MainActor
    public func openCollabMode() async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.openCollabMode();",
            arguments: [:],
            contentWorld: .page
        )
    }

    struct CollaborationInfo: Codable, Hashable {
        var username: String
    }

    @MainActor
    public func getCollaborationInfo() async throws -> CollaborationInfo {
        let res = try await webView.callAsyncJavaScript(
            "return window.excalidrawZHelper.getExcalidrawCollabInfo();",
            arguments: [:],
            contentWorld: .page
        )
        guard let res, JSONSerialization.isValidJSONObject(res) else {
            return CollaborationInfo(username: "")
        }
        let data = try JSONSerialization.data(withJSONObject: res)
        return try JSONDecoder().decode(CollaborationInfo.self, from: data)
    }


    @MainActor
    public func setCollaborationInfo(_ info: CollaborationInfo) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.setExcalidrawCollabInfo(\(info.jsonStringified()));",
            arguments: [:],
            contentWorld: .page
        )
    }

    @MainActor
    public func followCollborator(_ collaborator: Collaborator) async throws {
        _ = try await webView.callAsyncJavaScript(
            "window.excalidrawZHelper.followCollaborator(\(collaborator.jsonStringified()));",
            arguments: [:],
            contentWorld: .page
        )
    }



    @MainActor
    func reload() {
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "location.reload();",
                arguments: [:],
                contentWorld: .page
            )
        }
    }

    @MainActor
    func toggleWebPointerEvents(enabled: Bool) async throws {
        _ = try await webView.callAsyncJavaScript(
            "document.body.style = '\(enabled ? "" : "pointer-events: none;")';",
            arguments: [:],
            contentWorld: .page
        )
    }
}
