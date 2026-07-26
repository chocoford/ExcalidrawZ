#if os(macOS)
import AppKit
import Combine
import Foundation
import Logging
import WebKit

@MainActor
final class ScreenAnnotationSession: ObservableObject {
    @Published private(set) var selectedTool: ExcalidrawTool = .laser
    @Published private(set) var isToolLocked = false
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var frozenBackgroundImage: NSImage?
    @Published private(set) var isCapturingBackground = false
    @Published private(set) var selectionViewportBounds: CGRect?
    @Published private(set) var selectionContext: ElementPropertiesContext?
    @Published private(set) var isCanvasInteractionActive = false
    @Published private(set) var isSelectionGeometryChanging = false
    @Published private(set) var isSelectionBoundsResolving = false
    @Published var selectedElementProperties = ElementProperties()

    var isFrozen: Bool {
        frozenBackgroundImage != nil
    }

    private weak var webView: WKWebView?
    private var isPreparingCanvas = false
    private var canvasPreparationTask: Task<Void, Never>?
    private var canvasPreparationID = UUID()
    private let toolbarTools: [ExcalidrawTool]
    private var selectedElementIDs: [String] = []
    private var boundTextElementIDs: [String] = []
    private var reportedSelectionSceneBounds: CGRect?
    private var selectionSceneBounds: CGRect?
    private var camera = ExcalidrawCore.CameraState()
    private var presentedElementProperties = ElementProperties()
    private var selectionSettleTask: Task<Void, Never>?
    private var selectionBoundsResolutionTask: Task<Void, Never>?
    private var selectionBoundsResolutionID = UUID()
    private var boundTextResolutionTask: Task<Void, Never>?
    private var boundTextResolvedSelectionIDs: [String]?
    private var propertyUpdateTask: Task<Void, Never>?
    private var propertyUpdateID = UUID()
    private let logger = Logger(label: "ScreenAnnotationSession")
    private let sessionID = UUID().uuidString

    init(
        frozenBackgroundImage: NSImage? = nil,
        toolbarTools: [ExcalidrawTool] = ExcalidrawToolbarToolOrder.defaultTools
    ) {
        self.frozenBackgroundImage = frozenBackgroundImage
        self.toolbarTools = toolbarTools
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        Task { @MainActor [weak webView] in
            await Task.yield()
            guard let webView else { return }
            webView.window?.makeFirstResponder(webView)
        }
    }

    func detach(webView: WKWebView) {
        guard self.webView === webView else { return }

        canvasPreparationID = UUID()
        canvasPreparationTask?.cancel()
        canvasPreparationTask = nil
        selectionSettleTask?.cancel()
        selectionBoundsResolutionTask?.cancel()
        boundTextResolutionTask?.cancel()
        cancelPropertyUpdate()
        self.webView = nil
        isPreparingCanvas = false
        isReady = false
    }

