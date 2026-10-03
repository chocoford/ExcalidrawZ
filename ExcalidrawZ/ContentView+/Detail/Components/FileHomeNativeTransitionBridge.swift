//
//  FileHomeNativeTransitionBridge.swift
//  ExcalidrawZ
//

#if os(macOS)
import SwiftUI
import AppKit

/// SwiftUI anchor preferences cannot cross separate hosting roots. Native
/// cards register their actual cover views instead; AppKit converts between
/// their coordinate systems only while a hero transition needs a source.
final class FileHomeNativeTransitionBridge: ObservableObject {
    @Published private(set) var revision = 0
    var activeFileID: String?
    private weak var destination: NSView?
    private var sources: [String: [WeakView]] = [:]
    private var notificationPending = false

    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    func registerSource(_ view: NSView, fileID: String) {
        var views = sources[fileID, default: []].filter { $0.view != nil }
        guard !views.contains(where: { $0.view === view }) else { return }
        views.append(WeakView(view))
        sources[fileID] = views
        if activeFileID == fileID { notifyTransition() }
    }

    func removeSource(_ view: NSView, fileID: String) {
        let remaining = sources[fileID, default: []].filter { $0.view != nil && $0.view !== view }
        sources[fileID] = remaining.isEmpty ? nil : remaining
    }

    func registerDestination(_ view: NSView) {
        destination = view
        if activeFileID != nil { notifyTransition() }
    }

    func sourceRect(for fileID: String) -> CGRect? {
        guard let destination, let window = destination.window else { return nil }
        let candidates = sources[fileID, default: []].reversed().compactMap(\.view).filter {
            $0.window === window && $0.bounds.width > 0 && $0.bounds.height > 0
        }
        // The home can still be hidden behind the editor at the beginning of
        // a close transaction. Its prewarmed card already has valid geometry.
        let source = candidates.first {
            !$0.isHiddenOrHasHiddenAncestor && !$0.visibleRect.isEmpty
        } ?? candidates.first
        return source.map { $0.convert($0.bounds, to: destination) }
    }

    func sourceBecameVisible(fileID: String) {
        if activeFileID == fileID { notifyTransition() }
    }

    private func notifyTransition() {
        guard !notificationPending else { return }
        notificationPending = true
        // Registration occurs during AppKit/SwiftUI layout. Publish on the
        // next turn, and never publish for ordinary scrolling or cell reuse.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notificationPending = false
            guard self.activeFileID != nil else { return }
            self.revision &+= 1
        }
    }
}

private struct FileHomeNativeTransitionBridgeKey: EnvironmentKey {
    static let defaultValue: FileHomeNativeTransitionBridge? = nil
}

private struct FileHomeUsesNativeTransitionSourceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var fileHomeUsesNativeTransitionSource: Bool {
        get { self[FileHomeUsesNativeTransitionSourceKey.self] }
        set { self[FileHomeUsesNativeTransitionSourceKey.self] = newValue }
    }

    var fileHomeNativeTransitionBridge: FileHomeNativeTransitionBridge? {
        get { self[FileHomeNativeTransitionBridgeKey.self] }
        set { self[FileHomeNativeTransitionBridgeKey.self] = newValue }
    }
}

struct FileHomeNativeTransitionProbe: NSViewRepresentable {
    let bridge: FileHomeNativeTransitionBridge
    var fileID: String?

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        guard nsView.bridge !== bridge || nsView.fileID != fileID else { return }
        nsView.unregister()
        nsView.bridge = bridge
        nsView.fileID = fileID
        if let fileID {
            bridge.registerSource(nsView, fileID: fileID)
        } else {
            bridge.registerDestination(nsView)
        }
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: ()) {
        nsView.unregister()
    }

    final class ProbeView: NSView {
        weak var bridge: FileHomeNativeTransitionBridge?
        var fileID: String?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, let fileID { bridge?.sourceBecameVisible(fileID: fileID) }
        }

        func unregister() {
            if let fileID { bridge?.removeSource(self, fileID: fileID) }
        }
    }
}
#endif
