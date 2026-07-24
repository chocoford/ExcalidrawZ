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

        let webView = WKWebView(frame: .zero, configuration: configuration)
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

    })();
    """
}
#endif
