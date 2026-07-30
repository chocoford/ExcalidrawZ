#if os(macOS)
import AppKit
import SwiftUI

struct ScreenAnnotationWebView: NSViewRepresentable {
    @ObservedObject var session: ScreenAnnotationSession
    let runtime: ScreenAnnotationWebRuntime

    func makeCoordinator() -> Coordinator {
        Coordinator(runtime: runtime, session: session)
    }

    func makeNSView(context: Context) -> ScreenAnnotationWebViewHost {
        let host = ScreenAnnotationWebViewHost()
        host.attach(runtime.webView)
        context.coordinator.scheduleBinding()
        return host
    }

    func updateNSView(
        _ host: ScreenAnnotationWebViewHost,
        context: Context
    ) {}

    static func dismantleNSView(
        _ host: ScreenAnnotationWebViewHost,
        coordinator: Coordinator
    ) {
        coordinator.cancelBinding()
        host.detach()
        Task { @MainActor in
            coordinator.runtime.unbind(coordinator.session)
        }
    }

    @MainActor
    final class Coordinator {
        let runtime: ScreenAnnotationWebRuntime
        let session: ScreenAnnotationSession
        private var bindingTask: Task<Void, Never>?

        init(
            runtime: ScreenAnnotationWebRuntime,
            session: ScreenAnnotationSession
        ) {
            self.runtime = runtime
            self.session = session
        }

        func scheduleBinding() {
            bindingTask?.cancel()
            bindingTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.runtime.bind(self.session)
                self.bindingTask = nil
            }
        }

        func cancelBinding() {
            bindingTask?.cancel()
            bindingTask = nil
        }
    }
}

@MainActor
final class ScreenAnnotationWebViewHost: NSView {
    private weak var attachedWebView: NSView?

    func attach(_ webView: NSView) {
        guard attachedWebView !== webView || webView.superview !== self else {
            return
        }
        attachedWebView?.removeFromSuperview()
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        attachedWebView = webView
    }

    func detach() {
        if attachedWebView?.superview === self {
            attachedWebView?.removeFromSuperview()
        }
        attachedWebView = nil
    }
}
#endif
