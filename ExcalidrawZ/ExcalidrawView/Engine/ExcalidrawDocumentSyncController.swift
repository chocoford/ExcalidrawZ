//
//  ExcalidrawDocumentSyncController.swift
//  ExcalidrawZ
//
//  Coordinates host-driven file loads with WebView stateChanged events.
//

import Foundation
import UniformTypeIdentifiers

final class ExcalidrawDocumentSyncController: @unchecked Sendable {
    enum LoadOutcome {
        case skipped
        case loaded(LoadFileResult?)
        case failed

        var didLoad: Bool {
            if case .loaded = self {
                return true
            }
            return false
        }
    }

    private enum StateChangeSuppressionReason {
        case preparingFileLoad
        case canvasFileLoad
        case coreFileLoad
    }

    private struct StateChangeSuppression {
        let fileID: String
        let reason: StateChangeSuppressionReason
        let startedAt: Date
    }

    private let lock = NSLock()
    private weak var core: ExcalidrawCore?
    private var loadedFileID: String?
    private var pendingFileLoadID: String?
    private var stateChangeSuppressions: [UUID: StateChangeSuppression] = [:]

    var currentLoadedFileID: String? {
        lock.lock()
        let fileID = loadedFileID
        lock.unlock()
        return fileID
    }

    func attach(core: ExcalidrawCore) {
        self.core = core
    }

    func setTargetFileID(_ fileID: String?) {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        stateChangeSuppressions = stateChangeSuppressions.filter { _, suppression in
            suppression.reason != .preparingFileLoad
        }

        if let fileID, loadedFileID != fileID {
            stateChangeSuppressions[UUID()] = .init(
                fileID: fileID,
                reason: .preparingFileLoad,
                startedAt: Date()
            )
        }
        lock.unlock()
    }

    @discardableResult
    func load(_ file: ExcalidrawFile?, force: Bool = false) async -> LoadOutcome {
        guard let file, let data = file.content else {
            core.map {
                logLoadFileDiag($0.logger, "[LoadFileDiag] documentLoad skipped: missing file or content", level: .warning)
            }
            return .failed
        }

        return await load(
            fileID: file.id,
            data: data,
            force: force,
            validateCurrentParentFile: true
        )
    }

    @discardableResult
    func load(
        fileID: String,
        data: Data,
        force: Bool = false,
        validateCurrentParentFile: Bool = false
    ) async -> LoadOutcome {
        let canvasToken: UUID
        if force {
            canvasToken = beginForcedCanvasFileLoad(fileID: fileID)
        } else if let token = beginCanvasFileLoadIfNeeded(fileID: fileID) {
            canvasToken = token
        } else {
            return .skipped
        }

        defer {
            endStateChangeSuppression(canvasToken)
        }

        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            guard !Task.isCancelled else {
                finishCanvasFileLoad(fileID: fileID)
                return .failed
            }

            if validateCurrentParentFile {
                let isStillCurrent = await MainActor.run {
                    core?.parent?.file?.id == fileID
                }
                guard isStillCurrent else {
                    finishCanvasFileLoad(fileID: fileID)
                    return .failed
                }
            }

            let result = await loadPreparedFile(fileID: fileID, data: data, force: force)

            if validateCurrentParentFile {
                let isStillCurrent = await MainActor.run {
                    core?.parent?.file?.id == fileID
                }
                guard isStillCurrent else {
                    finishCanvasFileLoad(fileID: fileID)
                    return .failed
                }
            }

            let loadedID = await core?.webActor.loadedFileID

            if loadedID == fileID {
                commitLoadedFile(fileID: fileID)
                return .loaded(result)
            }

            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        let loadedID = await core?.webActor.loadedFileID
        core?.logger.warning("Failed to load file \(fileID) into Excalidraw after retries. loadedID=\(loadedID ?? "nil")")
        finishCanvasFileLoad(fileID: fileID)
        return .failed
    }

    func save(_ data: ExcalidrawCore.StateChangedMessageData) async {
        guard let core else { return }

        if let rejectionReason = receivedStateChangedRejectionReason(isCoreLoading: core.isLoading) {
            core.logger.debug("[LoadFileDiag] ignored stateChanged: \(rejectionReason)")
            return
        }

        let type = core.parent?.type
        let currentFileID = await core.parent?.file?.id
        let onError = core.publishError

        do {
            let loadedID = await core.webActor.loadedFileID
            guard self.canApplyStateChanged(
                currentFileID: currentFileID,
                webLoadedFileID: loadedID,
                isCollaboration: type == .collaboration
            ) else {
                return
            }

            let elements = data.data.elements
            switch core.parent?.savingType {
                case .excalidrawPNG, .png:
                    let data = try await core.exportElementsToPNGData(
                        elements: elements ?? [],
                        embedScene: true,
                        colorScheme: .light
                    )
                    await MainActor.run {
                        guard type == .collaboration || core.parent?.file?.id == currentFileID else { return }
                        core.parent?.file?.content = data
                    }
                case .excalidrawSVG, .svg:
                    let data = try await core.exportElementsToSVGData(
                        elements: elements ?? [],
                        embedScene: true,
                        colorScheme: .light
                    )
                    await MainActor.run {
                        guard type == .collaboration || core.parent?.file?.id == currentFileID else { return }
                        core.parent?.file?.content = data
                    }
                default:
                    await MainActor.run {
                        guard type == .collaboration || core.parent?.file?.id == currentFileID else { return }
                        do {
                            try core.parent?.file?.update(data: data.data)
                        } catch {
                            onError(error)
                        }
                    }
            }
        } catch {
            onError(error)
        }
    }

