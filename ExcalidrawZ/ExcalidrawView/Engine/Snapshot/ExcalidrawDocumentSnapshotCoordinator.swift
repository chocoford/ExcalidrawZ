//
//  ExcalidrawDocumentSnapshotCoordinator.swift
//  ExcalidrawZ
//
//  Coordinates lightweight dirty notifications with full canvas snapshot saves.
//

import Foundation
import UniformTypeIdentifiers

protocol ExcalidrawDocumentSnapshotCoordinatorDelegate: AnyObject {
    var snapshotCoordinatorCore: ExcalidrawCore? { get }

    func snapshotCoordinatorCanApplyStateChanged(
        currentFileID: String?,
        webLoadedFileID: String?,
        isCollaboration: Bool
    ) -> Bool

    func snapshotCoordinatorApplyCanvasFileData(
        _ fileData: ExcalidrawCore.ExcalidrawFileData,
        currentFileID: String?,
        type: ExcalidrawCanvasView.ExcalidrawType?,
        savingType: UTType?,
        markProgrammaticCommit: Bool
    ) async throws

    func snapshotCoordinatorMakeFileData(
        from snapshot: ExcalidrawCore.CurrentFileSnapshot
    ) throws -> ExcalidrawCore.ExcalidrawFileData
}

/// Owns save cadence for live Excalidraw state.
///
/// The WebView reports cheap metadata on hot edit paths. This coordinator
/// routes that metadata into smaller save components and only asks for a full
/// snapshot on a bounded cadence or at file/app boundaries.
final class ExcalidrawDocumentSnapshotCoordinator: @unchecked Sendable {
    private weak var delegate: ExcalidrawDocumentSnapshotCoordinatorDelegate?

    private lazy var contentScheduler = ExcalidrawDocumentContentSnapshotScheduler { [weak self] in
        await self?.commitScheduledDirtySnapshot()
    }
    private let appStateSaver = ExcalidrawDocumentAppStateSnapshotSaver()
    private let programmaticCommitter = ExcalidrawDocumentProgrammaticSnapshotCommitter()

    init(delegate: ExcalidrawDocumentSnapshotCoordinatorDelegate? = nil) {
        if let delegate {
            attach(delegate: delegate)
        }
    }

    func attach(delegate: ExcalidrawDocumentSnapshotCoordinatorDelegate) {
        self.delegate = delegate
        appStateSaver.attach(delegate: delegate)
        programmaticCommitter.attach(delegate: delegate)
    }

    func reset() {
        contentScheduler.reset()
        appStateSaver.reset()
        programmaticCommitter.reset()
    }

    func cancelPendingSnapshotCommits() {
        reset()
    }

    func handleStateChangedMetadata(
        _ metadata: ExcalidrawCore.StateChangedMetadata,
        currentFileID: String?,
        type _: ExcalidrawCanvasView.ExcalidrawType?,
        savingType: UTType?
    ) async {
        guard metadata.hasAnyDirtyChanges else {
            contentScheduler.markClean(metadata.revision)
            appStateSaver.clear()
            return
        }

        contentScheduler.recordLatestRevision(metadata.revision)
        appStateSaver.recordLatestAppState(metadata)

        guard metadata.shouldPullContentSnapshot else {
            appStateSaver.schedule(
                metadata,
                currentFileID: currentFileID,
                savingType: savingType
            )
            return
        }

        appStateSaver.clear()
        contentScheduler.recordPendingContentDirtyMetadata(
            metadata,
            currentFileID: currentFileID
        )
    }

    @MainActor
    func scheduleProgrammaticMutationCommit(reason: String) {
        programmaticCommitter.schedule(reason: reason)
    }

    /// Forces a pending content-dirty notification to materialize into a full
    /// snapshot. Use this at boundaries such as file switches or app
    /// backgrounding; appState-only changes deliberately do not pull content.
    func flushPendingDirtySnapshot(
        reason: String,
        force: Bool = false,
        expectedFileID: String? = nil,
        validateParentFileID: Bool = true
    ) async {
        await contentScheduler.waitForCommitToFinish()
        if let flushState = contentScheduler.takeFlushState() {
            await commitDirtySnapshot(
                reason: reason,
                expectedFileID: expectedFileID ?? flushState.expectedFileID,
                expectedRevision: flushState.expectedRevision,
                requirePendingDirty: !force,
                validateParentFileID: validateParentFileID
            )
        } else if force {
            let didCommitCurrentAppState = await appStateSaver.flushCurrentAppState(reason: reason)
            if !didCommitCurrentAppState {
                await appStateSaver.flush(reason: reason)
            }
        } else {
            await appStateSaver.flush(reason: reason)
        }
    }

