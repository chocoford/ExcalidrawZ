#if os(macOS)
import AppKit
import Combine
import Foundation
import WebKit

@MainActor
final class ScreenAnnotationSession: ObservableObject {
    @Published private(set) var selectedTool: ExcalidrawTool = .arrow
    @Published private(set) var isReady = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var frozenBackgroundImage: NSImage?
    @Published private(set) var isCapturingBackground = false

    var isFrozen: Bool {
        frozenBackgroundImage != nil
    }

    private weak var webView: WKWebView?
    private var isPreparingCanvas = false

    init(frozenBackgroundImage: NSImage? = nil) {
        self.frozenBackgroundImage = frozenBackgroundImage
    }

    func attach(webView: WKWebView) {
        self.webView = webView
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
                    return transparency;
                    """,
                    arguments: [:],
                    contentWorld: .page
                )
                isPreparingCanvas = false
                isReady = true
                errorMessage = nil
            } catch {
                isPreparingCanvas = false
                report(error)
            }
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
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
            case "selection", "lasso":
                tool = .cursor
            case "rectangle":
                tool = .rectangle
            case "ellipse":
                tool = .ellipse
            case "arrow":
                tool = .arrow
            case "freedraw":
                tool = .freedraw
            case "text":
                tool = .text
            case "eraser":
                tool = .eraser
            default:
                tool = nil
        }
        if let tool {
            selectedTool = tool
        }
    }

    func select(_ tool: ExcalidrawTool) {
        guard let key = tool.keyEquivalent else { return }
        selectedTool = tool
        run(
            """
            window.excalidrawZHelper?.toggleToolbarAction('\(String(key).uppercased())');
            """
        )
    }

    func undo() {
        run("window.excalidrawZHelper?.undo();")
    }

    func redo() {
        run("window.excalidrawZHelper?.redo();")
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
#endif
