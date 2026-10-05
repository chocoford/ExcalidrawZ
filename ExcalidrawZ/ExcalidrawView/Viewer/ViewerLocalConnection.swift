//
//  ViewerLocalConnection.swift
//  ExcalidrawZ
//
//  Pairs Web runtimes and controls their lifetime. Scene data stays on the
//  WebSocket path instead of being polled through the main-actor JS bridge.
//

#if os(macOS)
import Foundation
import Logging
import WebKit

@MainActor
final class ViewerLocalConnection {
    enum State: Equatable {
        case waitingForEditor
        case connecting
        case connected
        case unsupported
        case failed
    }

    private struct Binding {
        let id: String
        let editor: ExcalidrawCore
        let viewer: ExcalidrawCore
        let fileID: String
    }

    private enum ConnectionError: Error {
        case unsupported
    }

    private let viewer: ExcalidrawCore
    private let onStateChange: (State) -> Void
    private let onPointerSupportChange: (Bool) -> Void
    private let logger = Logger(label: "ViewerLocalConnection")
    private weak var desiredEditor: ExcalidrawCore?
    private var requestedFileID: String?
    private var binding: Binding?
    private var awaitingPresentationSessionID: String?
    private var connectionTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?
    private var pointerAppearanceTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var isFollowing: Bool
    private var pointerAppearance: ViewerPointerAppearance
    private var supportsPointerAppearance = false {
        didSet {
            if oldValue != supportsPointerAppearance {
                onPointerSupportChange(supportsPointerAppearance)
            }
        }
    }
    private var isClosed = false
    private var state: State = .waitingForEditor {
        didSet {
            if oldValue != state { onStateChange(state) }
        }
    }

    init(
        viewer: ExcalidrawCore,
        isFollowing: Bool,
        pointerAppearance: ViewerPointerAppearance,
        onStateChange: @escaping (State) -> Void,
        onPointerSupportChange: @escaping (Bool) -> Void
    ) {
        self.viewer = viewer
        self.isFollowing = isFollowing
        self.pointerAppearance = pointerAppearance
        self.onStateChange = onStateChange
        self.onPointerSupportChange = onPointerSupportChange
    }

