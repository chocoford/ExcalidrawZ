//
//  FileState.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import SwiftUI
import WebKit
import Combine
import Logging
import UniformTypeIdentifiers
@preconcurrency import CoreData
import ChocofordEssentials

final class FileState: ObservableObject {
    let logger = Logger(label: "FileState")

    private let openInPlaceAccessStore = OpenInPlaceAccessStore()
    
    var stateUpdateQueue: DispatchQueue = DispatchQueue(label: "StateUpdateQueue")
    
    var currentGroupPublisherCancellables: [AnyCancellable] = []
    var currentFilePublisherCancellables: [AnyCancellable] = []
    private var isRestoringActiveGroupAfterBlockedSwitch = false
    private var pendingActiveFileCloseTransitionIDs: Set<String> = []
    private var activeFileCloseTransitionContinuations: [
        String: [CheckedContinuation<Void, Never>]
    ] = [:]
    
    enum ActiveGroup: Identifiable, Equatable {
        case group(Group)
        case localFolder(LocalFolder)
        case cloudStorageFolder(CloudStorageFolderReference)
        case temporary
        case collaboration
        
        var id: String {
            switch self {
                case .group(let group):
                    (group.id ?? UUID()).uuidString
                case .localFolder(let folder):
                    folder.filePath ?? UUID().uuidString
                case .cloudStorageFolder(let folder):
                    folder.id
                case .temporary:
                    "temporary"
                case .collaboration:
                    "collaboration"
            }
        }
    }
    
    @Published var currentActiveGroup: ActiveGroup? {
        didSet {
            if shouldRestoreActiveGroupAfterBlockedSwitch(from: oldValue) {
                return
            }
            resetCurrentGroupChangesListener()
        }
    }

    @MainActor
    func setActiveGroupIfNeeded(_ group: ActiveGroup?) {
        guard currentActiveGroup != group else { return }
        currentActiveGroup = group
    }

    /// Keeps an open local-file session attached when Finder renames or moves
    /// the linked root folder and its bookmark resolves to the new location.
    @MainActor
    func rebaseLinkedFolderSession(from oldRootURL: URL, to newRootURL: URL) {
        for index in activeFiles.indices {
            guard let activeFile = activeFiles[index],
                  case .localFile(let currentURL) = activeFile,
                  let rebasedURL = currentURL.rebased(from: oldRootURL, to: newRootURL) else {
                continue
            }

            let replacement = ActiveFile.localFile(rebasedURL)
            if let didUpdate = didUpdateFileState.removeValue(forKey: activeFile) {
                didUpdateFileState[replacement] = didUpdate
            }
            if let checkpointStartedAt = userCheckpointWindowStartedAt.removeValue(forKey: activeFile.id) {
                userCheckpointWindowStartedAt[replacement.id] = checkpointStartedAt
            }
            activeFiles[index] = replacement
        }

        selectedLocalFiles = Set(selectedLocalFiles.map {
            $0.rebased(from: oldRootURL, to: newRootURL) ?? $0
        })
        if let selectedStartLocalFile {
            self.selectedStartLocalFile = selectedStartLocalFile.rebased(
                from: oldRootURL,
                to: newRootURL
            ) ?? selectedStartLocalFile
        }
        resetCurrentFileChangesListener()
    }

    /// Keeps per-window navigation consistent when a cloud location is
    /// removed from another scene, such as the macOS Settings window.
    @MainActor
    func reconcileCloudStorageLocations(_ locationIDs: Set<UUID>) async {
        let activeGroupWasRemoved = if case .cloudStorageFolder(let folder) = currentActiveGroup {
            !locationIDs.contains(folder.location.id)
        } else {
            false
        }
        let activeFileWasRemoved = if case .cloudStorageFile(let reference) = currentActiveFile {
            !locationIDs.contains(reference.locationID)
        } else {
            false
        }

        guard activeGroupWasRemoved || activeFileWasRemoved else {
            return
        }

        if activeGroupWasRemoved {
            setActiveGroupIfNeeded(nil)
        }
        resetSelections()

        if activeFileWasRemoved {
            _ = await requestActiveFileChange(nil)
        }
    }

    @MainActor
    func replaceCloudStorageDocumentReference(
        _ reference: CloudStorageDocumentReference
    ) {
        var replacedCount = 0
        for index in activeFiles.indices {
            guard let activeFile = activeFiles[index],
                  case .cloudStorageFile(let currentReference) = activeFile,
                  currentReference == reference else { continue }
            activeFiles[index] = .cloudStorageFile(
                reference.preservingActiveFileID(currentReference.activeFileID)
            )
            replacedCount += 1
        }
#if DEBUG
        logger.debug(
            "Replaced cloud document metadata itemID=\(reference.itemID.rawValue) name=\(reference.lastKnownName) activeSessions=\(replacedCount)"
        )
#endif
    }

    @MainActor
    func applyCloudStorageIdentityChange(
        _ change: CloudStorageItemIdentityChange
    ) {
        for index in activeFiles.indices {
            guard let activeFile = activeFiles[index],
                  case .cloudStorageFile(let reference) = activeFile,
                  reference.locationID == change.location.id,
                  let item = change.replacements[reference.itemID] else {
                continue
            }
            let replacement = CloudStorageDocumentReference(
                locationID: change.location.id,
                providerID: change.location.providerID,
                accountID: change.location.accountID,
                itemID: item.id,
                lastKnownName: item.name,
                lastKnownModifiedAt: item.modifiedAt,
                activeFileID: reference.activeFileID
            )
            let replacementFile = ActiveFile.cloudStorageFile(replacement)
            if let didUpdate = didUpdateFileState.removeValue(forKey: activeFile) {
                didUpdateFileState[replacementFile] = didUpdate
            }
            if let startedAt = userCheckpointWindowStartedAt.removeValue(forKey: activeFile.id) {
                userCheckpointWindowStartedAt[replacementFile.id] = startedAt
            }
            activeFiles[index] = replacementFile
        }

        selectedCloudStorageFiles = Set(selectedCloudStorageFiles.map { reference in
            guard reference.locationID == change.location.id,
                  let item = change.replacements[reference.itemID] else {
                return reference
            }
            return CloudStorageDocumentReference(
                locationID: change.location.id,
                providerID: change.location.providerID,
                accountID: change.location.accountID,
                itemID: item.id,
                lastKnownName: item.name,
                lastKnownModifiedAt: item.modifiedAt
            )
        })
        if let reference = selectedStartCloudStorageFile,
           reference.locationID == change.location.id,
           let item = change.replacements[reference.itemID] {
            selectedStartCloudStorageFile = CloudStorageDocumentReference(
                locationID: change.location.id,
                providerID: change.location.providerID,
                accountID: change.location.accountID,
                itemID: item.id,
                lastKnownName: item.name,
                lastKnownModifiedAt: item.modifiedAt
            )
        }

        if case .cloudStorageFolder(let folder) = currentActiveGroup,
           folder.location.id == change.location.id,
           let item = change.replacements[folder.itemID] {
            currentActiveGroup = .cloudStorageFolder(
                CloudStorageFolderReference(location: change.location, item: item)
            )
        }
    }
    
    enum ActiveFile: Identifiable, Hashable {
        case file(File)
        case localFile(URL)
        case temporaryFile(URL)
        case collaborationFile(CollaborationFile)
        case cloudStorageFile(CloudStorageDocumentReference)
        
        var id: String {
            switch self {
                case .file(let file):
                    // file.objectID.description
                    file.id?.uuidString ?? UUID().uuidString
                case .localFile(let url):
                    url.absoluteString
                case .temporaryFile(let url):
                    url.absoluteString
                case .collaborationFile(let collaborationFile):
                    // collaborationFile.objectID.description
                    collaborationFile.id?.uuidString ?? UUID().uuidString
                case .cloudStorageFile(let reference):
                    reference.activeFileID
            }
        }

        /// Identity used by persisted UI state such as covers and File Home
        /// transitions. An open cloud editor may temporarily keep an older
        /// session ID while its provisional provider identity is replaced.
        var canonicalID: String {
            switch self {
                case .cloudStorageFile(let reference):
                    reference.id
                default:
                    id
            }
        }

        var aiConversationFileScope: AIConversationFileScope {
            switch self {
                case .file(let file):
                    AIConversationFileScope(
                        kind: .libraryFile,
                        id: file.id?.uuidString ?? file.objectID.uriRepresentation().absoluteString
                    )
                case .localFile(let url):
                    AIConversationFileScope(kind: .localFile, id: url.absoluteString)
                case .temporaryFile(let url):
                    AIConversationFileScope(kind: .temporaryFile, id: url.absoluteString)
                case .collaborationFile(let file):
                    AIConversationFileScope(
                        kind: .collaborationFile,
                        id: file.id?.uuidString
                            ?? file.roomID
                            ?? file.objectID.uriRepresentation().absoluteString
                    )
                case .cloudStorageFile(let reference):
                    AIConversationFileScope(kind: .cloudStorageFile, id: reference.id)
            }
        }
        
        var name: String? {
            switch self {
                case .file(let file):
                    return file.name
                case .localFile(let url):
                    return fileType == .excalidrawPNG || fileType == .excalidrawSVG
                    ? url.deletingPathExtension().deletingPathExtension().lastPathComponent
                    : url.deletingPathExtension().lastPathComponent
                case .temporaryFile(let url):
                    return fileType == .excalidrawPNG || fileType == .excalidrawSVG
                    ? url.deletingPathExtension().deletingPathExtension().lastPathComponent
                    : url.deletingPathExtension().lastPathComponent
                case .collaborationFile(let file):
                    return file.name
                case .cloudStorageFile(let reference):
                    let url = URL(fileURLWithPath: reference.lastKnownName)
                    return fileType == .excalidrawPNG || fileType == .excalidrawSVG
                        ? url.deletingPathExtension().deletingPathExtension().lastPathComponent
                        : url.deletingPathExtension().lastPathComponent
            }
        }
        