    func prepareCanvas() {
        guard !isReady, !isPreparingCanvas, let webView else { return }
        let preparationID = UUID()
        canvasPreparationID = preparationID
        isPreparingCanvas = true
        logger.debug(
            "Preparing screen annotation canvas session=\(sessionID) url=\(webView.url?.absoluteString ?? "nil")"
        )

        canvasPreparationTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            defer {
                if self.canvasPreparationID == preparationID {
                    self.canvasPreparationTask = nil
                    self.isPreparingCanvas = false
                }
            }
            do {
                let result = try await webView.callAsyncJavaScript(
                    """
                    const helper = window.excalidrawZHelper;
                    const result = await helper.prepareCanvas(options);
                    helper.startCameraTracking?.();
                    await new Promise(resolve => {
                      requestAnimationFrame(() => requestAnimationFrame(resolve));
                    });
                    return result;
                    """,
                    arguments: [
                        "options": [
                            "reset": true,
                            "clearHistory": true,
                            "transparent": true,
                            "activeTool": "laser",
                            "appState": [
                                "gridModeEnabled": false,
                                "zenModeEnabled": true,
                                "viewModeEnabled": false,
                                "showWelcomeScreen": false,
                                "scrollX": 0,
                                "scrollY": 0,
                                "zoom": ["value": 1],
                                "currentItemStrokeColor": "#ff3b30",
                            ],
                        ],
                    ],
                    contentWorld: .page
                )
                guard let result = result as? [String: Any],
                      result["reset"] as? Bool == true,
                      result["historyCleared"] as? Bool == true,
                      result["transparent"] as? Bool == true,
                      result["activeTool"] as? String == "laser" else {
                    throw ScreenAnnotationCanvasPreparationError
                        .invalidAcknowledgement
                }
                self.logger.debug(
                    "Prepared screen annotation canvas session=\(self.sessionID) reset=\(result["reset"] ?? "nil") historyCleared=\(result["historyCleared"] ?? "nil") transparent=\(result["transparent"] ?? "nil") activeTool=\(result["activeTool"] ?? "nil") appliedAppStateKeys=\(result["appliedAppStateKeys"] ?? [])"
                )
                guard !Task.isCancelled,
                      self.canvasPreparationID == preparationID,
                      self.webView === webView else {
                    return
                }
                webView.alphaValue = 1
                self.isReady = true
                self.errorMessage = nil
                webView.window?.makeFirstResponder(webView)
            } catch {
                guard !Task.isCancelled,
                      self.canvasPreparationID == preparationID else {
                    return
                }
                self.report(error)
            }
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func makeAnnotationDocument(
        imageData: Data,
        imageFormat: ScreenAnnotationSaveFormat,
        mode: ScreenAnnotationDocumentBridge.Mode,
        viewportRect: CGRect,
        selectionRect: CGRect?
    ) async throws -> ExcalidrawFile {
        guard let webView else {
            throw ScreenAnnotationSaveService.SaveError
                .annotationDocumentUnavailable
        }

        return try await ScreenAnnotationDocumentBridge.makeDocument(
            in: webView,
            imageData: imageData,
            imageFormat: imageFormat,
            mode: mode,
            viewportRect: viewportRect,
            selectionRect: selectionRect
        )
    }

    func deselectElementsForCapture() async throws {
        guard let webView else { return }

        _ = try await webView.callAsyncJavaScript(
            """
            window.excalidrawZHelper?.setSelectedElementIds([]);
            await new Promise(resolve => {
              requestAnimationFrame(() => requestAnimationFrame(resolve));
            });
            """,
            arguments: [:],
            contentWorld: .page
        )
    }

    func beginBackgroundCapture() -> Bool {
        guard !isCapturingBackground, !isFrozen else { return false }
        isCapturingBackground = true
        return true
    }

    func finishBackgroundCapture(_ image: NSImage?) {
        frozenBackgroundImage = image
        isCapturingBackground = false
    }

    func resumeLiveBackground() {
        frozenBackgroundImage = nil
    }

    func syncSelectedTool(_ rawValue: String) {
        let tool: ExcalidrawTool?
        switch rawValue {
            case "selection":
                tool = .cursor
            case "rectangle":
                tool = .rectangle
            case "diamond":
                tool = .diamond
            case "ellipse":
                tool = .ellipse
            case "arrow":
                tool = .arrow
            case "line":
                tool = .line
            case "freedraw":
                tool = .freedraw
            case "text":
                tool = .text
            case "image":
                tool = .image
            case "eraser":
                tool = .eraser
            case "laser":
                tool = .laser
            case "lasso":
                tool = .lasso
            case "hand":
                tool = .hand
            case "frame":
                tool = .frame
            case "embeddable":
                tool = .webEmbed
            case "magicframe":
                tool = .magicFrame
            default:
                tool = nil
        }
        if let tool {
            selectedTool = tool
        }
    }

    func syncToolLock(_ isLocked: Bool) {
        isToolLocked = isLocked
    }

    func syncSelectedElements(_ elements: [[String: Any]]) {
        guard !elements.isEmpty else {
            clearSelectedElements()
            return
        }

        let elementIDs = elements.compactMap { $0["id"] as? String }
        let boundTextElementIDs = ScreenAnnotationSelectionProperties
            .boundTextElementIDs(from: elements)
        let reportedSceneBounds = ScreenAnnotationSelectionProperties.bounds(
            for: elements
        )
        let isSameSelection = !selectedElementIDs.isEmpty
            && selectedElementIDs == elementIDs
        let didReportedGeometryChange = reportedSelectionSceneBounds
            != reportedSceneBounds
        if isSameSelection,
           didReportedGeometryChange,
           isCanvasInteractionActive || isSelectionGeometryChanging {
            markSelectionGeometryChanging()
        } else if !isSameSelection {
            selectionSettleTask?.cancel()
            boundTextResolutionTask?.cancel()
            boundTextResolvedSelectionIDs = nil
            cancelPropertyUpdate()
            isSelectionGeometryChanging = false
        }

        selectedElementIDs = elementIDs
        self.boundTextElementIDs = boundTextElementIDs
        reportedSelectionSceneBounds = reportedSceneBounds
        let baseContext = ElementPropertiesContext(
            elementTypes: elements.compactMap { $0["type"] as? String }
        )
        selectionContext = boundTextElementIDs.isEmpty
            ? baseContext
            : baseContext.includingBoundText()

        if let firstElement = elements.first {
            var properties = ScreenAnnotationSelectionProperties.properties(
                from: firstElement
            )
            if isSameSelection, !boundTextElementIDs.isEmpty {
                properties.fontFamily = selectedElementProperties.fontFamily
                properties.fontSize = selectedElementProperties.fontSize
                properties.textAlign = selectedElementProperties.textAlign
            }
            selectedElementProperties = properties
            presentedElementProperties = properties
        }
        if !isSameSelection || didReportedGeometryChange {
            if !isSameSelection {
                selectionSceneBounds = nil
                selectionViewportBounds = nil
            }
            resolveSelectionBounds(elementIDs: elementIDs)
        }

        if !boundTextElementIDs.isEmpty,
           boundTextResolvedSelectionIDs != elementIDs {
            resolveBoundTextProperties(
                elementIDs: boundTextElementIDs,
                selectionIDs: elementIDs
            )
        }
    }

    func clearSelectedElements() {
        selectionSettleTask?.cancel()
        selectionBoundsResolutionTask?.cancel()
        selectionBoundsResolutionID = UUID()
        isSelectionBoundsResolving = false
        boundTextResolutionTask?.cancel()
        boundTextResolvedSelectionIDs = nil
        cancelPropertyUpdate()
        isSelectionGeometryChanging = false
        selectedElementIDs = []
        boundTextElementIDs = []
        reportedSelectionSceneBounds = nil
        selectionSceneBounds = nil
        selectionViewportBounds = nil
        selectionContext = nil
        selectedElementProperties = ElementProperties()
        presentedElementProperties = ElementProperties()
    }

    func setCanvasInteractionActive(_ isActive: Bool) {
        guard isActive != isCanvasInteractionActive else { return }

        if isActive {
            isCanvasInteractionActive = true
            selectionSettleTask?.cancel()
            isSelectionGeometryChanging = false
        } else {
            if !selectedElementIDs.isEmpty {
                markSelectionGeometryChanging()
            }
            isCanvasInteractionActive = false
        }
    }

    private func resolveSelectionBounds(elementIDs: [String]) {
        selectionBoundsResolutionTask?.cancel()
        let resolutionID = UUID()
        selectionBoundsResolutionID = resolutionID
        guard let webView,
              let idsData = try? JSONEncoder().encode(elementIDs),
              let idsJSON = String(data: idsData, encoding: .utf8) else {
            isSelectionBoundsResolving = false
            return
        }

        isSelectionBoundsResolving = true
        selectionBoundsResolutionTask = Task {
            defer {
                if self.selectionBoundsResolutionID == resolutionID {
                    self.isSelectionBoundsResolving = false
                }
            }
            do {
                let result = try await webView.callAsyncJavaScript(
                    """
                    const helper = window.excalidrawZHelper;
                    const ids = JSON.parse(\(idsJSON.jsStringLiteral));
                    const elements = helper?.getElementsByIds?.(ids) ?? [];
                    const bounds = helper?._getCommonBounds?.(elements);
                    return bounds ? JSON.stringify(bounds) : null;
                    """,
                    arguments: [:],
                    contentWorld: .page
                )
                guard !Task.isCancelled,
                      self.selectionBoundsResolutionID == resolutionID,
                      self.selectedElementIDs == elementIDs,
                      let json = result as? String,
                      let data = json.data(using: .utf8),
                      let bounds = try JSONSerialization.jsonObject(
                        with: data
                      ) as? [NSNumber],
                      bounds.count == 4 else {
                    return
                }

                selectionSceneBounds = CGRect(
                    x: bounds[0].doubleValue,
                    y: bounds[1].doubleValue,
                    width: bounds[2].doubleValue - bounds[0].doubleValue,
                    height: bounds[3].doubleValue - bounds[1].doubleValue
                )
                updateSelectionViewportBounds()
            } catch {
                guard !Task.isCancelled else { return }
                report(error)
            }
        }
    }

    func syncCamera(_ data: [String: Any]) {
        if let scrollX = ScreenAnnotationSelectionProperties.number(data["scrollX"]) {
            camera.scrollX = scrollX
        }
        if let scrollY = ScreenAnnotationSelectionProperties.number(data["scrollY"]) {
            camera.scrollY = scrollY
        }
        if let zoom = ScreenAnnotationSelectionProperties.number(data["zoom"]) {
            camera.zoom = zoom
        }
        updateSelectionViewportBounds()
    }

    func applySelectedElementProperties() {
        guard propertyUpdateTask == nil else { return }
        let updateID = UUID()
        propertyUpdateID = updateID
        propertyUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.propertyUpdateID == updateID {
                    self.propertyUpdateTask = nil
                }
            }
            await self.flushSelectedElementProperties()
        }
    }

    private func flushSelectedElementProperties() async {
        while !Task.isCancelled,
              !selectedElementIDs.isEmpty,
              selectedElementProperties != presentedElementProperties {
            guard let webView else { return }

            let targetProperties = selectedElementProperties
            let elementIDs = selectedElementIDs
            let boundTextIDs = boundTextElementIDs
            let changes = targetProperties.changes(
                from: presentedElementProperties
            )
            guard changes != ElementProperties() else {
                presentedElementProperties = targetProperties
                continue
            }

            do {
                try await ScreenAnnotationElementPropertiesBridge.apply(
                    changes,
                    to: elementIDs,
                    boundTextElementIDs: boundTextIDs,
                    in: webView
                )
            } catch {
                guard !Task.isCancelled else { return }
                report(error)
                return
            }

            guard selectedElementIDs == elementIDs else { return }
            presentedElementProperties = targetProperties
        }
    }

    private func cancelPropertyUpdate() {
        propertyUpdateID = UUID()
        propertyUpdateTask?.cancel()
        propertyUpdateTask = nil
    }

    private func resolveBoundTextProperties(
        elementIDs: [String],
        selectionIDs: [String]
    ) {
        boundTextResolutionTask?.cancel()
        boundTextResolvedSelectionIDs = selectionIDs
        guard let webView,
              let idsData = try? JSONEncoder().encode(elementIDs),
              let idsJSON = String(data: idsData, encoding: .utf8) else {
            boundTextResolvedSelectionIDs = nil
            return
        }

        boundTextResolutionTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let result = try await webView.callAsyncJavaScript(
                    """
                    const ids = JSON.parse(\(idsJSON.jsStringLiteral));
                    const elements =
                      window.excalidrawZHelper?.getElementsByIds?.(ids) ?? [];
                    return JSON.stringify(elements);
                    """,
                    arguments: [:],
                    contentWorld: .page
                )
                guard !Task.isCancelled,
                      self.selectedElementIDs == selectionIDs,
                      let json = result as? String,
                      let data = json.data(using: .utf8),
                      let elements = try JSONSerialization.jsonObject(
                        with: data
                      ) as? [[String: Any]],
                      let textElement = elements.first(where: {
                          $0["type"] as? String == "text"
                      }) else {
                    return
                }

                let textProperties =
                    ScreenAnnotationSelectionProperties.properties(
                        from: textElement
                    )
                selectedElementProperties.fontFamily =
                    textProperties.fontFamily
                selectedElementProperties.fontSize = textProperties.fontSize
                selectedElementProperties.textAlign = textProperties.textAlign
                presentedElementProperties.fontFamily =
                    textProperties.fontFamily
                presentedElementProperties.fontSize = textProperties.fontSize
                presentedElementProperties.textAlign =
                    textProperties.textAlign
            } catch {
                guard !Task.isCancelled else { return }
                boundTextResolvedSelectionIDs = nil
                report(error)
            }
        }
    }

    func select(_ tool: ExcalidrawTool) {
        guard let action = tool.screenAnnotationToolbarAction else { return }
        selectedTool = tool
        run(
            """
            window.excalidrawZHelper?.toggleToolbarAction('\(action)');
            """
        )
    }

    func toggleToolLock() {
        run("window.excalidrawZHelper?.toggleToolbarAction('Q');")
    }

    func handleToolbarAction(_ key: ExcalidrawWebView.ToolbarActionKey) {
        switch key {
            case .number(let number):
                if let tool = tool(forShortcutNumber: number) {
                    select(tool)
                }
            case .char(let character):
                run(
                    "window.excalidrawZHelper?.toggleToolbarAction('\(character)');"
                )
            case .space:
                run("window.excalidrawZHelper?.toggleToolbarAction(' ');")
            case .escape:
                break
        }
    }

    func setNativeShortcutHandlingEnabled(_ isEnabled: Bool) {
        (webView as? ExcalidrawWebView)?.shouldHandleInput = isEnabled
    }

    func undo() {
        run("window.excalidrawZHelper?.undo();")
    }

    func redo() {
        run("window.excalidrawZHelper?.redo();")
    }

    private func tool(forShortcutNumber number: Int) -> ExcalidrawTool? {
        let index = number == 0 ? 9 : number - 1
        guard toolbarTools.indices.contains(index) else { return nil }

        let tool = toolbarTools[index]
        return tool.supportsOrderedNumericShortcut ? tool : nil
    }

    private func updateSelectionViewportBounds() {
        guard let bounds = selectionSceneBounds else {
            selectionViewportBounds = nil
            return
        }

        selectionViewportBounds = CGRect(
            x: (bounds.minX + camera.scrollX) * camera.zoom,
            y: (bounds.minY + camera.scrollY) * camera.zoom,
            width: bounds.width * camera.zoom,
            height: bounds.height * camera.zoom
        )
    }

    private func markSelectionGeometryChanging() {
        selectionSettleTask?.cancel()
        isSelectionGeometryChanging = true
        selectionSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            self?.isSelectionGeometryChanging = false
        }
    }

    private func run(_ script: String) {
        guard let webView else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    script,
                    arguments: [:],
                    contentWorld: .page
                )
            } catch {
                report(error)
            }
        }
    }
}

private enum ScreenAnnotationCanvasPreparationError: LocalizedError {
    case invalidAcknowledgement

    var errorDescription: String? {
        "Excalidraw did not confirm the prepared canvas state."
    }
}

private extension String {
    var jsStringLiteral: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return result
    }
}

private extension ExcalidrawTool {
    var screenAnnotationToolbarAction: String? {
        switch self {
            case .webEmbed:
                "webEmbed"
            case .magicFrame:
                "wireframe"
            case .lasso:
                "lasso"
            default:
                keyEquivalent.map { String($0).uppercased() }
        }
    }
}
#endif
