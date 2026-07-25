#if os(macOS)
import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class ScreenAnnotationSession: ObservableObject {
    @Published private(set) var selectedTool: ExcalidrawTool = .arrow
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

    func prepareCanvas() {
        guard !isReady, !isPreparingCanvas, let webView else { return }
        isPreparingCanvas = true

        Task {
            do {
                _ = try await webView.callAsyncJavaScript(
                    """
                    const helper = window.excalidrawZHelper;
                    const api = helper?._api;
                    if (!api || typeof helper.setCanvasTransparent !== "function") {
                      throw new Error("Screen annotation API is not ready.");
                    }

                    const transparency = helper.setCanvasTransparent(true);
                    if (!transparency?.applied) {
                      throw new Error("Canvas transparency was not applied.");
                    }

                    api.updateScene({
                      appState: {
                        gridModeEnabled: false,
                        zenModeEnabled: true,
                        viewModeEnabled: false,
                        showWelcomeScreen: false,
                        scrollX: 0,
                        scrollY: 0,
                        zoom: { value: 1 },
                        currentItemStrokeColor: "#ff3b30",
                      },
                    });
                    api.setActiveTool({ type: "arrow" });
                    helper.startCameraTracking?.();
                    await new Promise(resolve => {
                      requestAnimationFrame(() => requestAnimationFrame(resolve));
                    });
                    return transparency;
                    """,
                    arguments: [:],
                    contentWorld: .page
                )
                isPreparingCanvas = false
                webView.alphaValue = 1
                isReady = true
                errorMessage = nil
                webView.window?.makeFirstResponder(webView)
            } catch {
                isPreparingCanvas = false
                report(error)
            }
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func makeRawAnnotationDocument(
        backgroundImageData: Data,
        viewportRect: CGRect,
        selectionRect: CGRect?
    ) async throws -> ExcalidrawFile {
        guard let webView else {
            throw ScreenAnnotationSaveService.SaveError
                .annotationDocumentUnavailable
        }

        return try await ScreenAnnotationDocumentBridge.makeRawDocument(
            in: webView,
            backgroundImageData: backgroundImageData,
            viewportRect: viewportRect,
            selectionRect: selectionRect
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
