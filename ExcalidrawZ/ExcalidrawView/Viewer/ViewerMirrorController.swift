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

    private let logger = Logger(label: "ViewerMirrorController")
    /// Registered editor cores, most recently key (or registered) first.
    private var editors: [WeakEditor] = []
    private var keyWindowCancellable: AnyCancellable?

    private init() {
        keyWindowCancellable = NotificationCenter.default
            .publisher(for: NSWindow.didBecomeKeyNotification)
            .compactMap { $0.object as? NSWindow }
            .sink { [weak self] window in
                self?.windowDidBecomeKey(window)
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

    func viewerDidAppear() {
        if session == nil {
            session = ViewerMirrorSession { [weak self] in
                self?.currentEditorCore
            }
        }
        session?.refreshEditorBinding()
    }

    func viewerDidDisappear() {
        session?.close()
        session = nil
    }

    private var currentEditorCore: ExcalidrawCore? {
        editors.removeAll { $0.core == nil }
        return editors.first?.core
    }

    private func windowDidBecomeKey(_ window: NSWindow) {
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
