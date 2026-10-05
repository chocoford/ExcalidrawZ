//
//  ViewerMirrorController.swift
//  ExcalidrawZ
//
//  App-wide entry point for the Viewer window. Editor canvases register their
//  core; the Viewer mirrors the editor in the most recently key window.
//

#if os(macOS)
import AppKit
import Combine
import Logging

@MainActor
final class ViewerMirrorController: ObservableObject {
    static let shared = ViewerMirrorController()

    static let windowID = "viewer"

    @Published private(set) var session: ViewerMirrorSession?

    /// Follow mode: the Viewer pans/zooms with the editor. Off lets the
    /// presenter zoom in privately while the Viewer holds its view.
    @Published var isFollowingCamera: Bool {
        didSet {
            UserDefaults.standard.set(isFollowingCamera, forKey: Self.followDefaultsKey)
            session?.isFollowingCamera = isFollowingCamera
        }
    }

    @Published var pointerAppearance = ViewerPointerAppearance.load() {
        didSet {
            guard pointerAppearance != oldValue else { return }
            pointerAppearance.save()
            session?.setPointerAppearance(pointerAppearance)
        }
    }

    private static let followDefaultsKey = "ViewerFollowsEditorCamera"
    private let logger = Logger(label: "ViewerMirrorController")
    /// Registered editor cores, most recently key (or registered) first.
    private var editors: [WeakEditor] = []
    private weak var viewerWindow: NSWindow?
    private var keyWindowCancellable: AnyCancellable?
    private var closeWindowCancellable: AnyCancellable?

    private init() {
        isFollowingCamera = UserDefaults.standard.object(forKey: Self.followDefaultsKey) as? Bool ?? true
        keyWindowCancellable = NotificationCenter.default
            .publisher(for: NSWindow.didBecomeKeyNotification)
            .compactMap { $0.object as? NSWindow }
            .sink { [weak self] window in
                self?.windowDidBecomeKey(window)
            }
        closeWindowCancellable = NotificationCenter.default
            .publisher(for: NSWindow.willCloseNotification)
            .compactMap { $0.object as? NSWindow }
            .sink { [weak self] window in
                self?.windowWillClose(window)
            }
    }

    func register(editor: ExcalidrawCore) {
        editors.removeAll { $0.core === editor || $0.core == nil }
        editors.insert(WeakEditor(core: editor), at: 0)
        logger.debug("Registered editor core; total=\(editors.count)")
        session?.refreshEditorBinding()
    }

    func unregister(editor: ExcalidrawCore) {
        editors.removeAll { $0.core === editor || $0.core == nil }
        session?.refreshEditorBinding()
    }

    func editorDocumentDidChange(_ editor: ExcalidrawCore) {
        session?.editorDocumentDidChange(editor)
    }

    /// SwiftUI may reuse a Window scene's content after it closes. Prepare the
    /// session at the open action rather than relying on its view task restarting.
    func prepareForOpeningViewer() {
        FeatureDiscoveryTips.didOpenViewer()
        if session == nil {
            session = ViewerMirrorSession(
                isFollowingCamera: isFollowingCamera,
                pointerAppearance: pointerAppearance
            ) { [weak self] in
                self?.currentEditorCore
            }
        }
        session?.refreshEditorBinding()
    }

    func attachViewerWindow(_ window: NSWindow) {
        viewerWindow = window
    }

    private func windowWillClose(_ window: NSWindow) {
        guard window === viewerWindow else { return }
        session?.close()
        session = nil
    }

    private var currentEditorCore: ExcalidrawCore? {
        editors.removeAll { $0.core == nil }
        return editors.first?.core
    }

    private func windowDidBecomeKey(_ window: NSWindow) {
        if window === viewerWindow {
            // Also covers a cached scene reopened through the system Window menu.
            prepareForOpeningViewer()
            return
        }
        guard let index = editors.firstIndex(where: { $0.core?.webView.window === window }),
              index != 0 else {
            return
        }
        let editor = editors.remove(at: index)
        editors.insert(editor, at: 0)
        session?.refreshEditorBinding()
    }
}

private struct WeakEditor {
    weak var core: ExcalidrawCore?
}
#endif
