#if os(macOS)
import AppKit
import SwiftUI
import WebKit

struct ScreenAnnotationWebView: NSViewRepresentable {
    @ObservedObject var session: ScreenAnnotationSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "excalidrawZ")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.bootstrapScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = ExcalidrawWebView(
            frame: .zero,
            configuration: configuration
        ) { [weak session] key in
            Task { @MainActor in
                session?.handleToolbarAction(key)
            }
        }
        webView.alphaValue = 0
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        session.attach(webView: webView)

#if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        let url = URL(string: "http://127.0.0.1:8486/index.html")!
#else
        let url = URL(string: "http://127.0.0.1:8487/index.html")!
#endif
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.evaluateJavaScript(
            "window.excalidrawZHelper?.setCanvasTransparent(false);"
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let session: ScreenAnnotationSession

        init(session: ScreenAnnotationSession) {
            self.session = session
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                session.report(error)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            Task { @MainActor in
                session.report(error)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any],
                  let event = payload["event"] as? String else {
                return
            }

            Task { @MainActor in
                switch event {
                    case "onload":
                        session.prepareCanvas()
                    case "didSetActiveTool":
                        guard let data = payload["data"] as? [String: Any],
                              let type = data["type"] as? String else {
                            return
                        }
                        session.syncSelectedTool(type)
                    case "didToggleToolLock":
                        guard let isLocked = payload["data"] as? Bool else {
                            return
                        }
                        session.syncToolLock(isLocked)
                    case "didSelectElements":
                        guard let elements = payload["data"] as? [[String: Any]] else {
                            return
                        }
                        session.syncSelectedElements(elements)
                    case "didUnselectAllElements":
                        session.clearSelectedElements()
                    case "canvasInteractionChanged":
                        guard let isActive = payload["data"] as? Bool else {
                            return
                        }
                        session.setCanvasInteractionActive(isActive)
                    case "onCameraChanged":
                        guard let data = payload["data"] as? [String: Any] else {
                            return
                        }
                        session.syncCamera(data)
                    case "onFocus":
                        session.setNativeShortcutHandlingEnabled(false)
                    case "onBlur":
                        session.setNativeShortcutHandlingEnabled(true)
                    default:
                        break
                }
            }
        }
    }

    private static let bootstrapScript = """
    (() => {
      const style = document.createElement("style");
      style.textContent = `
        .excalidraw .App-menu_top,
        .excalidraw .App-menu_top__left,
        .excalidraw .App-menu_top__right,
        .excalidraw .App-bottom-bar,
        .excalidraw .layer-ui__wrapper__top-right,
        .excalidraw .layer-ui__wrapper__footer,
        .excalidraw .welcome-screen-center {
          display: none !important;
        }
      `;
      document.head.appendChild(style);

      window.addEventListener("wheel", event => {
        event.preventDefault();
        event.stopImmediatePropagation();
      }, { capture: true, passive: false });

      const setCanvasInteractionActive = isActive => {
        window.webkit?.messageHandlers?.excalidrawZ?.postMessage({
          event: "canvasInteractionChanged",
          data: isActive,
        });
      };
      const hasActiveCanvasInteraction = () => {
        const appState = window.excalidrawZHelper?._api?.getAppState?.();
        return Boolean(
          appState?.newElement ||
          appState?.multiElement ||
          appState?.resizingElement ||
          appState?.selectionElement ||
          appState?.isResizing ||
          appState?.isRotating ||
          appState?.editingTextElement ||
          appState?.selectedLinearElement?.isEditing
        );
      };
      const settleCanvasInteraction = () => {
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            setCanvasInteractionActive(hasActiveCanvasInteraction());
          });
        });
      };
      window.addEventListener("pointerdown", event => {
        if (event.button === 0) {
          setCanvasInteractionActive(true);
        }
      }, { capture: true });
      window.addEventListener("pointerup", event => {
        if (event.button === 0) {
          settleCanvasInteraction();
        }
      }, { capture: true });
      window.addEventListener("pointercancel", () => {
        settleCanvasInteraction();
      }, { capture: true });
      window.addEventListener("keyup", event => {
        if (event.key === "Escape") {
          settleCanvasInteraction();
        }
      }, { capture: true });
      window.addEventListener("blur", () => {
        setCanvasInteractionActive(false);
      });

    })();
    """
}
#endif
