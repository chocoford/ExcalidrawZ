//
//  ExcalidrawDocumentProgrammaticSnapshotCommitter.swift
//  ExcalidrawZ
//
//  Captures snapshots after Swift-driven canvas mutations.
//

import Foundation

final class ExcalidrawDocumentProgrammaticSnapshotCommitter: @unchecked Sendable {
    private let lock = NSLock()
    private weak var delegate: ExcalidrawDocumentSnapshotCoordinatorDelegate?
    private var commitTask: Task<Void, Never>?

    func attach(delegate: ExcalidrawDocumentSnapshotCoordinatorDelegate) {
        self.delegate = delegate
    }

    func reset() {
        lock.lock()
        commitTask?.cancel()
        commitTask = nil
        lock.unlock()
    }

    /// Marks a native Swift mutation as locally dirty and schedules a live
    /// canvas snapshot save. This is intentionally separate from normal
    /// `stateChanged` because these mutations may not produce a reliable
    /// autosave event while the editor is outside explicit edit mode on iOS.
    @MainActor
    func schedule(reason: String) {
        guard let core = delegate?.snapshotCoordinatorCore,
              let fileID = core.parent?.file?.id else {
            return
        }

        core.parent?.fileState.noteProgrammaticCanvasMutation(fileID: fileID)
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                try Task.checkCancellation()
                await self?.commit(
                    reason: reason,
                    expectedFileID: fileID
                )
            } catch {
                return
            }
        }

        lock.lock()
        commitTask?.cancel()
        commitTask = task
        lock.unlock()
    }

    /// Captures the current WebView scene after a Swift-driven mutation and
    /// persists it if the canvas is still showing the same file.
    private func commit(
        reason: String,
        expectedFileID: String
    ) async {
        guard let delegate,
              let core = delegate.snapshotCoordinatorCore else { return }

        let onError = core.publishError
        let currentFileID = await MainActor.run { core.parent?.file?.id }
        guard currentFileID == expectedFileID else { return }

        let type = await MainActor.run { core.parent?.type }
        let savingType = await MainActor.run { core.parent?.savingType }

        do {
            let loadedID = core.documentSyncController.currentLoadedFileID
            guard delegate.snapshotCoordinatorCanApplyStateChanged(
                currentFileID: currentFileID,
                webLoadedFileID: loadedID,
                isCollaboration: type == .collaboration
            ) else {
                return
            }

            let snapshot = try await core.getCurrentFileSnapshot()
            let fileData = try delegate.snapshotCoordinatorMakeFileData(from: snapshot)
            try await delegate.snapshotCoordinatorApplyCanvasFileData(
                fileData,
                currentFileID: currentFileID,
                type: type,
                savingType: savingType,
                markProgrammaticCommit: true
            )
            core.logger.debug("Committed programmatic canvas mutation: \(reason)")
        } catch is CancellationError {
            return
        } catch {
            core.logger.error("Failed to commit programmatic canvas mutation \(reason): \(error)")
            onError(error)
        }
    }
}
