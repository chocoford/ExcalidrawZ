//
//  ViewerWindowView.swift
//  ExcalidrawZ
//
//  Read-only Viewer canvas. Display controls live in the editor window.
//

#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import ChocofordUI

struct ViewerWindowView: View {
    @ObservedObject private var controller = ViewerMirrorController.shared

    var body: some View {
        ZStack {
            if let session = controller.session {
                ViewerSessionContent(session: session)
                    // A new session owns a different WKWebView. Do not let
                    // NSViewRepresentable keep the closed session's native view.
                    .id(ObjectIdentifier(session))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .ignoresSafeArea()
        .window { window in
            Self.configureWindow(window)
            controller.attachViewerWindow(window)
        }
        .onAppear {
            controller.prepareForOpeningViewer()
        }
    }

    @MainActor
    private static func configureWindow(_ window: NSWindow) {
        // Secondary SwiftUI Window scenes default to an auxiliary role. Mark
        // Viewer as primary so it can own a full-screen space on macOS 13+.
        var behavior = window.collectionBehavior
        behavior.subtract([.auxiliary, .canJoinAllApplications, .fullScreenAuxiliary, .fullScreenNone])
        behavior.formUnion([.primary, .fullScreenPrimary])
        if behavior != window.collectionBehavior {
            window.collectionBehavior = behavior
        }
        // Pan gestures in the read-only canvas must not move the whole window.
        window.isMovableByWindowBackground = false
    }
}

private struct ViewerSessionContent: View {
    @ObservedObject var session: ViewerMirrorSession

    private var isReady: Bool {
        session.localConnectionState == .connected
    }

    var body: some View {
        ZStack {
            // Keep the WebView laid out while connecting so its initial
            // viewport has the actual window dimensions.
            ViewerCanvasRepresentable(webView: session.core.webView)
                .opacity(isReady ? 1 : 0)
                .allowsHitTesting(isReady)

            if !isReady {
                VStack(spacing: 12) {
                    switch session.localConnectionState {
                        case .waitingForEditor:
                            Text("Open a canvas to show it here.")
                        case .connecting:
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text(.localizable(.webViewLoadingText))
                        case .unsupported:
                            Image(systemName: "rectangle.slash")
                                .font(.largeTitle)
                            Text("This editor version does not support Viewer.")
                        case .failed:
                            Text("Unable to connect to the canvas.")
                            Button("Retry") { session.retryConnection() }
                        case .connected:
                            EmptyView()
                    }
                }
                .foregroundStyle(.secondary)
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
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
