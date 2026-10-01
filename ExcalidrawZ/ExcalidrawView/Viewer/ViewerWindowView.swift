//
//  ViewerWindowView.swift
//  ExcalidrawZ
//
//  Content of the read-only "Viewer" window: just the mirrored canvas.
//

#if os(macOS)
import SwiftUI
import WebKit

struct ViewerWindowView: View {
    @ObservedObject private var controller = ViewerMirrorController.shared

    var body: some View {
        ZStack {
            Color.clear
            if let session = controller.session {
                ViewerCanvasRepresentable(webView: session.core.webView)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task {
            controller.viewerDidAppear()
        }
        .onDisappear {
            controller.viewerDidDisappear()
        }
    }
}

private struct ViewerCanvasRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
