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
        self.documentSyncController.attach(core: self)
        self.configWebView()
    }
    
    @Published var isNavigating = true
    @Published var isDocumentLoaded = false
    @Published var isCollabEnabled = false
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var cameraState = CameraState()
    @Published private(set) var selectedElementIDs: [String] = []
    @Published private(set) var contentChangeToken = 0
    
    var downloadCache: [String : Data] = [:]
    var downloads: [URLRequest : URL] = [:]
    
    
    @Published var canUndo = false
    @Published var canRedo = false
    @Published private(set) var aiCameraSession = AICameraSessionInfo()
    @Published private(set) var mathImageEditRequest: MathImageEditRequest?
    
    let documentSyncController = ExcalidrawDocumentSyncController()
    let currentFileSaveStreamBridge = ExcalidrawCore.CurrentFileSaveStreamBridge()
    private var lastVersion: Int = 0

    var hasInjectIndexedDBData = false

    @MainActor
    func noteAcceptedContentChange() {
        contentChangeToken &+= 1
    }

    // Track loaded MediaItem IDs for re-injection detection
    private var loadedMediaItemIDs: Set<String> = []

    internal var lastTool: ExcalidrawTool?
    weak var aiCameraEventSink: (any AICameraSessionEventSink)?

#if os(iOS)
    var lastPencilToolToggleAt: Date = .distantPast
    var isHandlingPencilToolToggle = false
#endif
    
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
                    Task { @MainActor in
                        let toolOrder = self.parent?.appPreference.toolbarToolOrder
                            ?? ExcalidrawToolbarToolOrder()
                        if let tool = toolOrder.tool(forShortcutNumber: int) {
                            guard let toolState = self.parent?.toolState,
                                  toolState.excalidrawWebCoordinator === self else {
                                return
                            }
                            try? await toolState.toggleTool(tool)
                        } else if self.parent == nil {
                            try? await self.toggleToolbarAction(key: int)
                        }
                    }
                case .char(let character):
                    Task { @MainActor in
                        guard self.parent?.toolState.excalidrawWebCoordinator === self else { return }
                        try? await self.toggleToolbarAction(key: character)
                    }
                case .space:
                    Task { @MainActor in
                        guard self.parent?.toolState.excalidrawWebCoordinator === self else { return }
                        try? await self.toggleToolbarAction(key: " ")
                    }
                case .escape:
                    Task { @MainActor in
                        guard self.parent?.toolState.excalidrawWebCoordinator === self else { return }
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

extension ExcalidrawCore {
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

    func updateLoadedMediaItemIDs(_ ids: Set<String>) {
        loadedMediaItemIDs = ids
    }

    func loadedMediaItemIDSnapshot() -> Set<String> {
        loadedMediaItemIDs
    }

    func requestMathImageEdit(_ request: MathImageEditRequest) {
        mathImageEditRequest = request
    }

    func clearMathImageEditRequest() {
        mathImageEditRequest = nil
    }

    /// Loads a file into the web view and returns once Excalidraw has actually applied
    /// the new scene (the JS helper is async). Callers can chain follow-up work like
    /// re-syncing canvas preferences without resorting to a delay.
    /// The optional `LoadFileResult` exposes JS-side telemetry (element count, duration)
    /// — currently unused, but typed so we don't have to touch this signature again.
    @discardableResult
    func loadFile(from file: ExcalidrawFile?, force: Bool = false) async -> LoadFileResult? {
        guard let file = file,
              let data = file.content else {
            logFileLoad(logger, "File load skipped: missing file or content", level: .warning)
            return nil
        }
        let outcome = await documentSyncController.load(
            fileID: file.id,
            data: data,
            force: force,
            validateCurrentParentFile: false
        )
        if case .loaded(let result) = outcome {
            return result
        }
        return nil
    }

    func waitUntilReadyForFileLoad(
        fileID: String,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var didLogWait = false

        while true {
            let coreLoading = self.isLoading || self.isNavigating || !self.isDocumentLoaded
            let webLoading = await self.webView.isLoading
            let initialMediaLoading = parent != nil
                && !hasInjectIndexedDBData

            if !coreLoading && !webLoading && !initialMediaLoading {
                return true
            }

            if Task.isCancelled {
                return false
            }

            if Date() >= deadline {
                if !coreLoading && !webLoading && initialMediaLoading {
                    logger.warning(
                        "Timed out waiting for initial media injection before loading file \(fileID); continuing with available media"
                    )
                    return true
                }
                logger.warning(
                    "Timed out waiting to load file \(fileID). coreLoading=\(coreLoading) webLoading=\(webLoading) initialMediaLoading=\(initialMediaLoading)"
                )
                return false
            }

            if !didLogWait {
                logger.info(
                    "Waiting for Excalidraw readiness before loading file \(fileID), initialMediaLoading=\(initialMediaLoading)"
                )
                didLogWait = true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
