//
//  OffscreenExcalidrawEditor.swift
//  ExcalidrawZ
//
//  Runs a scoped Excalidraw document operation without presenting a window.
//

import CoreGraphics
import Foundation
import WebKit
#if os(macOS)
import AppKit
#endif

@MainActor
final class OffscreenExcalidrawEditor {
    enum AppStatePolicy {
        case useEditorState
        case preserveLoadedDocument
    }

    enum EditorError: LocalizedError {
        case runtimeNotReady
        case documentLoadFailed(String)
        case documentNotLoaded

        var errorDescription: String? {
            switch self {
                case .runtimeNotReady:
                    "The background Excalidraw editor did not become ready."
                case .documentLoadFailed(let fileID):
                    "The Excalidraw file could not be loaded in the background editor: \(fileID)"
                case .documentNotLoaded:
                    "No Excalidraw document is loaded in the background editor."
            }
        }
    }

    private let core: ExcalidrawCore
    private var loadedFile: ExcalidrawFile?
    private var isClosed = false
#if os(macOS)
    private var hostPanel: OffscreenExcalidrawEditorPanel?
#endif

    var webView: WKWebView {
        core.webView
    }

    init(viewportSize: CGSize = CGSize(width: 1280, height: 800)) {
        let core = ExcalidrawCore()
        core.webView.frame = CGRect(origin: .zero, size: viewportSize)
        self.core = core
#if os(macOS)
        hostPanel = Self.makeHostPanel(
            for: core.webView,
            viewportSize: viewportSize
        )
#endif
        core.webView.load(URLRequest(url: Self.pageURL))
    }

    static func withEditor<Result>(
        viewportSize: CGSize = CGSize(width: 1280, height: 800),
        operation: @MainActor (OffscreenExcalidrawEditor) async throws -> Result
    ) async throws -> Result {
        let startedAt = Date()
        await OffscreenExcalidrawOperationTracker.shared.begin()
        let editor = OffscreenExcalidrawEditor(viewportSize: viewportSize)
        do {
            try await editor.waitUntilReady()
            editor.core.logger.debug(
                "Offscreen editor ready durationMs=\(Self.milliseconds(from: startedAt))"
            )
            let result = try await operation(editor)
            editor.close()
            await OffscreenExcalidrawOperationTracker.shared.finish()
            return result
        } catch {
            editor.close()
            await OffscreenExcalidrawOperationTracker.shared.finish()
            throw error
        }
    }

    static func waitForPendingOperations() async {
        await OffscreenExcalidrawOperationTracker.shared.waitUntilIdle()
    }

    func load(_ file: ExcalidrawFile) async throws {
        guard !isClosed else {
            throw EditorError.runtimeNotReady
        }
        guard let content = file.content else {
            throw EditorError.documentLoadFailed(file.id)
        }

        let outcome = await core.documentSyncController.load(
            fileID: file.id,
            data: content,
            force: true,
            validateCurrentParentFile: false
        )
        guard outcome.didLoad else {
            throw EditorError.documentLoadFailed(file.id)
        }
        loadedFile = file
    }

    func snapshot(
        appStatePolicy: AppStatePolicy = .useEditorState
    ) async throws -> ExcalidrawFile {
        guard var loadedFile,
              let existingContent = loadedFile.content else {
            throw EditorError.documentNotLoaded
        }

        let snapshot = try await core.getCurrentFileSnapshot()
        var documentData = try snapshot.documentData()
        switch appStatePolicy {
            case .useEditorState:
                documentData = try await ExcalidrawViewportStateStore.shared
                    .contentData(
                        documentData,
                        preservingViewportFrom: existingContent
                    )
            case .preserveLoadedDocument:
                documentData = try Self.documentData(
                    documentData,
                    preservingAppStateFrom: existingContent
                )
        }
        documentData = try ExcalidrawDocumentAppStatePersistence.documentData(
            documentData,
            settingNativeFileName: loadedFile.name
        )

        let preparedUpdate = try ExcalidrawFile.prepareCanvasDataUpdate(
            existingContent: existingContent,
            data: .init(
                documentData: documentData,
                elements: nil,
                files: [:]
            )
        )
        loadedFile.apply(preparedUpdate)
        return loadedFile
    }

    private static func documentData(
        _ documentData: Data,
        preservingAppStateFrom sourceData: Data
    ) throws -> Data {
        guard var documentObject = try JSONSerialization.jsonObject(
            with: documentData
        ) as? [String: Any],
              let sourceObject = try JSONSerialization.jsonObject(
                with: sourceData
              ) as? [String: Any],
              let sourceAppState = sourceObject["appState"] else {
            return documentData
        }

        documentObject["appState"] = sourceAppState
        return try JSONSerialization.data(withJSONObject: documentObject)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        loadedFile = nil
        core.documentSyncController.resetFileLoadState()

        let webView = core.webView
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.toolbarActionHandler = { _ in }
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "excalidrawZ")
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "consoleHandler")
        webView.removeFromSuperview()
#if os(macOS)
        hostPanel?.orderOut(nil)
        hostPanel?.contentView = nil
        hostPanel?.close()
        hostPanel = nil
#endif
    }

    private func waitUntilReady(timeout: TimeInterval = 15) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if core.isDocumentLoaded,
               !core.isNavigating,
               !core.webView.isLoading {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        core.logger.warning(
            "Offscreen editor readiness timed out isDocumentLoaded=\(core.isDocumentLoaded) isNavigating=\(core.isNavigating) webView.isLoading=\(core.webView.isLoading)"
        )
        throw EditorError.runtimeNotReady
    }

    private static func milliseconds(from start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1_000).rounded())
    }

#if os(macOS)
    private static func makeHostPanel(
        for webView: WKWebView,
        viewportSize: CGSize
    ) -> OffscreenExcalidrawEditorPanel {
        let panel = OffscreenExcalidrawEditorPanel(
            contentRect: CGRect(origin: .zero, size: viewportSize)
        )
        let contentView = NSView(
            frame: CGRect(origin: .zero, size: viewportSize)
        )
        webView.frame = contentView.bounds
        webView.autoresizingMask = [.width, .height]
        contentView.addSubview(webView)
        panel.contentView = contentView

        if let screen = NSScreen.main {
            panel.setFrameOrigin(screen.frame.origin)
        }
        panel.orderFrontRegardless()
        return panel
    }
#endif

    private static var pageURL: URL {
#if DEBUG
        URL(string: "http://127.0.0.1:8486/index.html")!
#else
        URL(string: "http://127.0.0.1:8487/index.html")!
#endif
    }
}

#if os(macOS)
private final class OffscreenExcalidrawEditorPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        alphaValue = 0.001
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        level = .screenSaver
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
#endif

private actor OffscreenExcalidrawOperationTracker {
    static let shared = OffscreenExcalidrawOperationTracker()

    private var activeOperationCount = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func begin() {
        activeOperationCount += 1
    }

    func finish() {
        activeOperationCount = max(activeOperationCount - 1, 0)
        guard activeOperationCount == 0 else { return }

        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilIdle() async {
        guard activeOperationCount > 0 else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }
}