        var updatedAt: Date? {
            switch self {
                case .file(let file):
                    file.updatedAt
                case .localFile(let url):
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                case .temporaryFile(let url):
                    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                case .collaborationFile(let file):
                    file.updatedAt
                case .cloudStorageFile(let reference):
                    reference.lastKnownModifiedAt
            }
        }

        var isInTrash: Bool {
            switch self {
                case .file(let file):
                    file.inTrash
                case .localFile, .temporaryFile, .collaborationFile, .cloudStorageFile:
                    false
            }
        }
        
        var fileType: UTType {
            switch self {
                case .localFile(let url):
                    return url.pathExtension == "svg"
                    ? .excalidrawSVG
                    : url.pathExtension == "png"
                    ? .excalidrawPNG
                    : .excalidrawFile
                case .temporaryFile(let url):
                    return url.pathExtension == "svg"
                    ? .excalidrawSVG
                    : url.pathExtension == "png"
                    ? .excalidrawPNG
                    : .excalidrawFile
                case .cloudStorageFile(let reference):
                    let pathExtension = (reference.lastKnownName as NSString).pathExtension.lowercased()
                    return pathExtension == "svg"
                        ? .excalidrawSVG
                        : pathExtension == "png"
                        ? .excalidrawPNG
                        : .excalidrawFile
                default:
                    return .excalidrawFile
            }
        }

        var usesLocalViewportSidecar: Bool {
            switch self {
                case .file, .cloudStorageFile:
                    true
                case .localFile, .temporaryFile, .collaborationFile:
                    false
            }
        }
    }

    struct CapturedCanvasSaveTarget: Sendable {
        enum Kind: Sendable {
            case libraryFile(
                objectURI: URL,
                fileName: String,
                newCheckpoint: Bool,
                suppressCheckpoint: Bool
            )
            case localFile(
                url: URL,
                newCheckpoint: Bool,
                suppressCheckpoint: Bool
            )
            case collaborationFile(
                objectURI: URL,
                fileName: String,
                newCheckpoint: Bool
            )
            case cloudStorageFile(
                reference: CloudStorageDocumentReference,
                newCheckpoint: Bool,
                suppressCheckpoint: Bool
            )

            var usesLocalViewportSidecar: Bool {
                switch self {
                    case .libraryFile, .cloudStorageFile:
                        true
                    case .localFile, .collaborationFile:
                        false
                }
            }

            var nativeFileName: String? {
                switch self {
                    case .libraryFile(_, let fileName, _, _):
                        fileName
                    case .localFile(let url, _, _):
                        url.deletingPathExtension().lastPathComponent
                    case .collaborationFile(_, let fileName, _):
                        fileName
                    case .cloudStorageFile(let reference, _, _):
                        URL(fileURLWithPath: reference.lastKnownName)
                            .deletingPathExtension()
                            .lastPathComponent
                }
            }
        }

        let id: String
        let kind: Kind
    }
    
    @Published private(set) var activeFileIndex: Int? = 0
    @Published private(set) var activeFiles: [ActiveFile?] = [nil] {
        willSet {
            guard let activeFileIndex else { return }
            self.activeFileIndex = min(newValue.endIndex - 1, activeFileIndex)
        }
        didSet {
            
        }
    }
    var currentActiveFile: ActiveFile? {
        if let activeFileIndex,
           activeFileIndex >= 0,
           activeFileIndex < activeFiles.count {
            return activeFiles[activeFileIndex]
        }
        return nil
    }

    @MainActor
    private var activeFileChangeGeneration = 0
    @MainActor
    private var pendingActiveFileOpenDurationOverrides: [String: TimeInterval] = [:]
    @MainActor
    var prepareActiveFileCloseTransition: (() async -> Void)?
    private let homeOpenNavigationUpdateDelay: UInt64 = 650_000_000

    @MainActor
    var activeFileBinding: Binding<ActiveFile?> {
        Binding {
            self.currentActiveFile
        } set: { newValue in
            self.setActiveFile(newValue)
        }
    }

    @MainActor
    private func applyActiveFile(_ newValue: ActiveFile?) {
        let previousActiveFile = currentActiveFile
        let previousConversationScope = previousActiveFile?.aiConversationFileScope
        let nextConversationScope = newValue?.aiConversationFileScope
        if previousConversationScope != nextConversationScope {
            aiChatConversationID = nil
            isAIChatConversationLoading = nextConversationScope != nil
        }
        if let activeFileIndex,
           activeFileIndex < activeFiles.count {
            if let newValue {
                activeFiles[activeFileIndex] = newValue
            } else if activeFileIndex > 0 {
                activeFiles.remove(at: activeFileIndex)
            } else {
                activeFiles[activeFileIndex] = nil
            }
        }

        shouldIgnoreUpdate = true
        recoverWatchUpdate()
        currentFilePublisherCancellables.forEach { $0.cancel() }
        resetSelections()
        if let previousActiveFile {
            didUpdateFileState[previousActiveFile] = false
            userCheckpointWindowStartedAt.removeValue(forKey: previousActiveFile.id)
        }
        if let newValue {
            didUpdateFileState[newValue] = false
            userCheckpointWindowStartedAt.removeValue(forKey: newValue.id)
        }
        resetCurrentFileChangesListener()
    }

    var currentActiveFileIsInTrash: Bool {
        currentActiveFile?.isInTrash == true
    }
    
    /// Set active file with automatic iCloud download handling.
    ///
    /// This is also the active-file transition boundary: before switching away
    /// from the current file, pending lightweight canvas dirty notifications are
    /// handed to a captured-target background save. External UI should route
    /// file changes through `setActiveFile(_:)` or `requestActiveFileChange(_:)`,
    /// not by mutating tab state directly.
    ///
    /// This method checks whether the file needs to be downloaded from iCloud
    /// and starts that download after the active file is selected.
    ///
    /// Use this method instead of directly setting `currentActiveFile` when
    /// the file might need to be downloaded from iCloud.
    ///
    /// - Parameter file: The file to activate
    /// - Throws: FileAccessError if download fails
    @MainActor
    func setActiveFile(
        _ file: ActiveFile?,
        openDurationOverride: TimeInterval? = nil
    ) {
        if let file, let openDurationOverride {
            pendingActiveFileOpenDurationOverrides[file.id] = openDurationOverride
        }
        activeFileChangeGeneration += 1
        let generation = activeFileChangeGeneration
        Task { @MainActor in
            await performActiveFileChange(file, generation: generation)
        }
    }

    @MainActor
    @discardableResult
    func requestActiveFileChange(
        _ file: ActiveFile?,
        openDurationOverride: TimeInterval? = nil
    ) async -> Bool {
        if let file, let openDurationOverride {
            pendingActiveFileOpenDurationOverrides[file.id] = openDurationOverride
        }
        activeFileChangeGeneration += 1
        let generation = activeFileChangeGeneration
        return await performActiveFileChange(file, generation: generation)
    }

    /// Closes an active cloud document before its backing item is removed.
    /// Keeping the item in the document store until the close transition
    /// completes preserves the File Home destination for the hero animation.
    @MainActor
    func closeActiveFileIfDeleting(
        anyOf references: Set<CloudStorageDocumentReference>
    ) async -> Bool {
        guard case .cloudStorageFile(let activeReference) = currentActiveFile,
              references.contains(where: {
                  $0.locationID == activeReference.locationID
                      && $0.itemID == activeReference.itemID
              }) else {
            return true
        }

        let transitionFileID = currentActiveFile?.canonicalID
        guard await requestActiveFileChange(nil) else { return false }
        if let transitionFileID {
            await waitForActiveFileCloseTransition(fileID: transitionFileID)
        }
        return true
    }

    @MainActor
    func completeActiveFileCloseTransition(fileID: String) {
        guard pendingActiveFileCloseTransitionIDs.remove(fileID) != nil else {
            return
        }
        let continuations = activeFileCloseTransitionContinuations.removeValue(
            forKey: fileID
        ) ?? []
        continuations.forEach { $0.resume() }
    }

    /// Closes the active editor session without persisting its canvas state.
    ///
    /// This is intentionally separate from the normal active-file transition,
    /// which flushes pending canvas changes before closing. Use it only when
    /// the current session must be discarded, such as cancelling unresolved
    /// cloud-storage conflict resolution.
    @MainActor
    func discardAndCloseActiveFile() {
        guard currentActiveFile != nil else { return }

        activeFileChangeGeneration += 1
        let generation = activeFileChangeGeneration
        let previousFile = currentActiveFile

        Task { @MainActor in
            await prepareActiveFileCloseTransitionIfNeeded(
                from: previousFile,
                to: nil
            )
            guard generation == activeFileChangeGeneration else { return }
            applyActiveFile(nil)
        }
    }

    @MainActor
    func consumeActiveFileOpenDurationOverride(for fileID: String) -> TimeInterval? {
        pendingActiveFileOpenDurationOverrides.removeValue(forKey: fileID)
    }

    @MainActor
    @discardableResult
    private func requestActiveLibraryFileChange(fileObjectID: NSManagedObjectID) async -> Bool {
        let context = PersistenceController.shared.container.viewContext
        guard let file = context.object(with: fileObjectID) as? File else {
            return false
        }
        return await requestActiveFileChange(.file(file))
    }

