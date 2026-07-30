#if os(macOS)
import AppKit
import Logging
import WebKit

@MainActor
final class ScreenAnnotationWebRuntime: NSObject {
    private(set) var webView: ExcalidrawWebView!

    private let logger = Logger(label: "ScreenAnnotationWebRuntime")
    private weak var activeSession: ScreenAnnotationSession?
    private var isPageReady = false
    private var isNavigationLoading = false
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var loadStartedAt = Date()
    private var loadGeneration = 0
    private var currentNavigation: WKNavigation?

    override init() {
        super.init()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "excalidrawZ")
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
        ) { [weak self] key in
            Task { @MainActor in
                self?.activeSession?.handleToolbarAction(key)
            }
        }
        webView.alphaValue = 0
        webView.navigationDelegate = self
#if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
#endif
        self.webView = webView
        applyTransparentPresentation()
        loadPage(resetRetryAttempt: true)
    }

    func bind(_ session: ScreenAnnotationSession) {
        applyTransparentPresentation()

        guard activeSession !== session else {
            if isPageReady {
                session.prepareCanvas()
            }
            return
        }

        if let activeSession {
            activeSession.detach(webView: webView)
        }
        activeSession = session
        webView.alphaValue = 0
        session.attach(webView: webView)

        if isPageReady {
            logger.debug("Binding prewarmed screen annotation WebView")
            session.prepareCanvas()
        } else if !isNavigationLoading {
            logger.debug("Screen annotation WebView is not prewarmed; loading on demand")
            loadPage(resetRetryAttempt: true)
        }
    }

    func unbind(_ session: ScreenAnnotationSession) {
        guard activeSession === session else { return }

        retryTask?.cancel()
        retryTask = nil
        activeSession = nil
        session.detach(webView: webView)
    }

    private func loadPage(resetRetryAttempt: Bool = false) {
        retryTask?.cancel()
        retryTask = nil
        if resetRetryAttempt {
            retryAttempt = 0
        }
        isPageReady = false
        isNavigationLoading = true
        loadStartedAt = Date()
        webView.alphaValue = 0
        webView.stopLoading()
        loadGeneration += 1
        currentNavigation = webView.load(
            URLRequest(
                url: Self.pageURL(generation: loadGeneration)
            )
        )
    }

    private func handleNavigationFailure(_ error: Error) {
        isPageReady = false
        isNavigationLoading = false
        activeSession?.report(error)
        let shouldRetry = activeSession != nil || retryAttempt < 8
        guard shouldRetry else {
            logger.warning(
                "Screen annotation WebView prewarm stopped after \(retryAttempt) retries: \(error)"
            )
            return
        }

        retryAttempt += 1
        let delay = min(
            250_000_000 * UInt64(1 << min(retryAttempt - 1, 3)),
            2_000_000_000
        )
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.loadPage()
        }
    }

    private static func pageURL(generation: Int) -> URL {
#if DEBUG
        let baseURL = URL(string: "http://127.0.0.1:8486/index.html")!
#else
        let baseURL = URL(string: "http://127.0.0.1:8487/index.html")!
#endif
        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(
                name: "screenAnnotationGeneration",
                value: String(generation)
            ),
        ]
        return components.url!
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

extension ScreenAnnotationWebRuntime: WKNavigationDelegate, WKScriptMessageHandler {
    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard navigation === currentNavigation else { return }
        handleNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard navigation === currentNavigation else { return }
        handleNavigationFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isPageReady = false
        isNavigationLoading = false
        loadPage(resetRetryAttempt: true)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let payload = message.body as? [String: Any],
              let event = payload["event"] as? String else {
            return
        }
        let receivedGeneration = messageGeneration(message)
        guard receivedGeneration == loadGeneration else {
            if event == "onload" {
                logger.debug(
                    "Ignored stale screen annotation onload receivedGeneration=\(receivedGeneration.map { String($0) } ?? "nil") currentGeneration=\(loadGeneration)"
                )
            }
            return
        }

        switch event {
            case "onload":
                isPageReady = true
                isNavigationLoading = false
                applyTransparentPresentation()
                retryTask?.cancel()
                retryTask = nil
                retryAttempt = 0
                let durationMs = Date().timeIntervalSince(loadStartedAt) * 1_000
                let mode = activeSession == nil ? "prewarm" : "onDemand"
                logger.debug(
                    "Screen annotation WebView ready mode=\(mode) durationMs=\(String(format: "%.1f", durationMs))"
                )
                activeSession?.prepareCanvas()
            case "didSetActiveTool":
                guard let data = payload["data"] as? [String: Any],
                      let type = data["type"] as? String else {
                    return
                }
                activeSession?.syncSelectedTool(type)
            case "didToggleToolLock":
                guard let isLocked = payload["data"] as? Bool else {
                    return
                }
                activeSession?.syncToolLock(isLocked)
            case "didSelectElements":
                guard let elements = payload["data"] as? [[String: Any]] else {
                    return
                }
                activeSession?.syncSelectedElements(elements)
            case "didUnselectAllElements":
                activeSession?.clearSelectedElements()
            case "canvasInteractionChanged":
                guard let isActive = payload["data"] as? Bool else {
                    return
                }
                activeSession?.setCanvasInteractionActive(isActive)
            case "onCameraChanged":
                guard let data = payload["data"] as? [String: Any] else {
                    return
                }
                activeSession?.syncCamera(data)
            case "onFocus":
                activeSession?.setNativeShortcutHandlingEnabled(false)
            case "onBlur":
                activeSession?.setNativeShortcutHandlingEnabled(true)
            default:
                break
        }
    }

    private func messageGeneration(_ message: WKScriptMessage) -> Int? {
        guard let url = message.frameInfo.request.url,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ),
              let rawValue = components.queryItems?.first(
                where: { $0.name == "screenAnnotationGeneration" }
              )?.value else {
            return nil
        }
        return Int(rawValue)
    }
}

private extension ScreenAnnotationWebRuntime {
    func applyTransparentPresentation() {
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
#endif