    func update(editor: ExcalidrawCore?, force: Bool = false) {
        guard !isClosed else { return }
        let fileID = readyFileID(in: editor)
        // An existing file can be waiting for either WebView or a file load.
        // Only an actual empty editor should show the open-canvas placeholder.
        let pendingState: State = selectedFileID(in: editor) == nil ? .waitingForEditor : .connecting
        let isSameRequest = desiredEditor === editor && requestedFileID == fileID
        desiredEditor = editor
        requestedFileID = fileID
        if !force, isSameRequest, connectionTask != nil {
            if fileID == nil { state = pendingState }
            return
        }
        if !force, let binding,
           binding.editor === editor, binding.fileID == fileID,
           state == .connected || connectionTask != nil {
            return
        }
        if fileID == nil, binding == nil, connectionTask == nil {
            state = pendingState
            return
        }

        revision &+= 1
        let expectedRevision = revision
        let previousTask = connectionTask
        let previousBinding = binding
        let wasAwaitingPresentation = awaitingPresentationSessionID != nil
            && previousBinding?.id == awaitingPresentationSessionID
        previousTask?.cancel()
        followTask?.cancel()
        pointerAppearanceTask?.cancel()
        supportsPointerAppearance = false
        binding = nil
        awaitingPresentationSessionID = nil
        state = fileID == nil ? pendingState : .connecting

        // Serialize teardown and setup, including JS calls already in flight.
        // A canceled start must finish before a new start can replace it.
        connectionTask = Task { @MainActor [weak self] in
            if let previousBinding {
                await ViewerLocalRelay.shared.endSession(previousBinding.id)
                // Both starts have completed by this phase. Stopping now
                // rejects the read-only readiness wait without its timeout.
                if wasAwaitingPresentation { await Self.stop(previousBinding) }
            }
            await previousTask?.value
            if let previousBinding, !wasAwaitingPresentation { await Self.stop(previousBinding) }
            guard let self, self.isCurrent(expectedRevision) else { return }
            defer {
                if self.revision == expectedRevision { self.connectionTask = nil }
            }
            guard let editor, let fileID,
                  self.readyFileID(in: editor) == fileID else { return }

            do {
                guard try await Self.isSupported(editor),
                      try await Self.isSupported(self.viewer),
                      try await Self.supportsPresentationReadiness(self.viewer) else {
                    throw ConnectionError.unsupported
                }
                try self.checkCurrent(expectedRevision)

                let supportsPointerAppearance = try await self.viewer.webView.callAsyncJavaScript(
                    ViewerLocalScripts.supportsPointerAppearance,
                    arguments: [:], contentWorld: .page
                ) as? Bool == true
                try self.checkCurrent(expectedRevision)

                let id = await ViewerLocalRelay.shared.createSession()
                guard self.isCurrent(expectedRevision) else {
                    await ViewerLocalRelay.shared.endSession(id)
                    return
                }
                let binding = Binding(id: id, editor: editor, viewer: self.viewer, fileID: fileID)
                self.binding = binding

                // Both runtimes must request/send initialization on reconnect;
                // messages emitted before the other peer connects are not stored.
                try await Self.start(binding.viewer, role: .viewer, binding: binding,
                                     isFollowing: self.isFollowing,
                                     pointerAppearance: self.pointerAppearance)
                try self.checkCurrent(expectedRevision)
                try await Self.start(binding.editor, role: .editor, binding: binding,
                                     isFollowing: self.isFollowing,
                                     pointerAppearance: self.pointerAppearance)
                try self.checkCurrent(expectedRevision)
                // Opening the sockets does not mean the scene is visible yet.
                // Wait for the first snapshot and its initial viewport to paint.
                self.awaitingPresentationSessionID = binding.id
                defer {
                    if self.awaitingPresentationSessionID == binding.id {
                        self.awaitingPresentationSessionID = nil
                    }
                }
                try await Self.waitUntilReady(binding)
                try self.checkCurrent(expectedRevision)
                guard self.readyFileID(in: editor) == fileID else {
                    self.update(editor: self.desiredEditor, force: true)
                    return
                }
                self.state = .connected
                self.supportsPointerAppearance = supportsPointerAppearance
                self.setFollowing(self.isFollowing)
                self.setPointerAppearance(self.pointerAppearance)
                self.logger.debug("Local Viewer session connected")
            } catch {
                guard self.revision == expectedRevision else { return }
                if let binding = self.binding {
                    self.binding = nil
                    await Self.stop(binding)
                }
                guard self.isCurrent(expectedRevision) else { return }
                if case ConnectionError.unsupported = error {
                    self.state = .unsupported
                } else {
                    self.state = .failed
                    self.logger.warning("Local Viewer connection failed: \(error)")
                }
            }
        }
    }

