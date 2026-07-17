//
//  ExcalidrawDocumentSyncController.swift
//  ExcalidrawZ
//
//  Coordinates host-driven file loads with WebView stateChanged events.
//

import Foundation
import UniformTypeIdentifiers

private struct DocumentLoadStateMachine {
    struct Request: Equatable, Sendable {
        let id: String
        let generation: UInt64
        let fileID: String
    }

    private(set) var confirmedFileID: String?
    private(set) var currentRequest: Request?
    private var generation: UInt64 = 0

    mutating func begin(fileID: String, force: Bool) -> Request? {
        if !force {
            if currentRequest?.fileID == fileID {
                return nil
            }
            if currentRequest == nil, confirmedFileID == fileID {
                return nil
            }
        }

        generation &+= 1
        let request = Request(
            id: "native-\(generation)-\(UUID().uuidString)",
            generation: generation,
            fileID: fileID
        )
        currentRequest = request
        return request
    }

    func isCurrent(_ request: Request) -> Bool {
        currentRequest == request
    }

    mutating func confirm(_ request: Request) -> Bool {
        guard isCurrent(request) else { return false }
        confirmedFileID = request.fileID
        currentRequest = nil
        return true
    }

    mutating func fail(_ request: Request) -> Bool {
        guard isCurrent(request) else { return false }
        currentRequest = nil
        return true
    }

    mutating func reset() {
        generation &+= 1
        confirmedFileID = nil
        currentRequest = nil
    }
}

/// Owns the synchronization boundary between the native `ExcalidrawCanvasView`
/// binding and the embedded Excalidraw WebView.
///
/// Excalidraw can emit `stateChanged` events while the host is loading or
/// force-reloading a file. Applying those events blindly can persist an empty
/// or stale scene over the real file. This controller tracks which file is
/// expected in the WebView, suppresses load-induced events, and only applies
/// saves when the native file id still matches the WebView's loaded file id.
///
/// Swift-driven canvas mutations and metadata-only dirty events are delegated
/// to `ExcalidrawDocumentSnapshotCoordinator`, then routed back through this
/// controller's persistence bridge when a full snapshot must be applied.
final class ExcalidrawDocumentSyncController: @unchecked Sendable {
    enum LoadOutcome {
        case skipped
        case loaded(LoadFileResult)
        case superseded
        case failed

        var didLoad: Bool {
            if case .loaded = self {
                return true
            }
            return false
        }

