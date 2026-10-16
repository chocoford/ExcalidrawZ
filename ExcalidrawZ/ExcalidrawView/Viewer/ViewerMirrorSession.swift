//
//  ViewerMirrorSession.swift
//  ExcalidrawZ
//
//  Owns the Viewer WebView and its local connection for the lifetime of the window.
//

import Observation
#if os(macOS)
import Combine
import Foundation
import WebKit

@MainActor
@Observable
final class ViewerMirrorSession {
    var isFollowingCamera: Bool {
        didSet {
            guard isFollowingCamera != oldValue else { return }
            localConnection?.setFollowing(isFollowingCamera)
        }
    }
    private(set) var localConnectionState: ViewerLocalConnection.State = .waitingForEditor
    private(set) var supportsPointerAppearance = false

    let core = ExcalidrawCore()

    private let editorProvider: () -> ExcalidrawCore?
    private weak var editor: ExcalidrawCore?
    @ObservationIgnored private var editorObservation: ObservationSubscription?
    @ObservationIgnored private var viewerObservation: ObservationSubscription?
    private var localConnection: ViewerLocalConnection?
    private var isClosed = false

    init(
        isFollowingCamera: Bool,
        pointerAppearance: ViewerPointerAppearance,
        editorProvider: @escaping () -> ExcalidrawCore?
    ) {
        self.isFollowingCamera = isFollowingCamera
        self.editorProvider = editorProvider

        // The Viewer must not dispatch editor toolbar commands.
        core.webView.toolbarActionHandler = { _ in }
        let contentController = core.webView.configuration.userContentController
        contentController.addUserScript(
            WKUserScript(source: ViewerLocalScripts.bootstrap,
                         injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        contentController.addUserScript(
            WKUserScript(source: ViewerLocalScripts.chromeStyle,
                         injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        localConnection = ViewerLocalConnection(
            viewer: core,
            isFollowing: isFollowingCamera,
            pointerAppearance: pointerAppearance,
            onStateChange: { [weak self] state in self?.localConnectionState = state },
            onPointerSupportChange: { [weak self] supported in
                self?.supportsPointerAppearance = supported
            }
        )
        core.webView.load(URLRequest(url: Self.pageURL))

        viewerObservation = ObservationSubscription { [core] in
            core.isDocumentLoaded && !core.isNavigating
        } onChange: { [weak self] _ in
            guard let self else { return }
            self.localConnection?.update(editor: self.editor)
        }
    }

    /// Editors register when their canvas appears, so no polling is needed
    /// while the Viewer waits for a canvas to open.
    func refreshEditorBinding() {
        guard !isClosed else { return }
        let resolved = editorProvider()
        guard resolved !== editor else {
            localConnection?.update(editor: editor)
            return
        }

        editorObservation?.cancel()
        editorObservation = nil
        editor = resolved
        if let resolved {
            editorObservation = ObservationSubscription { [weak resolved] in
                resolved?.isDocumentLoaded == true && resolved?.isNavigating == false
            } onChange: { [weak self] _ in
                guard let self else { return }
                self.localConnection?.update(editor: self.editor)
            }
        }
        localConnection?.update(editor: resolved)
    }

    func editorDocumentDidChange(_ core: ExcalidrawCore) {
        guard !isClosed, core === editor else { return }
        localConnection?.update(editor: core, force: true)
    }

    func retryConnection() {
        localConnection?.update(editor: editor, force: true)
    }

    func setPointerAppearance(_ appearance: ViewerPointerAppearance) {
        localConnection?.setPointerAppearance(appearance)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        localConnection?.close()
        localConnection = nil
        editorObservation?.cancel()
        editorObservation = nil
        viewerObservation?.cancel()
        viewerObservation = nil
        editor = nil

        // Script message handlers retain the core; release them when the window closes.
        let webView = core.webView
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.toolbarActionHandler = { _ in }
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "excalidrawZ")
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "consoleHandler")
        webView.configuration.userContentController.removeAllUserScripts()
        webView.removeFromSuperview()
    }

    private static var pageURL: URL {
        URL(string: "http://127.0.0.1:\(ExcalidrawServer.port)/index.html")!
    }
}
#endif