    func setFollowing(_ enabled: Bool) {
        isFollowing = enabled
        followTask?.cancel()
        guard !isClosed, state == .connected, let binding else { return }
        followTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.binding?.id == binding.id else { return }
            do {
                _ = try await binding.viewer.webView.callAsyncJavaScript(
                    ViewerLocalScripts.setFollowing,
                    arguments: ["sessionId": binding.id, "enabled": self.isFollowing],
                    contentWorld: .page
                )
            } catch {
                guard self.binding?.id == binding.id, !Task.isCancelled else { return }
                self.logger.warning("Failed to update local Viewer following: \(error)")
            }
        }
    }

    func setPointerAppearance(_ appearance: ViewerPointerAppearance) {
        pointerAppearance = appearance
        let previousTask = pointerAppearanceTask
        previousTask?.cancel()
        guard !isClosed, state == .connected, supportsPointerAppearance,
              let binding else { return }
        pointerAppearanceTask = Task { @MainActor [weak self] in
            // ColorPicker can emit changes rapidly. Finish any in-flight call
            // before applying the latest value to this session.
            await previousTask?.value
            guard let self, !Task.isCancelled, self.binding?.id == binding.id,
                  self.pointerAppearance == appearance else { return }
            do {
                _ = try await binding.viewer.webView.callAsyncJavaScript(
                    ViewerLocalScripts.setPointerAppearance,
                    arguments: [
                        "sessionId": binding.id,
                        "visible": appearance.isVisible,
                        "color": (appearance.colorHex as Any?) ?? NSNull(),
                    ],
                    contentWorld: .page
                )
            } catch {
                guard self.binding?.id == binding.id, !Task.isCancelled else { return }
                self.logger.warning("Failed to update local Viewer pointer appearance: \(error)")
            }
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        revision &+= 1
        desiredEditor = nil
        requestedFileID = nil
        followTask?.cancel()
        pointerAppearanceTask?.cancel()
        let previousTask = connectionTask
        let previousBinding = binding
        let wasAwaitingPresentation = awaitingPresentationSessionID != nil
            && previousBinding?.id == awaitingPresentationSessionID
        previousTask?.cancel()
        binding = nil
        awaitingPresentationSessionID = nil
        connectionTask = nil
        // Cleanup must finish even if the owning window has disappeared.
        Task { @MainActor in
            if let previousBinding {
                await ViewerLocalRelay.shared.endSession(previousBinding.id)
                if wasAwaitingPresentation { await Self.stop(previousBinding) }
            }
            await previousTask?.value
            if let previousBinding, !wasAwaitingPresentation { await Self.stop(previousBinding) }
        }
    }

    private func selectedFileID(in editor: ExcalidrawCore?) -> String? {
        // Collaboration has its own runtime; the registered normal canvas can
        // remain mounted underneath it while its editor is hidden.
        if case .collaborationFile = editor?.parent?.fileState.currentActiveFile { return nil }
        return editor?.parent?.fileState.currentActiveFile?.id
    }

    private func readyFileID(in editor: ExcalidrawCore?) -> String? {
        guard let editor,
              let fileID = selectedFileID(in: editor),
              viewer.isDocumentLoaded, !viewer.isNavigating, !viewer.webView.isLoading,
              editor.isDocumentLoaded, !editor.isNavigating, !editor.webView.isLoading,
              !editor.documentSyncController.hasPendingFileLoad,
              editor.documentSyncController.currentLoadedFileID == fileID else { return nil }
        return fileID
    }

    private func isCurrent(_ expectedRevision: UInt64) -> Bool {
        !isClosed && !Task.isCancelled && revision == expectedRevision
    }

    private func checkCurrent(_ expectedRevision: UInt64) throws {
        guard isCurrent(expectedRevision) else { throw CancellationError() }
    }

    private static func isSupported(_ core: ExcalidrawCore) async throws -> Bool {
        let result = try await core.webView.callAsyncJavaScript(
            ViewerLocalScripts.isSupported, arguments: [:], contentWorld: .page
        )
        return result as? Bool == true
    }

    private static func supportsPresentationReadiness(_ core: ExcalidrawCore) async throws -> Bool {
        let result = try await core.webView.callAsyncJavaScript(
            ViewerLocalScripts.supportsPresentationReadiness, arguments: [:], contentWorld: .page
        )
        return result as? Bool == true
    }

    private static func waitUntilReady(_ binding: Binding) async throws {
        _ = try await binding.viewer.webView.callAsyncJavaScript(
            ViewerLocalScripts.waitUntilReady,
            arguments: ["sessionId": binding.id], contentWorld: .page
        )
    }

    private static func start(
        _ core: ExcalidrawCore,
        role: ViewerLocalRelay.Role,
        binding: Binding,
        isFollowing: Bool,
        pointerAppearance: ViewerPointerAppearance
    ) async throws {
        let url = "ws://127.0.0.1:\(ExcalidrawServer.port)/viewer/\(binding.id)/\(role.rawValue)"
        _ = try await core.webView.callAsyncJavaScript(
            ViewerLocalScripts.start,
            arguments: [
                "role": role.rawValue,
                "sessionId": binding.id,
                "transportURL": url,
                "followCamera": isFollowing,
                "pointerVisible": pointerAppearance.isVisible,
                "pointerColor": (pointerAppearance.colorHex as Any?) ?? NSNull(),
            ],
            contentWorld: .page
        )
    }

    private static func stop(_ binding: Binding) async {
        await ViewerLocalRelay.shared.endSession(binding.id)
        for core in [binding.editor, binding.viewer] where !core.webView.isLoading {
            _ = try? await core.webView.callAsyncJavaScript(
                ViewerLocalScripts.stop,
                arguments: ["sessionId": binding.id],
                contentWorld: .page
            )
        }
    }
}
#endif