    @MainActor
    private func capturedCanvasSaveTarget(for activeFile: ActiveFile) -> CapturedCanvasSaveTarget? {
        switch activeFile {
            case .file(let file):
                guard !file.inTrash else { return nil }
                let suppressCheckpoint = automaticCheckpointWritesSuppressed
                return CapturedCanvasSaveTarget(
                    id: activeFile.id,
                    kind: .libraryFile(
                        objectURI: file.objectID.uriRepresentation(),
                        fileName: file.name ?? "Untitled",
                        newCheckpoint: suppressCheckpoint
                            ? false
                            : shouldCreateUserCheckpoint(for: activeFile),
                        suppressCheckpoint: suppressCheckpoint
                    )
                )

            case .localFile(let url), .temporaryFile(let url):
                let suppressCheckpoint = automaticCheckpointWritesSuppressed
                return CapturedCanvasSaveTarget(
                    id: activeFile.id,
                    kind: .localFile(
                        url: url,
                        newCheckpoint: suppressCheckpoint
                            ? false
                            : shouldCreateUserCheckpoint(for: activeFile),
                        suppressCheckpoint: suppressCheckpoint
                    )
                )

            case .collaborationFile(let file):
                return CapturedCanvasSaveTarget(
                    id: activeFile.id,
                    kind: .collaborationFile(
                        objectURI: file.objectID.uriRepresentation(),
                        fileName: file.name ?? "Untitled",
                        newCheckpoint: shouldCreateUserCheckpoint(for: activeFile)
                    )
                )
            case .cloudStorageFile(let reference):
                didUpdateFileState[activeFile] = true
                let suppressCheckpoint = automaticCheckpointWritesSuppressed
                return CapturedCanvasSaveTarget(
                    id: activeFile.id,
                    kind: .cloudStorageFile(
                        reference: reference,
                        newCheckpoint: suppressCheckpoint
                            ? false
                            : shouldCreateUserCheckpoint(for: activeFile),
                        suppressCheckpoint: suppressCheckpoint
                    )
                )
        }
    }

    @MainActor
    private func canvasCoordinator(for activeFile: ActiveFile) -> ExcalidrawCanvasView.Coordinator? {
        if case .collaborationFile = activeFile {
            return excalidrawCollaborationWebCoordinator
        }
        return excalidrawWebCoordinator
    }

    @MainActor
    private func performActiveFileChange(
        _ file: ActiveFile?,
        generation: Int
    ) async -> Bool {
        let file = if case .cloudStorageFile(let reference) = file {
            ActiveFile.cloudStorageFile(
                CloudStorageDocumentStore.shared.resolvingCurrentIdentity(for: reference)
            )
        } else {
            file
        }

        if aiChatSession != nil, currentActiveFile != file {
            activeFileSwitchBlockedReason = .aiGenerationInProgress
            activeFileSwitchBlockedToken += 1
            return false
        }

        if currentActiveFile == file {
            return true
        }

        let previousFile = currentActiveFile
        let shouldDelayNavigationUpdate = currentActiveFile == nil && file != nil

        await prepareActiveFileCloseTransitionIfNeeded(
            from: previousFile,
            to: file
        )

        if let previousFile,
           let saveTarget = capturedCanvasSaveTarget(for: previousFile) {
            let coordinator = canvasCoordinator(for: previousFile)
            if file == nil {
                isFinalizingActiveFileClose = true
                defer {
                    isFinalizingActiveFileClose = false
                }

                await coordinator?.documentSyncController.flushPendingDirtySnapshotToCapturedTarget(
                    reason: "activeFileClose",
                    expectedFileID: previousFile.id,
                    target: saveTarget,
                    forceCurrentAppState: true
                )
                await FileCoverCacheCoordinator.shared.cacheCurrentViewportPreview(
                    for: previousFile
                )
            } else {
                await FileCoverCacheCoordinator.shared.cacheCurrentViewportPreview(
                    for: previousFile
                )
                await coordinator?.documentSyncController.flushPendingDirtySnapshotInBackground(
                    reason: "activeFileWillChange",
                    expectedFileID: previousFile.id,
                    target: saveTarget
                )
            }
        }

        guard generation == activeFileChangeGeneration else {
            return false
        }

        if let previousFile {
            // Checkpoint windows are editor-session scoped. Reopening the file
            // starts a new history segment even when less than ten minutes passed.
            userCheckpointWindowStartedAt.removeValue(forKey: previousFile.id)
        }

        if file == nil, let previousFile {
            pendingActiveFileCloseTransitionIDs.insert(previousFile.canonicalID)
        }
        applyActiveFile(file)

        guard let file else {
            return true
        }

        if case .collaborationFile = file {
            recordVisit(for: file)
        }
        let context = PersistenceController.shared.container.viewContext
        let activeFileID = file.id
        switch file {
            case .localFile(let url):
                Task {
                    if shouldDelayNavigationUpdate {
                        try? await Task.sleep(nanoseconds: homeOpenNavigationUpdateDelay)
                    }
                    guard shouldApplyNavigationUpdate(
                        fileID: activeFileID,
                        generation: generation
                    ) else {
                        return
                    }

                    do {
                        let parentURL = url.deletingLastPathComponent().standardizedFileURL
                        if case .localFolder(let activeFolder) = currentActiveGroup,
                           let activeFolderPath = activeFolder.filePath,
                           URL(fileURLWithPath: activeFolderPath).standardizedFileURL.path
                            == parentURL.path {
                            expandToGroup(activeFolder.objectID)
                            return
                        }

                        let folder = try await context.perform {
                            try LocalFolder.deepestFolder(
                                containingLocalFileAt: url,
                                in: context
                            )
                        }
                        if let folder {
                            setActiveGroupIfNeeded(.localFolder(folder))
                            expandToGroup(folder.objectID)
                        } else {
                            setActiveGroupIfNeeded(nil)
                        }
                    } catch {}
                }
                // Check iCloud status
                let statusBox = FileStatusService.shared.statusBox(for: file)
                let status = statusBox.status

                logger.debug("Setting active file: \(url.lastPathComponent), status: \(status)")

                // Download if needed (notDownloaded, outdated, or currently downloading)
                if status.iCloudStatus == .notDownloaded || status.iCloudStatus == .outdated || status.iCloudStatus.isInProgress {
                    logger.info("Downloading file: \(url.lastPathComponent)")
                    Task {
                        do {
                            try await FileSyncCoordinator.shared.downloadFile(url)
                        } catch {
                            logger.error("Failed to download local file \(url.lastPathComponent): \(error)")
                        }
                    }
                }
            case .file(let dbFile):
                Task { @MainActor in
                    if shouldDelayNavigationUpdate {
                        try? await Task.sleep(nanoseconds: homeOpenNavigationUpdateDelay)
                    }
                    guard shouldApplyNavigationUpdate(
                        fileID: activeFileID,
                        generation: generation
                    ) else {
                        return
                    }

                    if dbFile.group == nil {
                        setActiveGroupIfNeeded(nil)
                    } else if dbFile.inTrash {
                        let trashGroup = await context.perform {
                            let trashGroupFetchRequest = NSFetchRequest<Group>(entityName: "Group")
                            trashGroupFetchRequest.predicate = NSPredicate(format: "type == 'trash'")
                            return try? context.fetch(trashGroupFetchRequest).first
                        }
                        
                        setActiveGroupIfNeeded(.group(trashGroup ?? dbFile.group!))
                    } else {
                        setActiveGroupIfNeeded(.group(dbFile.group!))
                    }
                    if let groupID = dbFile.group?.objectID, dbFile.inTrash == false {
                        expandToGroup(groupID)
                    }
                }
                
            case .temporaryFile(let url):
                Task { @MainActor in
                    if shouldDelayNavigationUpdate {
                        try? await Task.sleep(nanoseconds: homeOpenNavigationUpdateDelay)
                    }
                    guard shouldApplyNavigationUpdate(
                        fileID: activeFileID,
                        generation: generation
                    ) else {
                        return
                    }

                    registerTemporaryFile(url)
                    setActiveGroupIfNeeded(.temporary)
                }
            case .collaborationFile(let room):
                let store = Store.shared
                if let limit = store.collaborationRoomLimits,
                   collaboratingFiles.count >= limit,
                   !collaboratingFiles.contains(room) {
                    store.togglePaywall(reason: .roomLimit)
                } else {
                    setActiveGroupIfNeeded(.collaboration)
                    if !collaboratingFiles.contains(room) {
                        collaboratingFiles.append(room)
                    }
                    if collaboratingFilesState[room] == nil {
                        collaboratingFilesState[room] = .loading
                    }
                }
            case .cloudStorageFile(let reference):
                if let folder = CloudStorageDocumentStore.shared.bestKnownParentFolder(for: reference) {
                    setActiveGroupIfNeeded(.cloudStorageFolder(folder))
                }
        }
        return true
    }

    @MainActor
    private func prepareActiveFileCloseTransitionIfNeeded(
        from previousFile: ActiveFile?,
        to nextFile: ActiveFile?
    ) async {
        guard previousFile != nil, nextFile == nil else { return }
        await prepareActiveFileCloseTransition?()
    }

    @MainActor
    private func waitForActiveFileCloseTransition(fileID: String) async {
        guard pendingActiveFileCloseTransitionIDs.contains(fileID) else {
            return
        }
        await withCheckedContinuation { continuation in
            activeFileCloseTransitionContinuations[fileID, default: []]
                .append(continuation)
        }
    }

    @MainActor
    private func shouldApplyNavigationUpdate(
        fileID: String,
        generation: Int
    ) -> Bool {
        generation == activeFileChangeGeneration && currentActiveFile?.id == fileID
    }

    @MainActor
    func recordVisitAfterFileReady(fileID: String) {
        guard let currentActiveFile,
              currentActiveFile.id == fileID else { return }
        recordVisit(for: currentActiveFile)
    }

