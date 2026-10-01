//
//  ViewerMirrorSession.swift
//  ExcalidrawZ
//
//  Owns the Viewer WebView and pumps throttled scene deltas into it from the
//  editor. One session lives for as long as the Viewer window is open.
//

#if os(macOS)
import AppKit
import Combine
import Logging
import WebKit

@MainActor
final class ViewerMirrorSession: ObservableObject {
    /// Mirror the editor's scroll/zoom into the Viewer.
    @Published var isFollowingCamera = true

    let core = ExcalidrawCore()

    private let logger = Logger(label: "ViewerMirrorSession")
    private let editorProvider: () -> ExcalidrawCore?
    /// Upper bound on sync frequency (~15 Hz).
    private let minimumSyncInterval: TimeInterval = 1.0 / 15.0

    private weak var editor: ExcalidrawCore?
    private var editorCancellables: Set<AnyCancellable> = []
    private var viewerCancellables: Set<AnyCancellable> = []
    private var syncTask: Task<Void, Never>?
    private var bindingRetryTask: Task<Void, Never>?
    private var pendingSync = false
    private var needsFullSync = true
    private var isViewerPrepared = false
    private var lastSyncAt = Date.distantPast
    private var isClosed = false

    init(editorProvider: @escaping () -> ExcalidrawCore?) {
        self.editorProvider = editorProvider

        core.webView.configuration.userContentController.addUserScript(
            WKUserScript(
                source: ViewerMirrorScripts.viewerChromeStyle,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        core.webView.load(URLRequest(url: Self.pageURL))

        Publishers.CombineLatest(core.$isDocumentLoaded, core.$isNavigating)
            .map { isDocumentLoaded, isNavigating in
                isDocumentLoaded && !isNavigating
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                self?.isViewerPrepared = false
                self?.needsFullSync = true
                if isReady {
                    self?.requestSync()
                }
            }
            .store(in: &viewerCancellables)

        $isFollowingCamera
            .dropFirst()
            .sink { [weak self] isFollowing in
                guard isFollowing else { return }
                self?.needsFullSync = true
                self?.requestSync()
            }
            .store(in: &viewerCancellables)
    }

    /// Re-resolves the editor to mirror. Safe to call often; it only
    /// resubscribes when the editor instance actually changed.
    func refreshEditorBinding() {
        let resolved = editorProvider()
        guard resolved !== editor || resolved == nil else {
            requestSync()
            return
        }

        editorCancellables.removeAll()
        editor = resolved
        needsFullSync = true
        logger.debug("Viewer bound to editor: \(resolved == nil ? "none" : "ok")")

        guard let resolved else {
            scheduleEditorBindingRetry()
            return
        }
        resolved.$viewerMirrorDirtyToken
            .dropFirst()
            .sink { [weak self] _ in
                self?.requestSync()
            }
            .store(in: &editorCancellables)
        resolved.$isDocumentLoaded
            .removeDuplicates()
            .sink { [weak self] _ in
                // The page (and our subscription living on `window`) was reloaded.
                self?.needsFullSync = true
                self?.requestSync()
            }
            .store(in: &editorCancellables)
        requestSync()
    }

    /// No editor is available yet (e.g. the Viewer was opened before any file).
    /// Poll until one shows up; this is cheap and only runs while unbound.
    private func scheduleEditorBindingRetry() {
        guard bindingRetryTask == nil, !isClosed else { return }
        bindingRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.bindingRetryTask = nil
            self.refreshEditorBinding()
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        syncTask?.cancel()
        syncTask = nil
        bindingRetryTask?.cancel()
        bindingRetryTask = nil
        editorCancellables.removeAll()
        viewerCancellables.removeAll()
        editor = nil

        // Mirror `OffscreenExcalidrawEditor.close()`: the script message
        // handlers retain the core, so drop them explicitly.
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

    // MARK: - Sync loop

    private func requestSync() {
        guard !isClosed else { return }
        pendingSync = true
        scheduleSyncIfNeeded()
    }

    private func scheduleSyncIfNeeded() {
        guard pendingSync, syncTask == nil else { return }
        syncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let wait = self.minimumSyncInterval - Date().timeIntervalSince(self.lastSyncAt)
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled, !self.isClosed else {
                self.syncTask = nil
                return
            }
            self.pendingSync = false
            await self.performSync()
            self.lastSyncAt = Date()
            self.syncTask = nil
            self.scheduleSyncIfNeeded()
        }
    }

    private var isViewerReady: Bool {
        core.isDocumentLoaded && !core.isNavigating && !core.webView.isLoading
    }

    private func performSync() async {
        guard isViewerReady,
              let editor,
              editor.isDocumentLoaded,
              !editor.isNavigating else {
            return
        }

        do {
            if !isViewerPrepared {
                _ = try await core.webView.callAsyncJavaScript(
                    ViewerMirrorScripts.viewerPrepare,
                    arguments: [:],
                    contentWorld: .page
                )
                isViewerPrepared = true
            }

            let full = needsFullSync
            if full {
                _ = try await editor.webView.callAsyncJavaScript(
                    ViewerMirrorScripts.editorSubscribe,
                    arguments: [:],
                    contentWorld: .page
                )
            }

            let delta = try await editor.webView.callAsyncJavaScript(
                ViewerMirrorScripts.editorTakeDelta,
                arguments: ["full": full],
                contentWorld: .page
            )
            guard let payload = delta as? String else {
                needsFullSync = false
                return
            }

            let result = try await core.webView.callAsyncJavaScript(
                ViewerMirrorScripts.viewerApplyDelta,
                arguments: [
                    "payload": payload,
                    "followCamera": isFollowingCamera,
                ],
                contentWorld: .page
            )
            if result as? String == "resync" {
                needsFullSync = true
                requestSync()
            } else {
                if full {
                    logger.debug("Viewer full sync applied (\(payload.utf8.count) bytes)")
                }
                needsFullSync = false
            }
        } catch {
            logger.warning("Viewer sync failed: \(error)")
            needsFullSync = true
        }
    }

    private static var pageURL: URL {
#if DEBUG
        URL(string: "http://127.0.0.1:8486/index.html")!
#else
        URL(string: "http://127.0.0.1:8487/index.html")!
#endif
    }
}
#endif