    @MainActor
    func flushPendingDirtySnapshotInBackground(
        reason: String,
        expectedFileID: String,
        target: FileState.CapturedCanvasSaveTarget
    ) async {
        let capturedContent = delegate?.snapshotCoordinatorCore?.parent?.file?.content
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.flushPendingDirtySnapshotToCapturedTarget(
                reason: reason,
                expectedFileID: expectedFileID,
                target: target,
                capturedContent: capturedContent
            )
        }
        await Task.yield()
    }

    func flushPendingDirtySnapshotToCapturedTarget(
        reason: String,
        expectedFileID: String,
        target: FileState.CapturedCanvasSaveTarget,
        forceCurrentAppState: Bool = false
    ) async {
        let capturedContent = await MainActor.run {
            delegate?.snapshotCoordinatorCore?.parent?.file?.content
        }
        await flushPendingDirtySnapshotToCapturedTarget(
            reason: reason,
            expectedFileID: expectedFileID,
            target: target,
            capturedContent: capturedContent,
            forceCurrentAppState: forceCurrentAppState
        )
    }

    private func commitScheduledDirtySnapshot() async {
        guard let commitState = contentScheduler.takeScheduledCommitState() else {
            return
        }
        defer {
            contentScheduler.completeScheduledCommit()
        }
        await commitDirtySnapshot(
            reason: "stateChangedThrottled",
            expectedFileID: commitState.expectedFileID,
            expectedRevision: commitState.expectedRevision,
            requirePendingDirty: true,
            validateParentFileID: true
        )
    }

    /// Pulls the current full scene and applies it through the same
    /// persistence path as legacy full `onStateChanged`.
    private func commitDirtySnapshot(
        reason: String,
        expectedFileID: String?,
        expectedRevision: Int?,
        requirePendingDirty: Bool = true,
        validateParentFileID: Bool = true
    ) async {
        guard let delegate,
              let core = delegate.snapshotCoordinatorCore else { return }
        if requirePendingDirty {
            guard contentScheduler.hasPendingDirtySnapshot() else { return }
        }

        let onError = core.publishError
        let parentFileID = await MainActor.run { core.parent?.file?.id }
        if validateParentFileID,
           let expectedFileID,
           parentFileID != expectedFileID {
            core.logger.debug(
                "Skipped dirty canvas snapshot \(reason): parent file mismatch expected=\(expectedFileID) actual=\(parentFileID ?? "nil")"
            )
            return
        }
        let currentFileID = expectedFileID ?? parentFileID

        let type = await MainActor.run { core.parent?.type }
        let savingType = await MainActor.run { core.parent?.savingType }

        do {
            let loadedID = core.documentSyncController.currentLoadedFileID
            guard delegate.snapshotCoordinatorCanApplyStateChanged(
                currentFileID: currentFileID,
                webLoadedFileID: loadedID,
                isCollaboration: type == .collaboration
            ) else {
                core.logger.debug(
                    "Skipped dirty canvas snapshot \(reason): loaded file mismatch expected=\(currentFileID ?? "nil") loaded=\(loadedID ?? "nil")"
                )
                return
            }

            let snapshot = try await core.getCurrentFileSnapshot()
            if let expectedRevision,
               let snapshotRevision = snapshot.revision,
               snapshotRevision < expectedRevision {
                core.logger.debug(
                    "Skipped dirty canvas snapshot \(reason): stale snapshot revision=\(snapshotRevision) expected=\(expectedRevision)"
                )
                return
            }
            let fileData = try delegate.snapshotCoordinatorMakeFileData(from: snapshot)
            try await delegate.snapshotCoordinatorApplyCanvasFileData(
                fileData,
                currentFileID: currentFileID,
                type: type,
                savingType: savingType,
                markProgrammaticCommit: false
            )
            contentScheduler.markCommitted(
                snapshotRevision: snapshot.revision,
                fallbackRevision: expectedRevision
            )
        } catch is CancellationError {
            return
        } catch {
            core.logger.error("Failed to commit dirty canvas snapshot \(reason): \(error)")
            onError(error)
        }
    }

    private func flushPendingDirtySnapshotToCapturedTarget(
        reason: String,
        expectedFileID: String,
        target: FileState.CapturedCanvasSaveTarget,
        capturedContent: Data?,
        forceCurrentAppState: Bool = false
    ) async {
        await contentScheduler.waitForCommitToFinish()
        if let flushState = contentScheduler.takeFlushState() {
            await commitDirtySnapshotToCapturedTarget(
                reason: reason,
                expectedFileID: expectedFileID,
                expectedRevision: flushState.expectedRevision,
                target: target,
                capturedContent: capturedContent
            )
        } else if forceCurrentAppState {
            let didCommitCurrentAppState = await appStateSaver.flushCurrentAppStateToCapturedTarget(
                reason: reason,
                expectedFileID: expectedFileID,
                target: target,
                capturedContent: capturedContent
            )
            if !didCommitCurrentAppState {
                await appStateSaver.flushToCapturedTarget(
                    reason: reason,
                    expectedFileID: expectedFileID,
                    target: target,
                    capturedContent: capturedContent
                )
            }
        } else {
            await appStateSaver.flushToCapturedTarget(
                reason: reason,
                expectedFileID: expectedFileID,
                target: target,
                capturedContent: capturedContent
            )
        }
    }

    private func commitDirtySnapshotToCapturedTarget(
        reason: String,
        expectedFileID: String,
        expectedRevision: Int?,
        target: FileState.CapturedCanvasSaveTarget,
        capturedContent: Data?
    ) async {
        guard let delegate,
              let core = delegate.snapshotCoordinatorCore else { return }
        do {
            let loadedID = core.documentSyncController.currentLoadedFileID
            guard loadedID == expectedFileID else {
                core.logger.debug(
                    "Skipped background dirty canvas snapshot \(reason): loaded file mismatch expected=\(expectedFileID) loaded=\(loadedID ?? "nil")"
                )
                return
            }

            let snapshot = try await core.getCurrentFileSnapshot()
            if let expectedRevision,
               let snapshotRevision = snapshot.revision,
               snapshotRevision < expectedRevision {
                core.logger.debug(
                    "Skipped background dirty canvas snapshot \(reason): stale snapshot revision=\(snapshotRevision) expected=\(expectedRevision)"
                )
                return
            }
            let fileData = try await capturedCanvasFileDataForPersistence(
                delegate.snapshotCoordinatorMakeFileData(from: snapshot),
                expectedFileID: expectedFileID,
                target: target
            )
            var file = ExcalidrawFile()
            file.id = expectedFileID
            file.content = capturedContent ?? file.content
            try file.update(data: fileData)
            await FileState.saveCapturedCanvasUpdate(target, with: file)
            contentScheduler.markCommitted(
                snapshotRevision: snapshot.revision,
                fallbackRevision: expectedRevision
            )
            core.logger.debug("Committed background dirty canvas snapshot: \(reason) id=\(expectedFileID)")
        } catch is CancellationError {
            return
        } catch {
            core.logger.error("Failed to commit background dirty canvas snapshot \(reason): \(error)")
            core.publishError(error)
        }
    }

    private func capturedCanvasFileDataForPersistence(
        _ fileData: ExcalidrawCore.ExcalidrawFileData,
        expectedFileID: String,
        target: FileState.CapturedCanvasSaveTarget
    ) async throws -> ExcalidrawCore.ExcalidrawFileData {
        var fileDataForPersistence = fileData

        if case .libraryFile(_, let fileName, _, _) = target.kind {
            fileDataForPersistence.documentData = try await ExcalidrawViewportStateStore.shared
                .contentDataBySeparatingViewport(
                    from: fileDataForPersistence.documentData,
                    fileID: expectedFileID
                )
            fileDataForPersistence.documentData = try ExcalidrawDocumentAppStatePersistence.documentData(
                fileDataForPersistence.documentData,
                settingNativeFileName: fileName
            )
        }

        return fileDataForPersistence
    }
}