    @MainActor
    private func recordVisit(for file: ActiveFile) {
        let now = Date()
        switch file {
            case .file(let dbFile):
                guard dbFile.inTrash == false else { return }
                dbFile.visitedAt = now
                saveVisitedAtChange(in: dbFile.managedObjectContext)
            case .collaborationFile(let room):
                room.visitedAt = now
                saveVisitedAtChange(in: room.managedObjectContext)
            case .localFile, .temporaryFile, .cloudStorageFile:
                break
        }
    }

    @MainActor
    private func saveVisitedAtChange(in context: NSManagedObjectContext?) {
        guard let context, context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Failed to save file visit timestamp: \(error.localizedDescription)")
        }
    }
    
    @Published var selectedGroups: Set<NSManagedObjectID> = []
    // @Published var selectedLocalFolders: Set<LocalFolder> = []
    
    @Published var selectedFiles: Set<File> = []
    @Published var selectedStartFile: File?
    
    @Published var selectedLocalFiles: Set<URL> = []
    @Published var selectedStartLocalFile: URL?
    
    @Published var temporaryFiles: [URL] = [] {
        didSet {
            updateOpenInPlaceOwnership(from: oldValue, to: temporaryFiles)
        }
    }

    @MainActor
    func prepareOpenInPlaceAccess(to url: URL) async throws {
        let key = url.standardizedFileURL
        let wasRegistered = temporaryFiles.contains {
            $0.standardizedFileURL == key
        }
        registerTemporaryFile(url)

        do {
            try await openInPlaceAccessStore.prepareAccess(to: url)
        } catch {
            if !wasRegistered {
                temporaryFiles.removeAll { $0.standardizedFileURL == key }
            }
            throw error
        }
    }

    @MainActor
    func registerTemporaryFile(_ url: URL) {
        let key = url.standardizedFileURL
        guard !temporaryFiles.contains(where: { $0.standardizedFileURL == key }) else {
            return
        }
        temporaryFiles.append(url)
    }

    @MainActor
    func readTemporaryFileContent(at url: URL) async throws -> Data {
        if let content = openInPlaceAccessStore.content(for: url) {
            return content
        }
        return try await FileSyncCoordinator.shared.openFileWithActiveSecurityScope(url)
    }

    /// A directly opened document is owned by its Temporary workspace, not by
    /// the currently visible editor. Keep its UIDocument session alive while
    /// the row exists so returning from the editor does not revoke access.
    private func updateOpenInPlaceOwnership(from oldURLs: [URL], to newURLs: [URL]) {
        let oldKeys = Set(oldURLs.map(\.standardizedFileURL))
        let newKeys = Set(newURLs.map(\.standardizedFileURL))
        let addedKeys = newKeys.subtracting(oldKeys)
        let removedKeys = oldKeys.subtracting(newKeys)

        guard !addedKeys.isEmpty || !removedKeys.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let currentKeys = Set(self.temporaryFiles.map(\.standardizedFileURL))

            for url in addedKeys where currentKeys.contains(url) {
                self.openInPlaceAccessStore.retainAccess(to: url)
            }
            for url in removedKeys where !currentKeys.contains(url) {
                self.openInPlaceAccessStore.releaseAccess(to: url)
            }
        }
    }
    
    @Published var selectedTemporaryFiles: Set<URL> = []
    @Published var selectedStartTemporaryFile: URL?

    @Published var selectedCloudStorageFiles: Set<CloudStorageDocumentReference> = []
    @Published var selectedStartCloudStorageFile: CloudStorageDocumentReference?
    
    // Collab
    var isInCollaborationSpace: Bool {
        if case .collaborationFile = currentActiveFile {
            return true
        }
        if case .collaboration = currentActiveGroup {
            return true
        }
        return false
    }
    
    // MARK: - AI Chat

    enum ActiveFileSwitchBlockedReason: Equatable {
        case aiGenerationInProgress
    }

    @Published var activeFileSwitchBlockedReason: ActiveFileSwitchBlockedReason?
    @Published var activeFileSwitchBlockedToken: Int = 0

    /// The currently active AI chat conversation id.
    ///
    /// Stored on `FileState` because conversations are conceptually scoped to
    /// the file the user is working on — each file will eventually own a set
    /// of persisted conversations (Core Data), with this property pointing at
    /// the one currently visible. For now we only track a single in-memory id;
    /// the AIChatView/AIChatIslandView read and write through here so the
    /// inspector and the floating island stay in sync across presentation
    /// toggles.
    @Published var aiChatConversationID: String? = nil
    @Published var isAIChatConversationLoading: Bool = false

    /// Active AI chat session, if any. While this is non-nil:
    ///
    /// 1. `updateFile` / `updateLocalFile` switch to checkpoint policy
    ///    `.suppress` — content saves, no history rows created. The user
    ///    explicitly asked for "一刀切" — no per-edit history during AI
    ///    runs (whether the edit was user-driven or AI-tool-driven).
    /// 2. `beginAIChatSession` records an `.aiPre` snapshot before the
    ///    user message hits the LLM and links it to that message through
    ///    `AIMessageCheckpointLink`. `endAIChatSession(success: true, ...)`
    ///    records the matching `.aiPost` snapshot and links it to the
    ///    assistant final-answer id.
    ///
    /// One session per (FileState, conversationID) — each user message
    /// inside the same conversation re-enters begin/end with a fresh
    /// (pre, post) pair anchored to that message round.
    @Published var aiChatSession: AIChatSessionState?

    /// Nested MCP mutation depth. While non-zero, normal canvas save paths
    /// still persist file content but must not create user-edit checkpoints;
    /// the MCP bridge writes explicit `.mcpPre` / `.mcpPost` rows instead.
    var mcpCheckpointSuppressionDepth: Int = 0

    /// Shared guard for automated mutation sessions that manage their own
    /// explicit checkpoint boundaries.
    var automaticCheckpointWritesSuppressed: Bool {
        aiChatSession != nil || mcpCheckpointSuppressionDepth > 0
    }

    struct AIChatSessionState: Equatable {
        /// Conversation id this session belongs to. Surfaced for sanity
        /// checks (the conversation could in theory change mid-session
        /// if the user navigates between files).
        let conversationID: String
        /// User chat message id that triggered the session.
        let userMessageID: String
        /// `ActiveFile` snapshot at session begin. Optional because the
        /// user can fire off an AI message with no file open (e.g. asking
        /// the AI to *create* a new file). When `nil`, no `.aiPre` row
        /// gets written — there's nothing to snapshot. We still open the
        /// session so the suppression flag prevents stray history while
        /// the AI runs.
        let anchorFile: ActiveFile?
        /// Exact `.aiPre` checkpoint created for this session, if any.
        /// Used to delete only this eager checkpoint when a read-only
        /// round can safely rebind to an earlier checkpoint.
        var preCheckpointID: UUID? = nil
        var preCheckpointKind: AIMessageCheckpointKind? = nil
    }

    /// Files that is currently under collaboration.
    @Published var collaboratingFiles: [CollaborationFile] = []
    @Published var collaboratingFilesState: [CollaborationFile : ExcalidrawCanvasView.LoadingState] = [:]
    @Published var collaborators: [CollaborationFile : [Collaborator]] = [:]
    @Published var isFinalizingActiveFileClose = false

    var activeCollaborationFileIsLoading: Bool {
        guard case .collaborationFile(let file) = currentActiveFile else {
            return false
        }

        switch collaboratingFilesState[file] {
            case .loaded, .error:
                return false
            case .idle, .loading, .none:
                return true
        }
    }

    enum CollborationRoute: Hashable {
        case home
        case room(CollaborationFile)
        
        var room: CollaborationFile? {
            switch self {
                case .home:
                    nil
                case .room(let collaborationFile):
                    collaborationFile
            }
        }
    }
    
    var currentCollaborators: [Collaborator] {
        if case .collaborationFile(let file) = currentActiveFile {
            collaborators[file] ?? []
        } else {
            []
        }
    }
    
    @AppStorage("ExcalidrawFileSortField") var sortField: ExcalidrawFileSortField = .updatedAt
    
    var excalidrawWebCoordinator: ExcalidrawCanvasView.Coordinator?
    var excalidrawCollaborationWebCoordinator: ExcalidrawCanvasView.Coordinator?
    
    var shouldIgnoreUpdate = true
    /// Indicate the file is being updated after being set as current file.
    var didUpdateFile = false
    var didUpdateFileState: [ActiveFile : Bool] = [:]
    private var userCheckpointWindowStartedAt: [String: Date] = [:]
    var isCreatingFile = false
    private var pendingProgrammaticCanvasCommitDates: [String: Date] = [:]
    private var recentLocalCanvasMutationDates: [String: Date] = [:]
    
    var recoverWatchUpdateWorkItem: DispatchWorkItem?
    
    private func recoverWatchUpdate() {
        recoverWatchUpdateWorkItem?.cancel()
        recoverWatchUpdateWorkItem = DispatchWorkItem(flags: .assignCurrentContext) {
            if self.activeCanvasIsLoading {
                self.recoverWatchUpdate()
                return
            }
            self.shouldIgnoreUpdate = false
            self.didUpdateFile = false
        }
        stateUpdateQueue.asyncAfter(deadline: .now().advanced(by: .milliseconds(2500)), execute: recoverWatchUpdateWorkItem!)
    }

    private var activeCanvasIsLoading: Bool {
        if case .collaborationFile = currentActiveFile {
            let coreIsLoading = excalidrawCollaborationWebCoordinator?.isLoading == true
            return coreIsLoading || activeCollaborationFileIsLoading
        }
        return excalidrawWebCoordinator?.isLoading == true
    }

    func noteProgrammaticCanvasMutation(fileID: String) {
        pendingProgrammaticCanvasCommitDates[fileID] = Date()
        recentLocalCanvasMutationDates[fileID] = Date()
        pruneProgrammaticCanvasMutationDates()
    }

    func recentLocalCanvasMutationDate(for activeFile: ActiveFile?) -> Date? {
        pruneRecentLocalCanvasMutationDates()
        guard let fileID = activeFile?.id else { return nil }
        return recentLocalCanvasMutationDates[fileID]
    }

    private func consumeProgrammaticCanvasCommitAllowance(fileID: String) -> Bool {
        pruneProgrammaticCanvasMutationDates()
        guard pendingProgrammaticCanvasCommitDates.removeValue(forKey: fileID) != nil else {
            return false
        }
        return true
    }

    private func shouldAcceptCanvasUpdate(
        fileID: String,
        label: String
    ) -> Bool {
        let hasProgrammaticAllowance = consumeProgrammaticCanvasCommitAllowance(fileID: fileID)
        if shouldIgnoreUpdate {
            guard hasProgrammaticAllowance, !activeCanvasIsLoading else {
                return false
            }
            logger.info("Accepting programmatic canvas update while update gate is recovering: \(label)")
            recoverWatchUpdateWorkItem?.cancel()
            recoverWatchUpdateWorkItem = nil
            shouldIgnoreUpdate = false
            didUpdateFile = false
        }
        return true
    }

    @MainActor
    private func shouldCreateUserCheckpoint(
        for activeFile: ActiveFile,
        now: Date = .now
    ) -> Bool {
        let startedAt = userCheckpointWindowStartedAt[activeFile.id]
        guard UserCheckpointRolloverPolicy.shouldStartNewWindow(
            startedAt: startedAt,
            now: now
        ) else {
            return false
        }
        userCheckpointWindowStartedAt[activeFile.id] = now
        return true
    }

    private func pruneRecentLocalCanvasMutationDates() {
        let cutoff = Date().addingTimeInterval(-30)
        recentLocalCanvasMutationDates = recentLocalCanvasMutationDates.filter { _, date in
            date >= cutoff
        }
    }

    private func pruneProgrammaticCanvasMutationDates() {
        let cutoff = Date().addingTimeInterval(-10)
        pendingProgrammaticCanvasCommitDates = pendingProgrammaticCanvasCommitDates.filter { _, date in
            date >= cutoff
        }
        pruneRecentLocalCanvasMutationDates()
    }
    
    @discardableResult
    func createNewGroup(
        name: String,
        activate: Bool = true,
        parentGroupID: NSManagedObjectID? = nil,
        context: NSManagedObjectContext,
        animation: Animation? = nil,
    ) async throws -> NSManagedObjectID {
        let groupID = try await context.perform {
            let group = withAnimation(animation) {
                
                let group = Group(name: name, context: context)
                
                if let parentGroupID,
                   let parent = context.object(with: parentGroupID) as? Group {
                    group.parent = parent
                }
                
                context.insert(group)
                return group
            }
            
            try context.save()
            
            return group.objectID
        }
        
        if activate {
            await MainActor.run {
                if let group = context.object(with: groupID) as? Group {
                    self.currentActiveGroup = .group(group)
                    self.expandToGroup(group.objectID)
                }
            }
        }
        
        return groupID
    }
    
    @discardableResult
    func createNewFile(
        active: Bool = true,
        in groupID: NSManagedObjectID? = nil,
        context: NSManagedObjectContext
    ) async throws -> NSManagedObjectID {
        guard let targetGroupID = groupID ?? {
            if case .group(let currentGroup) = self.currentActiveGroup {
                return currentGroup.objectID
            }
            return nil
        }() else { throw AppError.stateError(.currentGroupNil) }
        
        let templateData = ExcalidrawFile().content!
        
        // Create file through repository (creates entity and saves to iCloud Drive)
        let fileID = try await PersistenceController.shared.fileRepository.createFile(
            name: String(localizable: .newFileNamePlaceholder),
            content: templateData,
            groupObjectID: targetGroupID
        )
        
        if active {
            await requestActiveLibraryFileChange(fileObjectID: fileID)
        }
        
        return fileID
    }
    
    @discardableResult
    @MainActor
    func persistPreparedLibraryCanvasUpdate(
        _ file: File,
        with excalidrawFile: ExcalidrawFile
    ) -> Bool {
        let activeFile = ActiveFile.file(file)
        guard !file.inTrash,
              shouldAcceptCanvasUpdate(fileID: activeFile.id, label: file.name ?? "Untitled") else {
            return false
        }
        let id = file.objectID
        let suppressCheckpoint = automaticCheckpointWritesSuppressed
        let newCheckpoint = suppressCheckpoint
            ? false
            : shouldCreateUserCheckpoint(for: activeFile)
        self.didUpdateFileState[activeFile] = true
        Task.detached {
            do {
                guard let content = excalidrawFile.content else { return }
                
                // Step 1: Sync media items from ExcalidrawFile (creates new ones and saves to iCloud Drive)
                _ = try await PersistenceController.shared.mediaItemRepository.syncMediaItemsForFile(
                    excalidrawFile: excalidrawFile,
                    fileObjectID: id
                )
                
                // Step 2: Update file elements through repository.
                // Checkpoint policy: suppress entirely while an AI/MCP
                // mutation session is active (so automated mutations don't
                // pollute user history); otherwise fall back to historical
                // user-edit semantics.
                let checkpointPolicy: CheckpointWriteOptions = suppressCheckpoint
                    ? .suppress
                    : .userEdit(newCheckpoint: newCheckpoint)
                try await PersistenceController.shared.fileRepository.updateElements(
                    fileObjectID: id,
                    fileData: content,
                    checkpoint: checkpointPolicy
                )
                self.logger.debug("File update saved")
                await MainActor.run {
                    // already throttled
                    self.objectWillChange.send()
                }
            } catch {
                self.logger.error("Failed to update file \(file.name ?? "Untitled"): \(error)")
            }
        }
        return true
    }

    @MainActor
    func updateCloudStorageFile(
        _ reference: CloudStorageDocumentReference,
        content: Data
    ) async throws {
        let activeFile = ActiveFile.cloudStorageFile(reference)
        let suppressCheckpoint = automaticCheckpointWritesSuppressed
        let newCheckpoint = suppressCheckpoint
            ? false
            : shouldCreateUserCheckpoint(for: activeFile)
        didUpdateFileState[activeFile] = true
        try await Self.saveCloudStorageCanvasContent(
            reference: reference,
            content: content,
            newCheckpoint: newCheckpoint,
            suppressCheckpoint: suppressCheckpoint,
            logger: logger
        )
        objectWillChange.send()
    }

    static func saveCapturedCanvasUpdate(
        _ target: CapturedCanvasSaveTarget,
        with excalidrawFile: ExcalidrawFile
    ) async {
        let logger = Logger(label: "FileState")
        do {
            try await persistCapturedCanvasUpdate(
                target,
                with: excalidrawFile,
                logger: logger
            )
        } catch {
            logger.error("Failed to update background captured file \(target.id): \(error)")
        }
    }

    static func persistCapturedCanvasUpdate(
        _ target: CapturedCanvasSaveTarget,
        with excalidrawFile: ExcalidrawFile
    ) async throws {
        try await persistCapturedCanvasUpdate(
            target,
            with: excalidrawFile,
            logger: Logger(label: "FileState")
        )
    }

    private static func persistCapturedCanvasUpdate(
        _ target: CapturedCanvasSaveTarget,
        with excalidrawFile: ExcalidrawFile,
        logger: Logger
    ) async throws {
        switch target.kind {
            case .libraryFile(let objectURI, let fileName, let newCheckpoint, let suppressCheckpoint):
                guard let fileObjectID = managedObjectID(for: objectURI),
                      let content = excalidrawFile.content else {
                    throw AppError.fileError(.notFound)
                }
                _ = try await PersistenceController.shared.mediaItemRepository.syncMediaItemsForFile(
                    excalidrawFile: excalidrawFile,
                    fileObjectID: fileObjectID
                )
                let checkpointPolicy: CheckpointWriteOptions = suppressCheckpoint
                    ? .suppress
                    : .userEdit(newCheckpoint: newCheckpoint)
                try await PersistenceController.shared.fileRepository.updateElements(
                    fileObjectID: fileObjectID,
                    fileData: content,
                    checkpoint: checkpointPolicy
                )
                logger.debug("Background captured file update saved: \(fileName)")

            case .localFile(let url, let newCheckpoint, let suppressCheckpoint):
                try await saveCapturedLocalCanvasUpdate(
                    to: url,
                    with: excalidrawFile,
                    newCheckpoint: newCheckpoint,
                    suppressCheckpoint: suppressCheckpoint,
                    logger: logger
                )

            case .collaborationFile(let objectURI, let fileName, let newCheckpoint):
                guard let collaborationFileObjectID = managedObjectID(for: objectURI),
                      let content = excalidrawFile.content else {
                    throw AppError.fileError(.notFound)
                }
                try await PersistenceController.shared.collaborationFileRepository.updateElements(
                    collaborationFileObjectID: collaborationFileObjectID,
                    content: content,
                    newCheckpoint: newCheckpoint
                )
                logger.debug("Background captured collaboration file update saved: \(fileName)")

            case .cloudStorageFile(let reference, let newCheckpoint, let suppressCheckpoint):
                try await saveCloudStorageCanvasUpdate(
                    reference: reference,
                    excalidrawFile: excalidrawFile,
                    newCheckpoint: newCheckpoint,
                    suppressCheckpoint: suppressCheckpoint,
                    logger: logger
                )
                logger.debug("Background captured cloud storage file update cached: \(reference.lastKnownName)")
        }
    }

    private static func saveCloudStorageCanvasUpdate(
        reference: CloudStorageDocumentReference,
        excalidrawFile: ExcalidrawFile,
        newCheckpoint: Bool,
        suppressCheckpoint: Bool,
        logger: Logger
    ) async throws {
        var file = excalidrawFile
        try file.updateContentFilesFromFiles()
        guard let content = file.content else {
            throw AppError.fileError(.notFound)
        }

        try await saveCloudStorageCanvasContent(
            reference: reference,
            content: content,
            newCheckpoint: newCheckpoint,
            suppressCheckpoint: suppressCheckpoint,
            logger: logger
        )
    }

    private static func saveCloudStorageCanvasContent(
        reference: CloudStorageDocumentReference,
        content: Data,
        newCheckpoint: Bool,
        suppressCheckpoint: Bool,
        logger: Logger
    ) async throws {
        try await stageCloudStorageUpload(content, for: reference)
        if !suppressCheckpoint {
            do {
                try await CloudStorageCheckpointStore.recordUserEdit(
                    content: content,
                    for: reference,
                    newCheckpoint: newCheckpoint
                )
            } catch {
                logger.warning(
                    "Failed to record cloud checkpoint for \(reference.lastKnownName): \(error.localizedDescription)"
                )
            }
        }
    }

    private static func stageCloudStorageUpload(
        _ content: Data,
        for reference: CloudStorageDocumentReference
    ) async throws {
        let needsUpload = try await CloudStorageDocumentStore.shared.saveToLocalCache(
            content,
            for: reference
        )
        if needsUpload {
            await CloudStorageSyncService.shared.enqueueUpload(for: reference)
        }
    }

    static func saveCapturedAppStateOnlyUpdate(
        _ target: CapturedCanvasSaveTarget,
        content: Data
    ) async {
        let logger = Logger(label: "FileState")
        do {
            switch target.kind {
                case .libraryFile(let objectURI, let fileName, _, _):
                    guard let fileObjectID = managedObjectID(for: objectURI) else { return }
                    try await PersistenceController.shared.fileRepository.updateElements(
                        fileObjectID: fileObjectID,
                        fileData: content,
                        checkpoint: .suppress,
                        updateMetadataWhenPathUnchanged: false
                    )
                    logger.debug("Background appState-only file update saved: \(fileName)")

                case .localFile(let url, _, _):
                    try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: url) {
                        try await FileCoordinator.shared.coordinatedWrite(url: url, data: content)
                    }
                    logger.debug("Background appState-only local file update saved: \(url.lastPathComponent)")

                case .collaborationFile:
                    break

                case .cloudStorageFile(let reference, _, _):
                    try await stageCloudStorageUpload(content, for: reference)
                    logger.debug(
                        "Background appState-only cloud storage file update cached: \(reference.lastKnownName)"
                    )
            }
        } catch {
            logger.error("Failed to update background appState-only file \(target.id): \(error)")
        }
    }

    private static func saveCapturedLocalCanvasUpdate(
        to url: URL,
        with file: ExcalidrawFile,
        newCheckpoint: Bool,
        suppressCheckpoint: Bool,
        logger: Logger
    ) async throws {
        var file = file
        try file.updateContentFilesFromFiles()
        guard let data = file.content else { return }

        try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: url) {
            try await FileCoordinator.shared.coordinatedWrite(url: url, data: data)
            touchLocalFileModificationDate(url, logger: logger)
        }

        guard !suppressCheckpoint else {
            logger.debug("Background captured local file update saved without checkpoint: \(url.lastPathComponent)")
            return
        }

        try await LocalFileCheckpointStore.recordUserEdit(
            content: data,
            for: url,
            newCheckpoint: newCheckpoint
        )

        logger.debug("Background captured local file update saved: \(url.lastPathComponent)")
    }

    private static func managedObjectID(for uri: URL) -> NSManagedObjectID? {
        PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(
            forURIRepresentation: uri
        )
    }

    @MainActor
    func updateAppStateOnlyForCurrentFile(
        expectedFileID: String?,
        content: Data
    ) {
        guard let activeFile = currentActiveFile,
              expectedFileID == nil || activeFile.id == expectedFileID else {
            return
        }

        switch activeFile {
            case .file(let file):
                guard !file.inTrash else { return }
                let fileObjectID = file.objectID
                let fileName = file.name ?? "Untitled"
                Task.detached {
                    do {
                        try await PersistenceController.shared.fileRepository.updateElements(
                            fileObjectID: fileObjectID,
                            fileData: content,
                            checkpoint: .suppress,
                            updateMetadataWhenPathUnchanged: false
                        )
                        self.logger.debug("AppState-only file update saved")
                    } catch {
                        self.logger.error("Failed to update appState-only file \(fileName): \(error)")
                    }
                }

            case .localFile(let url), .temporaryFile(let url):
                Task.detached {
                    do {
                        try await LocalFolder.withSecurityScopedAccessToContainingFolder(for: url) {
                            try await FileCoordinator.shared.coordinatedWrite(url: url, data: content)
                        }
                        self.logger.debug("AppState-only local file update saved")
                    } catch {
                        self.logger.error("Failed to update appState-only local file \(url.lastPathComponent): \(error)")
                    }
                }

            case .collaborationFile:
                break

            case .cloudStorageFile(let reference):
                Task {
                    do {
                        try await Self.stageCloudStorageUpload(content, for: reference)
                        self.logger.debug("AppState-only cloud storage file update cached")
                    } catch {
                        self.logger.error(
                            "Failed to update appState-only cloud storage file \(reference.lastKnownName): \(error)"
                        )
                    }
                }
        }
    }

    @MainActor
    func flushPendingCanvasSnapshotBeforeTermination() async {
        if let activeFile = currentActiveFile,
           let saveTarget = capturedCanvasSaveTarget(for: activeFile),
           let coordinator = canvasCoordinator(for: activeFile) {
            await coordinator.documentSyncController.flushPendingDirtySnapshotToCapturedTarget(
                reason: "applicationShouldTerminate",
                expectedFileID: activeFile.id,
                target: saveTarget,
                forceCurrentAppState: true
            )
            return
        }

        await excalidrawWebCoordinator?.documentSyncController.flushPendingDirtySnapshot(
            reason: "applicationShouldTerminate",
            force: true
        )
    }

    @MainActor
    func flushPendingCanvasSnapshotBeforeExternalMutation(fileID: String) async {
        guard let activeFile = currentActiveFile,
              activeFile.id == fileID,
              let saveTarget = capturedCanvasSaveTarget(for: activeFile),
              let coordinator = canvasCoordinator(for: activeFile) else {
            return
        }

        await coordinator.documentSyncController
            .flushPendingDirtySnapshotToCapturedTarget(
                reason: "externalDocumentMutation",
                expectedFileID: fileID,
                target: saveTarget,
                forceCurrentAppState: true
            )
    }

    @discardableResult
    func createNewLocalFile(active: Bool = true, folderURL scopedURL: URL) async throws -> URL? {
        guard let data = ExcalidrawFile().content else { return nil }
        var newFileName = "Untitled"
        
        while FileManager.default.fileExists(
            at: scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)
        ) {
            let components = newFileName.components(separatedBy: "-")
            if components.count == 2, let numComponent = components.last, let index = Int(numComponent) {
                newFileName = "\(components[0])-\(index+1)"
            } else {
                newFileName = "\(newFileName)-1"
            }
        }
        
        let fileURL = scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)

        // Use FileCoordinator for safe atomic write
        try await FileCoordinator.shared.coordinatedWrite(url: fileURL, data: data)
        
        if active {
            await requestActiveFileChange(.localFile(fileURL))
        }
        
        return fileURL
    }
    
    /// Remember to call `startAccessingSecurityScopedResource` before calling this function.
    func updateLocalFile(to url: URL, with excalidrawFile: ExcalidrawFile, context: NSManagedObjectContext) async throws {
        guard shouldAcceptCanvasUpdate(fileID: url.absoluteString, label: url.lastPathComponent) else { return }
        var excalidrawFile = excalidrawFile
        try excalidrawFile.updateContentFilesFromFiles()

        guard let data = excalidrawFile.content else { return }
        let savedThroughDocumentSession = try await openInPlaceAccessStore.save(data, to: url)
        if !savedThroughDocumentSession {
            // Linked Folder files retain a folder-scoped bookmark and continue
            // to use coordinated URL access. Directly opened iOS documents are
            // saved by their UIDocument session instead.
            try await FileCoordinator.shared.coordinatedWrite(url: url, data: data)
            Self.touchLocalFileModificationDate(url, logger: logger)
        }

        // Skip checkpoint writes entirely while an automated mutation session
        // is active — file content still saves, history doesn't. Mirrors the
        // database-file path's `.suppress` policy.
        let suppressCheckpoint = await MainActor.run {
            self.automaticCheckpointWritesSuppressed
        }
        if suppressCheckpoint {
            await MainActor.run {
                self.didUpdateFile = true
                self.objectWillChange.send()
            }
            return
        }

        let newCheckpoint = await MainActor.run {
            self.shouldCreateUserCheckpoint(for: .localFile(url))
        }

        try await LocalFileCheckpointStore.recordUserEdit(
            content: data,
            for: url,
            newCheckpoint: newCheckpoint
        )

        await MainActor.run {
            self.didUpdateFile = true
            self.objectWillChange.send()
        }
    }

    static func touchLocalFileModificationDate(
        _ url: URL,
        date: Date = Date(),
        logger: Logger
    ) {
        do {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.filePath
            )
        } catch {
            logger.warning("Failed to update local file modification date for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    
    @MainActor
    func updateCollaborationFile(_ file: CollaborationFile, with excalidrawFile: ExcalidrawFile) {
        guard !shouldIgnoreUpdate else { return }
        let activeFile = ActiveFile.collaborationFile(file)
        let newCheckpoint = shouldCreateUserCheckpoint(for: activeFile)
        let fileObjectID = file.objectID
        self.didUpdateFileState[activeFile] = true

        Task.detached {
            do {
                let context = PersistenceController.shared.newTaskContext()

                // Step 1: Update roomID
                try await context.perform {
                    guard let file = context.object(with: fileObjectID) as? CollaborationFile else {
                        throw AppError.fileError(.notFound)
                    }

                    // Update roomID
                    file.roomID = excalidrawFile.roomID

                    try context.save()
                }

                // Sync media items from ExcalidrawFile (creates new ones and saves to iCloud Drive)
                _ = try await PersistenceController.shared.mediaItemRepository.syncMediaItemsForCollaborationFile(
                    excalidrawFile: excalidrawFile,
                    collaborationFileObjectID: fileObjectID
                )
                
                // Step 2: Update content using repository (saves to iCloud Drive and creates checkpoint)
                guard let content = excalidrawFile.content else { return }
                try await PersistenceController.shared.collaborationFileRepository.updateElements(
                    collaborationFileObjectID: fileObjectID,
                    content: content,
                    newCheckpoint: newCheckpoint
                )
                
                await MainActor.run {
                    self.didUpdateFile = true
                    self.objectWillChange.send()
                }
            } catch {
                self.logger.error("Failed to update collaboration file: \(error)")
            }
        }
    }
    
    enum ImportGroupType: Hashable {
        case current
        case `default`
        case custom(Group.ID)
    }
    func importFile(_ url: URL, to targetGroupType: ImportGroupType = .current) async throws {
        let excalidrawFile = try ExcalidrawFile(contentsOf: url)
        let context = PersistenceController.shared.newTaskContext()
        let currentGroup: Group? = {
            if case .group(let currentGroup) = self.currentActiveGroup {
                return currentGroup
            }
            return nil
        }()
        let currentGroupID = currentGroup?.objectID
        
        let fileContentData = try excalidrawFile.contentWithoutFiles()
        
        // Get target group ID
        let targetGroupID = try await context.perform {
            var targetGroup: Group?
            
            if targetGroupType == .default || currentGroupID == nil {
                let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
                fetchRequest.fetchLimit = 1
                targetGroup = (try context.fetch(fetchRequest).first) as Group?
            } else if case .custom(let id) = targetGroupType, let id {
                let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                fetchRequest.fetchLimit = 1
                targetGroup = (try context.fetch(fetchRequest).first) as Group?
            }
            
            guard let group = targetGroup ?? {
                guard let currentGroupID else { return nil }
                return context.object(with: currentGroupID) as? Group
            }() else { throw AppError.stateError(.currentGroupNil) }
            
            return group.objectID
        }
        
        // Create file through repository (creates entity and saves to iCloud Drive)
        let fileID = try await PersistenceController.shared.fileRepository.createFile(
            name: excalidrawFile.name ?? "Untitled",
            content: fileContentData,
            groupObjectID: targetGroupID
        )
        
        // Get media items that need to be imported
        let mediaItemsNeedImport = try await context.perform {
            let mediaItems = try context.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
            return excalidrawFile.files.values.filter { item in
                !mediaItems.contains(where: { $0.id == item.id })
            }
        }
        
        // Create media items through repository (creates entities and saves to iCloud Drive)
        if !mediaItemsNeedImport.isEmpty {
            _ = try await PersistenceController.shared.mediaItemRepository.createMediaItems(
                resources: Array(mediaItemsNeedImport),
                fileObjectID: fileID
            )
        }
        
        try? await self.excalidrawWebCoordinator?.insertMediaFiles(Array(mediaItemsNeedImport))
        await requestActiveLibraryFileChange(fileObjectID: fileID)
    }
    
    /// Different handle logics according to different combinations of urls.
    /// * only files: Import to current group ?? default group..
    /// * 1 folder:
    ///     * if has subfolders: Create groups by folders & Group remains files to `Ungrouped`
    ///     * if only files: import all files to one group with the same name of the ancestor folder.
    /// * multiple folders: Create groups by folders
    /// * folders & files: Create groups by folders & Group remains files to `Ungrouped`
    func importFiles(_ urls: [URL]) async throws {
        let context = PersistenceController.shared.newTaskContext()
        
        let currentGroup: Group? = if case .group(let currentGroup) = self.currentActiveGroup {
            currentGroup
        } else {
            nil
        }
        let crrentGroupID = currentGroup?.objectID
        
        if urls.count == 1, let url = urls.first {
            guard url.startAccessingSecurityScopedResource() else {
                throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
            }
            defer { url.stopAccessingSecurityScopedResource() }
            if FileManager.default.isDirectory(url) {
                // select a directory
                try await self.importGroup(
                    url: url,
                    parentGroupID: crrentGroupID,
                    context: context
                )
            } else {
                // select only one excalidraw file
                try await self.importFile(url)
            }
        } else if urls.count > 1 {
            // select multiple files or folders
            // folders will be created as group, files will be imported to `default` group.
            // Prepare file data outside context.perform
            var fileDataPairs: [(URL, Data)] = []
            for fileURL in urls.filter({!FileManager.default.isDirectory($0)}) {
                guard fileURL.startAccessingSecurityScopedResource() else {
                    throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
                }
                let data = try Data(contentsOf: fileURL, options: .uncached)
                fileURL.stopAccessingSecurityScopedResource()
                fileDataPairs.append((fileURL, data))
            }
            
            // Get target group ID
            let targetGroupID = try await context.perform {
                let fetchRequest = NSFetchRequest<Group>()
                fetchRequest.predicate = NSPredicate(format: "type == %@", "default")
                var group: Group?
                let currentGroup: Group? = if let crrentGroupID {
                    context.object(with: crrentGroupID) as? Group
                } else {
                    nil
                }
                if let currentGroup {
                    group = currentGroup
                } else if let defaultGroup = try context.fetch(fetchRequest).first {
                    group = defaultGroup
                }
                guard let group else { throw AppError.stateError(.currentGroupNil) }
                
                return group.objectID
            }
            
            // Create files through repository (creates entities and saves to iCloud Drive)
            for (fileURL, data) in fileDataPairs {
                _ = try await PersistenceController.shared.fileRepository.createFile(
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    content: data,
                    groupObjectID: targetGroupID
                )
            }
            
            
            // folders
            for folderURL in urls.filter({FileManager.default.isDirectory($0)}) {
                guard folderURL.startAccessingSecurityScopedResource() else {
                    throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
                }
                defer { folderURL.stopAccessingSecurityScopedResource() }
                try await self.importGroup(
                    url: folderURL,
                    parentGroupID: currentGroup?.objectID,
                    context: context
                )
            }
            
        }
    }
    
    /// Import a folder as a group.
    private func importGroup(
        url: URL,
        parentGroupID: NSManagedObjectID?,
        context: NSManagedObjectContext
    ) async throws {
        let groupName = url.lastPathComponent
        
        // create group
        let group = try await context.perform {
            let group: Group = Group(name: groupName, context: context)
            context.insert(group)
            let parentGroup: Group? = if let parentGroupID {
                context.object(with: parentGroupID) as? Group
            } else {
                nil
            }
            group.parent = parentGroup
            try context.save()
            return group
        }
        let groupID = group.objectID
        
        // contents
        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: []
        )
        
        // Import medias
        let allMediaItems = try await context.perform {
            try context.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
        }
        var insertedMediaID = Set<String>()
        
        // files
        for fileURL in urls where fileURL.pathExtension == UTType.excalidrawFile.preferredFilenameExtension  {
            let excalidrawFile = try ExcalidrawFile(contentsOf: fileURL)
            let data = try Data(contentsOf: fileURL, options: .uncached)
            
            // Create file through repository (creates entity and saves to iCloud Drive)
            let fileID = try await PersistenceController.shared.fileRepository.createFile(
                name: fileURL.deletingPathExtension().lastPathComponent,
                content: data,
                groupObjectID: groupID
            )
            
            // Import medias
            let mediasToImport = excalidrawFile.files.values.filter { item in
                !insertedMediaID.contains(item.id) &&
                !allMediaItems.contains(where: {$0.id == item.id})
            }
            
            if !mediasToImport.isEmpty {
                // Create media items through repository (creates entities and saves to iCloud Drive)
                _ = try await PersistenceController.shared.mediaItemRepository.createMediaItems(
                    resources: Array(mediasToImport),
                    fileObjectID: fileID
                )
                
                // Mark as inserted to avoid duplicates in next iterations
                mediasToImport.forEach { insertedMediaID.insert($0.id) }
                
                Task {
                    try? await self.excalidrawWebCoordinator?.insertMediaFiles(Array(mediasToImport))
                }
            }
        }
        
        // folders
        for folderURL in urls where FileManager.default.isDirectory(folderURL) {
            try await self.importGroup(
                url: folderURL,
                parentGroupID: group.objectID,
                context: context
            )
        }

        try await context.perform {
            try context.save()
        }
    }
    
    func renameFile(_ fileID: NSManagedObjectID, context: NSManagedObjectContext, newName: String) {
        context.perform {
            guard let file = context.object(with: fileID) as? File else { return }
            file.name = newName
            try? context.save()
            if let id = file.id {
                Task {
                    await PersistenceController.shared.spotlightIndexingService.indexFile(id: id)
                }
            }
            self.objectWillChange.send()
        }
    }
    
    func renameGroup(_ group: Group, newName: String) {
        group.name = newName
        PersistenceController.shared.save()
        Task {
            await PersistenceController.shared.spotlightIndexingService.scheduleRebuild()
        }
        self.objectWillChange.send()
    }
    
    @discardableResult
    func duplicateFile(_ file: File, context: NSManagedObjectContext) async throws -> NSManagedObjectID {
        let fileID = file.objectID
        let fileName = file.name
        let groupID = file.group?.objectID
        
        // Load file content from iCloud Drive
        let content = try await file.loadContent()
        
        // Get file's group ID
        guard let groupID else {
            throw AppError.stateError(.currentGroupNil)
        }
        
        // Create duplicated file through repository (creates entity and saves to iCloud Drive)
        let newFileID = try await PersistenceController.shared.fileRepository.createFile(
            name: fileName ?? String(localizable: .generalUntitled),
            content: content,
            groupObjectID: groupID
        )
        
        // Copy media items if any
        let mediaItemsToCopy: [MediaItem] = await context.perform {
            guard let file = context.object(with: fileID) as? File else { return [] }
            let medias = file.medias?.allObjects as? [MediaItem] ?? []
            return medias
        }
        
        if !mediaItemsToCopy.isEmpty {
            // Load media resources
            var resources: [ExcalidrawFile.ResourceFile] = []
            for mediaItem in mediaItemsToCopy {
                if let resource = try? await ExcalidrawFile.ResourceFile(mediaItem: mediaItem) {
                    resources.append(resource)
                }
            }
            
            // Create media items for the new file
            if !resources.isEmpty {
                _ = try await PersistenceController.shared.mediaItemRepository.createMediaItems(
                    resources: resources,
                    fileObjectID: newFileID
                )
            }
        }
        
        return newFileID
    }
    
    func recoverFile(fileID: NSManagedObjectID, context: NSManagedObjectContext) async throws {
        let file: File? = try await context.perform {
            guard let file = context.object(with: fileID) as? File else { return nil }
            guard file.inTrash else { return nil }
            file.inTrash = false
            
            if let groupID = file.group?.objectID {
                let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                fetchRequest.predicate = NSPredicate(format: "id == %@", groupID as CVarArg)
                fetchRequest.fetchLimit = 1
                if try context.fetch(fetchRequest).isEmpty {
                    let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: context)
                    file.group = defaultGroup
                }
            } else {
                let defaultGroup = try PersistenceController.shared.getDefaultGroup(context: context)
                file.group = defaultGroup
            }
            
            try context.save()
            
            return file
        }
        
        if let file {
            if let id = file.id {
                await PersistenceController.shared.spotlightIndexingService.indexFile(id: id)
            }

            let fileID = file.objectID
            
            await MainActor.run {
                guard let file = context.object(with: fileID) as? File else { return }
                if self.currentActiveFile == .file(file) {
                    if let group = file.group {
                        self.currentActiveGroup = .group(group)
                        self.expandToGroup(group.objectID)
                    }
                }
            }
        }
    }
    
    func mergeDefaultGroupAndTrashIfNeeded(context: NSManagedObjectContext) async throws {
        let didMoveFiles = try await context.perform {
            var groups = try context.fetch(NSFetchRequest<Group>(entityName: "Group"))
            var didChange = false

            if groups.first(where: { $0.groupType == .default }) == nil {
                let group = Group(context: context)
                group.id = UUID()
                group.groupType = .default
                group.name = "default"
                group.createdAt = .now
                groups.append(group)
                didChange = true
            }

            if groups.first(where: { $0.groupType == .trash }) == nil {
                let group = Group(context: context)
                group.id = UUID()
                group.groupType = .trash
                group.name = "Recently Deleted"
                group.createdAt = .now
                groups.append(group)
                didChange = true
            }
            
            let defaultGroups = groups.filter({$0.groupType == .default})
            var theEearlisetGroup: Group?
            var didMoveFiles = false
            // Merge default groups
            if defaultGroups.count > 1 {
                theEearlisetGroup = defaultGroups.sorted(by: {
                    ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
                }).first!
                
                try defaultGroups.forEach { group in
                    if group != theEearlisetGroup {
                        let defaultGroupFilesfetchRequest = NSFetchRequest<File>(entityName: "File")
                        defaultGroupFilesfetchRequest.predicate = NSPredicate(format: "group == %@", group)
                        let defaultGroupFiles = try context.fetch(defaultGroupFilesfetchRequest)
                        defaultGroupFiles.forEach { file in
                            file.group = theEearlisetGroup
                            didMoveFiles = true
                            didChange = true
                        }
                        context.delete(group)
                        didChange = true
                    }
                }
            }
            
            let trashGroups = groups.filter({$0.groupType == .trash})
            if let defaultGroup = theEearlisetGroup ?? defaultGroups.sorted(by: {
                ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
            }).first, !trashGroups.isEmpty {
                let trashedGroupFilesFetchRequest = NSFetchRequest<File>(entityName: "File")
                trashedGroupFilesFetchRequest.predicate = NSPredicate(format: "group IN %@", trashGroups)
                let trashedGroupFiles = try context.fetch(trashedGroupFilesFetchRequest)
                trashedGroupFiles.forEach { file in
                    file.group = defaultGroup
                    file.inTrash = true
                    if file.deletedAt == nil {
                        file.deletedAt = .now
                    }
                    didChange = true
                }
            }

            let primaryTrashGroup = trashGroups.sorted {
                ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
            }.first

            if let primaryTrashGroup, primaryTrashGroup.parent != nil {
                primaryTrashGroup.parent = nil
                didChange = true
            }

            trashGroups
                .filter { $0 != primaryTrashGroup }
                .forEach { trash in
                    context.delete(trash)
                    didChange = true
                }

            if didChange {
                try context.save()
            }
            return didMoveFiles
        }

        if didMoveFiles {
            await PersistenceController.shared.spotlightIndexingService.scheduleRebuild()
        }
    }
    
    public func expandToGroup(_ groupID: NSManagedObjectID, expandSelf: Bool = true) {
        let context = PersistenceController.shared.newTaskContext()
        Task.detached {
            await context.perform {
                guard case let targetGroup as any ExcalidrawGroup = context.object(with: groupID) else { return }
                
                var groupIDs: [NSManagedObjectID] = []
                // get groupIDs
                do {
                    var targetGroupID: NSManagedObjectID? = groupID
                    var parentGroup: (any ExcalidrawGroup)? = targetGroup
                    while true {
                        guard let parentGroupID = (parentGroup?.getParent() as? (any ExcalidrawGroup))?.objectID else {
                            break
                        }
                        parentGroup = context.object(with: parentGroupID) as? (any ExcalidrawGroup)
                        targetGroupID = parentGroup?.objectID
                        if let targetGroupID {
                            groupIDs.insert(targetGroupID, at: 0)
                        }
                    }
                }
                Task { [groupIDs, expandSelf] in
                    for groupId in groupIDs {
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .shouldExpandGroup,
                                object: groupId
                            )
                        }
                        try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.2))
                    }
                    if expandSelf {
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .shouldExpandGroup,
                                object: groupID
                            )
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    public func setToDefaultGroup() async throws {
        let viewContext = PersistenceController.shared.container.viewContext
        let (_, group): (File?, Group?) = try await viewContext.perform {
            let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
            fetchRequest.predicate = NSPredicate(format: "type = %@", "default")
            if let defaultGroup = try viewContext.fetch(fetchRequest).first {
                let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
                fileFetchRequest.predicate = NSPredicate(format: "group = %@ AND inTrash = false", defaultGroup)
                fileFetchRequest.sortDescriptors = [
                    NSSortDescriptor(keyPath: \File.updatedAt, ascending: false)
                ]
                return (try viewContext.fetch(fileFetchRequest).first, defaultGroup)
            }
            
            return (nil, nil)
        }
        
        if let group {
            self.currentActiveGroup = .group(group)
            self.expandToGroup(group.objectID)
            //            if let file {
            //                self.setActiveFile(.file(file))
            //            }
        }
    }
    
    /// Restores the previous group/space while an AI round is active.
    /// File switching is already blocked in `setActiveFile`; this catches
    /// direct space changes such as Home, Collaboration, temporary, and
    /// local-folder navigation.
    private func shouldRestoreActiveGroupAfterBlockedSwitch(from oldValue: ActiveGroup?) -> Bool {
        guard !isRestoringActiveGroupAfterBlockedSwitch else { return false }
        guard aiChatSession != nil else { return false }
        guard oldValue != currentActiveGroup else { return false }

        activeFileSwitchBlockedReason = .aiGenerationInProgress
        activeFileSwitchBlockedToken += 1
        isRestoringActiveGroupAfterBlockedSwitch = true
        currentActiveGroup = oldValue
        isRestoringActiveGroupAfterBlockedSwitch = false
        return true
    }

    private func resetCurrentGroupChangesListener() {
        currentGroupPublisherCancellables.forEach {$0.cancel()}
        currentGroupPublisherCancellables = []
        if case .group(let group) = currentActiveGroup {
            currentGroupPublisherCancellables = [
                group.publisher(for: \.name).sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                    }
                }
            ]
        }
        DispatchQueue.main.async {
            self.resetSelections()
        }
    }

    /// Reset the current file changes listener.
    /// Everytime the current file changes, the listeners will send a `objectWillChange` event.
    private func resetCurrentFileChangesListener() {
        currentFilePublisherCancellables.forEach{$0.cancel()}
        
        if case .file(let currentFile) = self.currentActiveFile {
            currentFilePublisherCancellables = [
                currentFile.publisher(for: \.name).sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                    }
                },
                currentFile.publisher(for: \.updatedAt).sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                    }
                },
                currentFile.publisher(for: \.inTrash).sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                    }
                }
            ]
        }
    }
    
    /// Reset all selections to empty.
    public func resetSelections() {
        self.selectedFiles = []
        self.selectedStartFile = nil
        self.selectedLocalFiles = []
        self.selectedStartLocalFile = nil
        self.selectedTemporaryFiles = []
        self.selectedStartTemporaryFile = nil
        self.selectedCloudStorageFiles = []
        self.selectedStartCloudStorageFile = nil
    }
}