        var shouldFinishPresentation: Bool {
            switch self {
                case .loaded, .failed:
                    true
                case .skipped, .superseded:
                    false
            }
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
    private let snapshotCoordinator = ExcalidrawDocumentSnapshotCoordinator()
    private var loadState = DocumentLoadStateMachine()
    /// Temporary guards used to ignore `stateChanged` events produced by file
    /// loading itself rather than by user or tool edits.
    private var stateChangeSuppressions: [UUID: StateChangeSuppression] = [:]
    init() {
        snapshotCoordinator.attach(delegate: self)
    }

    var currentLoadedFileID: String? {
        lock.lock()
        let fileID = loadState.confirmedFileID
        lock.unlock()
        return fileID
    }

    var hasPendingFileLoad: Bool {
        lock.lock()
        let hasPendingLoad = loadState.currentRequest != nil
        lock.unlock()
        return hasPendingLoad
    }

    func attach(core: ExcalidrawCore) {
        self.core = core
    }

    /// Called before the SwiftUI binding points the WebView at a different
    /// file. This arms a short suppression window so pre-load WebView events do
    /// not write into the previous or next file.
    func setTargetFileID(_ fileID: String?) {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        stateChangeSuppressions = stateChangeSuppressions.filter { _, suppression in
            suppression.reason != .preparingFileLoad
        }

        if let fileID, loadState.confirmedFileID != fileID {
            stateChangeSuppressions[UUID()] = .init(
                fileID: fileID,
                reason: .preparingFileLoad,
                startedAt: Date()
            )
        }
        lock.unlock()
    }

    /// Loads a complete file into the WebView and records the file id only
    /// after the JS side confirms it has applied the scene.
    @discardableResult
    func load(_ file: ExcalidrawFile?, force: Bool = false) async -> LoadOutcome {
        guard let file, let data = file.content else {
            core.map {
                logFileLoad($0.logger, "Document load skipped: missing file or content", level: .warning)
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
        snapshotCoordinator.cancelPendingSnapshotCommits()

        guard let (request, canvasToken) = beginCanvasFileLoad(
            fileID: fileID,
            force: force
        ) else {
            return .skipped
        }

        defer {
            endStateChangeSuppression(canvasToken)
        }

        let dataForLoad = await dataByApplyingLocalViewportIfNeeded(
            data,
            fileID: fileID
        )

        let maxAttempts = 2
        var lastError: Error?
        for attempt in 1...maxAttempts {
            let transportRequestID = "\(request.id)-attempt-\(attempt)"
            guard !Task.isCancelled else {
                return finishCanvasFileLoad(request, outcome: .failed)
            }

            guard isCurrentLoadRequest(request) else {
                return .superseded
            }

            if validateCurrentParentFile {
                let isStillCurrent = await MainActor.run {
                    core?.parent?.file?.id == fileID
                }
                guard isStillCurrent else {
                    return finishCanvasFileLoad(request, outcome: .superseded)
                }
            }

            let result: LoadFileResult?
            do {
                result = try await loadPreparedFile(
                    request: request,
                    transportRequestID: transportRequestID,
                    data: dataForLoad
                )
            } catch {
                lastError = error
                result = nil
            }

            guard isCurrentLoadRequest(request) else {
                return .superseded
            }

            if validateCurrentParentFile {
                let isStillCurrent = await MainActor.run {
                    core?.parent?.file?.id == fileID
                }
                guard isStillCurrent else {
                    return finishCanvasFileLoad(request, outcome: .superseded)
                }
            }

            if let result,
               result.fileId == request.fileID,
               result.requestId == transportRequestID,
               commitLoadedFile(request) {
                return .loaded(result)
            }

            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        core?.logger.warning(
            "Failed to load file \(fileID) into Excalidraw after retries requestID=\(request.id)"
        )
        if let lastError, isCurrentLoadRequest(request) {
            core?.publishError(lastError)
        }
        return finishCanvasFileLoad(request, outcome: .failed)
    }

    /// Applies a normal WebView `stateChanged` payload to the native file
    /// binding, unless the event overlaps with a host-driven file load.
    func save(_ data: ExcalidrawCore.StateChangedMessageData) async {
        guard let core else { return }

        if let rejectionReason = receivedStateChangedRejectionReason(isCoreLoading: core.isLoading) {
#if DEBUG
            core.logger.debug(
                "Ignored stateChanged during file load: \(rejectionReason) \(debugStateChangedSummary(data))"
            )
#else
            core.logger.debug("Ignored stateChanged during file load: \(rejectionReason)")
#endif
            return
        }

        let type = core.parent?.type
        let currentFileID = await core.parent?.file?.id
        let onError = core.publishError

        if let metadata = data.metadata, data.fileData == nil {
            await snapshotCoordinator.handleStateChangedMetadata(
                metadata,
                currentFileID: currentFileID,
                type: type,
                savingType: core.parent?.savingType
            )
            return
        }

        guard let fileData = data.fileData else { return }

        do {
            let loadedID = currentLoadedFileID
            guard self.canApplyStateChanged(
                currentFileID: currentFileID,
                webLoadedFileID: loadedID,
                isCollaboration: type == .collaboration
            ) else {
                return
            }

            try await applyCanvasFileData(
                fileData,
                currentFileID: currentFileID,
                type: type,
                savingType: core.parent?.savingType,
                markProgrammaticCommit: false
            )
        } catch {
            onError(error)
        }
    }

    func flushPendingDirtySnapshot(
        reason: String,
        force: Bool = false,
        expectedFileID: String? = nil,
        validateParentFileID: Bool = true
    ) async {
        await snapshotCoordinator.flushPendingDirtySnapshot(
            reason: reason,
            force: force,
            expectedFileID: expectedFileID,
            validateParentFileID: validateParentFileID
        )
    }

    @MainActor
    func flushPendingDirtySnapshotInBackground(
        reason: String,
        expectedFileID: String,
        target: FileState.CapturedCanvasSaveTarget
    ) async {
        await snapshotCoordinator.flushPendingDirtySnapshotInBackground(
            reason: reason,
            expectedFileID: expectedFileID,
            target: target
        )
    }

    func flushPendingDirtySnapshotToCapturedTarget(
        reason: String,
        expectedFileID: String,
        target: FileState.CapturedCanvasSaveTarget,
        forceCurrentAppState: Bool = false
    ) async {
        await snapshotCoordinator.flushPendingDirtySnapshotToCapturedTarget(
            reason: reason,
            expectedFileID: expectedFileID,
            target: target,
            forceCurrentAppState: forceCurrentAppState
        )
    }

    @MainActor
    func scheduleProgrammaticMutationCommit(reason: String) {
        snapshotCoordinator.scheduleProgrammaticMutationCommit(reason: reason)
    }

    /// Shared persistence bridge for both WebView autosave events and explicit
    /// snapshot commits. This keeps PNG/SVG export-backed documents and normal
    /// `.excalidraw` documents on the same validation path.
    private func applyCanvasFileData(
        _ fileData: ExcalidrawCore.ExcalidrawFileData,
        currentFileID: String?,
        type: ExcalidrawCanvasView.ExcalidrawType?,
        savingType: UTType?,
        markProgrammaticCommit: Bool
    ) async throws {
        guard let core else { return }

        switch savingType {
            case .some(.excalidrawPNG), .some(.png):
                let elements = try await Self.elements(from: fileData)
                let data = try await core.exportElementsToPNGData(
                    elements: elements,
                    embedScene: true,
                    colorScheme: .light
                )
                await MainActor.run {
                    guard type == .collaboration || core.parent?.file?.id == currentFileID else {
                        core.logger.debug(
                            "Skipped applying PNG canvas data: parent file mismatch expected=\(currentFileID ?? "nil") actual=\(core.parent?.file?.id ?? "nil")"
                        )
                        return
                    }
                    core.parent?.file?.content = data
                }
            case .some(.excalidrawSVG), .some(.svg):
                let elements = try await Self.elements(from: fileData)
                let data = try await core.exportElementsToSVGData(
                    elements: elements,
                    embedScene: true,
                    colorScheme: .light
                )
                await MainActor.run {
                    guard type == .collaboration || core.parent?.file?.id == currentFileID else {
                        core.logger.debug(
                            "Skipped applying SVG canvas data: parent file mismatch expected=\(currentFileID ?? "nil") actual=\(core.parent?.file?.id ?? "nil")"
                        )
                        return
                    }
                    core.parent?.file?.content = data
                }
            default:
                let existingContent: Data? = await MainActor.run { () -> Data? in
                    guard type == .collaboration || core.parent?.file?.id == currentFileID else {
                        core.logger.debug(
                            "Skipped applying canvas data: parent file mismatch expected=\(currentFileID ?? "nil") actual=\(core.parent?.file?.id ?? "nil")"
                        )
                        return nil
                    }
                    return core.parent?.file?.content
                }
                guard let existingContent else { return }

                let fileDataForPersistence = try await canvasFileDataForPersistence(
                    fileData,
                    currentFileID: currentFileID
                )

                let preparedUpdate = try await Task.detached(priority: .utility) { () async throws -> ExcalidrawFile.PreparedCanvasDataUpdate in
                    try ExcalidrawFile.prepareCanvasDataUpdate(
                        existingContent: existingContent,
                        data: fileDataForPersistence
                    )
                }.value

                await MainActor.run {
                    guard type == .collaboration || core.parent?.file?.id == currentFileID else {
                        core.logger.debug(
                            "Skipped applying canvas data: parent file mismatch expected=\(currentFileID ?? "nil") actual=\(core.parent?.file?.id ?? "nil")"
                        )
                        return
                    }
                    if markProgrammaticCommit, let currentFileID {
                        core.parent?.fileState.noteProgrammaticCanvasMutation(fileID: currentFileID)
                    }
                    guard persistPreparedLibraryCanvasUpdateIfNeeded(
                        preparedUpdate,
                        currentFileID: currentFileID,
                        type: type,
                        core: core
                    ) else {
                        return
                    }
                    core.parent?.file?.apply(preparedUpdate)
                }
        }
    }

    /// Converts a live JS snapshot into the same payload shape used by the
    /// `stateChanged` message.
    private static func makeFileData(
        from snapshot: ExcalidrawCore.CurrentFileSnapshot
    ) throws -> ExcalidrawCore.ExcalidrawFileData {
        return .init(documentData: try snapshot.documentData(), elements: nil, files: [:])
    }

    private func dataByApplyingLocalViewportIfNeeded(
        _ data: Data,
        fileID: String
    ) async -> Data {
        guard await usesLocalViewportSidecar(fileID: fileID) else {
            return data
        }

        do {
            return try await ExcalidrawViewportStateStore.shared.contentDataByApplyingStoredViewport(
                to: data,
                fileID: fileID
            )
        } catch {
            core?.logger.warning("Failed to apply local viewport state for file \(fileID): \(error)")
            return data
        }
    }

    private func canvasFileDataForPersistence(
        _ fileData: ExcalidrawCore.ExcalidrawFileData,
        currentFileID: String?
    ) async throws -> ExcalidrawCore.ExcalidrawFileData {
        var fileDataForPersistence = fileData

        if let currentFileID,
           await usesLocalViewportSidecar(fileID: currentFileID) {
            fileDataForPersistence.documentData = try await ExcalidrawViewportStateStore.shared.contentDataBySeparatingViewport(
                from: fileData.documentData,
                fileID: currentFileID
            )
        }

        fileDataForPersistence.documentData = try ExcalidrawDocumentAppStatePersistence.documentData(
            fileDataForPersistence.documentData,
            settingNativeFileName: await nativeFileNameForPersistence(currentFileID: currentFileID)
        )
        return fileDataForPersistence
    }

    private func usesLocalViewportSidecar(fileID: String) async -> Bool {
        await MainActor.run {
            guard core?.parent?.type == .normal,
                  let activeFile = core?.parent?.fileState.currentActiveFile,
                  case .file(let file) = activeFile else {
                return false
            }
            return file.id?.uuidString == fileID
        }
    }

    private func nativeFileNameForPersistence(currentFileID: String?) async -> String? {
        await MainActor.run {
            guard let activeFile = core?.parent?.fileState.currentActiveFile,
                  currentFileID == nil || activeFile.id == currentFileID else {
                return nil
            }
            return activeFile.name
        }
    }

    @MainActor
    private func persistPreparedLibraryCanvasUpdateIfNeeded(
        _ preparedUpdate: ExcalidrawFile.PreparedCanvasDataUpdate,
        currentFileID: String?,
        type: ExcalidrawCanvasView.ExcalidrawType?,
        core: ExcalidrawCore
    ) -> Bool {
        guard type == .normal else {
            return true
        }
        guard let currentFileID,
              let fileState = core.parent?.fileState,
              case .file(let activeFile) = fileState.currentActiveFile else {
            return true
        }
        guard activeFile.id?.uuidString == currentFileID else {
            core.logger.debug(
                "Skipped persisting prepared library canvas update: active file mismatch expected=\(currentFileID) actual=\(activeFile.id?.uuidString ?? "nil")"
            )
            return false
        }

        var file = ExcalidrawFile()
        file.id = currentFileID
        file.apply(preparedUpdate)
        return fileState.persistPreparedLibraryCanvasUpdate(activeFile, with: file)
    }

    private static func elements(
        from fileData: ExcalidrawCore.ExcalidrawFileData
    ) async throws -> [ExcalidrawElement] {
        if let elements = fileData.elements {
            return elements
        }

        return try await Task.detached(priority: .utility) {
            let payload = try JSONDecoder().decode(
                SnapshotElementsPayload.self,
                from: fileData.documentData
            )
            return payload.elements
        }.value
    }

    private struct SnapshotElementsPayload: Decodable {
        var elements: [ExcalidrawElement]
    }

    private func loadPreparedFile(
        request: DocumentLoadStateMachine.Request,
        transportRequestID: String,
        data: Data
    ) async throws -> LoadFileResult? {
        guard let core else { return nil }

        let suppressionToken = beginCoreFileLoad(fileID: request.fileID)
        defer {
            endStateChangeSuppression(suppressionToken)
        }

        guard await core.waitUntilReadyForFileLoad(fileID: request.fileID) else {
            logFileLoad(
                core.logger,
                "File load skipped: core not ready id=\(request.fileID)",
                level: .warning
            )
            return nil
        }

        guard isCurrentLoadRequest(request) else { return nil }

        return try await core.webActor.loadFile(
            id: request.fileID,
            requestID: transportRequestID,
            data: data
        )
    }

    private func beginCanvasFileLoad(
        fileID: String,
        force: Bool
    ) -> (DocumentLoadStateMachine.Request, UUID)? {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        clearStateChangeSuppressions(reason: .preparingFileLoad, fileID: fileID)
        stateChangeSuppressions = stateChangeSuppressions.filter { _, suppression in
            suppression.reason != .canvasFileLoad && suppression.reason != .coreFileLoad
        }

        guard let request = loadState.begin(fileID: fileID, force: force) else {
            lock.unlock()
            return nil
        }

        let token = UUID()
        stateChangeSuppressions[token] = .init(
            fileID: fileID,
            reason: .canvasFileLoad,
            startedAt: Date()
        )
        lock.unlock()
        return (request, token)
    }

    private func beginCoreFileLoad(fileID: String) -> UUID {
        beginStateChangeSuppression(fileID: fileID, reason: .coreFileLoad)
    }

    private func endStateChangeSuppression(_ token: UUID) {
        lock.lock()
        stateChangeSuppressions.removeValue(forKey: token)
        lock.unlock()
    }

    private func isCurrentLoadRequest(_ request: DocumentLoadStateMachine.Request) -> Bool {
        lock.lock()
        let isCurrent = loadState.isCurrent(request)
        lock.unlock()
        return isCurrent
    }

    private func commitLoadedFile(_ request: DocumentLoadStateMachine.Request) -> Bool {
        lock.lock()
        let didCommit = loadState.confirm(request)
        lock.unlock()
        return didCommit
    }

    private func finishCanvasFileLoad(
        _ request: DocumentLoadStateMachine.Request,
        outcome: LoadOutcome
    ) -> LoadOutcome {
        lock.lock()
        let wasCurrent = loadState.fail(request)
        lock.unlock()
        return wasCurrent ? outcome : .superseded
    }

    func resetFileLoadState() {
        snapshotCoordinator.reset()
        lock.lock()
        loadState.reset()
        stateChangeSuppressions.removeAll()
        lock.unlock()
    }

    private func receivedStateChangedRejectionReason(isCoreLoading: Bool) -> String? {
        lock.lock()
        pruneExpiredStateChangeSuppressions()
        let suppression = latestStateChangeSuppression()
        let pendingFileID = loadState.currentRequest?.fileID
        lock.unlock()

        if let pendingFileID {
            return "document load pending id=\(pendingFileID)"
        }

        if let suppression {
            return "suppressed during file load id=\(suppression.fileID)"
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

#if DEBUG
    private func debugStateChangedSummary(_ data: ExcalidrawCore.StateChangedMessageData) -> String {
        if let metadata = data.metadata, data.fileData == nil {
            return debugMetadataSummary(metadata)
        }

        if data.fileData != nil {
            return "payload=fullSnapshot"
        }

        return "payload=empty"
    }

    private func debugMetadataSummary(_ metadata: ExcalidrawCore.StateChangedMetadata) -> String {
        [
            "payload=metadata",
            "revision=\(metadata.revision.map(String.init) ?? "nil")",
            "dirty=\(metadata.dirty.map(String.init) ?? "nil")",
            "contentDirty=\(metadata.contentDirty.map(String.init) ?? "nil")",
            "appStateDirty=\(metadata.appStateDirty.map(String.init) ?? "nil")",
            "currentFileId=\(metadata.currentFileId ?? "nil")",
            "elements=\(metadata.elementCount.map(String.init) ?? "nil")",
            "fileElements=\(metadata.fileElementCount.map(String.init) ?? "nil")",
            "appStateKeys=\(metadata.appStateKeyCount.map(String.init) ?? "nil")",
            "appStateChars=\(metadata.appStateChars.map(String.init) ?? "nil")"
        ].joined(separator: " ")
    }
#endif
}

extension ExcalidrawDocumentSyncController: ExcalidrawDocumentSnapshotCoordinatorDelegate {
    var snapshotCoordinatorCore: ExcalidrawCore? {
        core
    }

    func snapshotCoordinatorCanApplyStateChanged(
        currentFileID: String?,
        webLoadedFileID: String?,
        isCollaboration: Bool
    ) -> Bool {
        canApplyStateChanged(
            currentFileID: currentFileID,
            webLoadedFileID: webLoadedFileID,
            isCollaboration: isCollaboration
        )
    }

    func snapshotCoordinatorApplyCanvasFileData(
        _ fileData: ExcalidrawCore.ExcalidrawFileData,
        currentFileID: String?,
        type: ExcalidrawCanvasView.ExcalidrawType?,
        savingType: UTType?,
        markProgrammaticCommit: Bool
    ) async throws {
        try await applyCanvasFileData(
            fileData,
            currentFileID: currentFileID,
            type: type,
            savingType: savingType,
            markProgrammaticCommit: markProgrammaticCommit
        )
    }

    func snapshotCoordinatorMakeFileData(
        from snapshot: ExcalidrawCore.CurrentFileSnapshot
    ) throws -> ExcalidrawCore.ExcalidrawFileData {
        try Self.makeFileData(from: snapshot)
    }
}