    private func loadPreparedFile(
        fileID: String,
        data: Data,
        force: Bool
    ) async -> LoadFileResult? {
        guard let core else { return nil }

        let suppressionToken = beginCoreFileLoad(fileID: fileID)
        defer {
            endStateChangeSuppression(suppressionToken)
        }

        guard await core.waitUntilReadyForFileLoad(fileID: fileID) else {
            logLoadFileDiag(core.logger, "[LoadFileDiag] coreLoad notReady id=\(fileID)", level: .warning)
            return nil
        }

        do {
            let result = try await core.webActor.loadFile(id: fileID, data: data, force: force)
            let loadedID = await core.webActor.loadedFileID
            if loadedID == fileID {
                commitLoadedFile(fileID: fileID)
            }
            return result
        } catch {
            core.publishError(error)
            return nil
        }
    }

    private func beginCanvasFileLoadIfNeeded(fileID: String) -> UUID? {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        clearStateChangeSuppressions(reason: .preparingFileLoad, fileID: fileID)

        guard loadedFileID != fileID, pendingFileLoadID != fileID else {
            lock.unlock()
            return nil
        }

        pendingFileLoadID = fileID
        let token = UUID()
        stateChangeSuppressions[token] = .init(
            fileID: fileID,
            reason: .canvasFileLoad,
            startedAt: Date()
        )
        lock.unlock()
        return token
    }

    private func beginForcedCanvasFileLoad(fileID: String) -> UUID {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        clearStateChangeSuppressions(reason: .preparingFileLoad, fileID: fileID)
        pendingFileLoadID = fileID
        let token = UUID()
        stateChangeSuppressions[token] = .init(
            fileID: fileID,
            reason: .canvasFileLoad,
            startedAt: Date()
        )
        lock.unlock()
        return token
    }

    private func beginCoreFileLoad(fileID: String) -> UUID {
        beginStateChangeSuppression(fileID: fileID, reason: .coreFileLoad)
    }

    private func endStateChangeSuppression(_ token: UUID) {
        lock.lock()
        stateChangeSuppressions.removeValue(forKey: token)
        lock.unlock()
    }

    private func commitLoadedFile(fileID: String) {
        lock.lock()
        loadedFileID = fileID
        if pendingFileLoadID == fileID {
            pendingFileLoadID = nil
        }
        lock.unlock()
    }

    private func finishCanvasFileLoad(fileID: String) {
        lock.lock()
        if pendingFileLoadID == fileID {
            pendingFileLoadID = nil
        }
        lock.unlock()
    }

    func resetFileLoadState() {
        lock.lock()
        loadedFileID = nil
        pendingFileLoadID = nil
        stateChangeSuppressions.removeAll()
        lock.unlock()
    }

    private func receivedStateChangedRejectionReason(isCoreLoading: Bool) -> String? {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        let suppressedFileID = latestStateChangeSuppression()?.fileID
        lock.unlock()

        if let suppressedFileID {
            return "suppressed during file load id=\(suppressedFileID)"
        }

        if isCoreLoading {
            return "core loading"
        }

        return nil
    }

    private func canApplyStateChanged(
        currentFileID: String?,
        webLoadedFileID: String?,
        isCollaboration: Bool
    ) -> Bool {
        if isCollaboration {
            return true
        }

        guard let currentFileID else {
            return false
        }

        return webLoadedFileID == currentFileID
    }

    private func beginStateChangeSuppression(
        fileID: String,
        reason: StateChangeSuppressionReason
    ) -> UUID {
        let token = UUID()
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        stateChangeSuppressions[token] = .init(
            fileID: fileID,
            reason: reason,
            startedAt: Date()
        )
        lock.unlock()
        return token
    }

    private func pruneExpiredStateChangeSuppressions() {
        let now = Date()
        stateChangeSuppressions = stateChangeSuppressions.filter { _, suppression in
            now.timeIntervalSince(suppression.startedAt) <= 8
        }
    }

    private func clearStateChangeSuppressions(
        reason: StateChangeSuppressionReason,
        fileID: String
    ) {
        stateChangeSuppressions = stateChangeSuppressions.filter { _, suppression in
            !(suppression.reason == reason && suppression.fileID == fileID)
        }
    }

    private func latestStateChangeSuppression() -> StateChangeSuppression? {
        stateChangeSuppressions.values.max { lhs, rhs in
            lhs.startedAt < rhs.startedAt
        }
    }
}
