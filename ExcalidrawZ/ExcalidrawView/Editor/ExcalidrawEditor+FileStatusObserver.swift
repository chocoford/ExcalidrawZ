//
//  ExcalidrawEditor+FileStatusObserver.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/27/25.
//

import SwiftUI
import ChocofordUI
import CoreData
import Logging

private struct FileStatusObserverModifier: ViewModifier {
    private let logger = Logger(label: "FileStatusObserverModifier")

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var fileState: FileState
    
    var activeFile: FileState.ActiveFile?
    var activeFileLockState: FileContentLockState
    @Binding private var conflictFileURL: URL?
    var onSyncing: (Data, _ onDone: @escaping () -> Void) -> Void
    var onResolveConflict: (URL) -> Void
    
    init(
        activeFile: FileState.ActiveFile?,
        activeFileLockState: FileContentLockState,
        conflictFileURL: Binding<URL?>,
        onSyncing: @escaping (Data, _ onDone: @escaping () -> Void) -> Void,
        onResolveConflict: @escaping (URL) -> Void
    ) {
        self.activeFile = activeFile
        self.activeFileLockState = activeFileLockState
        self._conflictFileURL = conflictFileURL
        self.onSyncing = onSyncing
        self.onResolveConflict = onResolveConflict
    }
    
    @State private var isSyncing = false
    @State private var fileStorageICloudMonitor = FileStorageICloudStatusMonitor()
    @State private var pendingCloudPullFileIDs: Set<String> = []
    @State private var pullingCloudFileIDs: Set<String> = []
    @State private var checkingCloudFreshnessFileIDs: Set<String> = []
    @State private var requestedCloudDownloadFileIDs: Set<String> = []
    @State private var lastHandledICloudStatuses: [String: ICloudFileStatus] = [:]
    @State private var remoteMetadataProbeTask: Task<Void, Never>?
    @State private var activeFileFallbackProbeTask: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        content
            .observeFileStatus(for: activeFile) { status in
                handleFileStatusChange(status)
            }
            .sheet(isPresented: Binding {
                conflictFileURL != nil
            } set: {
                if !$0 {
                    conflictFileURL = nil
                }
            }) {
                if let conflictURL = conflictFileURL {
                    ConflictResolutionSheetView(
                        fileURL: conflictURL
                    ) {
                        onResolveConflict(conflictURL)
                    } onCancelled: {
                        fileState.setActiveFile(nil)
                    }
                }
            }
            .task {
                startFileStorageICloudMonitorIfNeeded()
                startActiveFileFallbackProbeIfNeeded()
            }
            .watch(value: activeFile) { _ in
                Task { @MainActor in
                    resetActiveStorageSyncState()
                    startFileStorageICloudMonitorIfNeeded()
                    startActiveFileFallbackProbeIfNeeded()
                }
            }
            .watch(value: activeFileLockState) { lockState in
                if lockState == .plaintext {
                    Task { @MainActor in
                        startFileStorageICloudMonitorIfNeeded()
                        startActiveFileFallbackProbeIfNeeded()
                    }
                } else {
                    isSyncing = false
                    resetActiveStorageSyncState()
                    Task { @MainActor in
                        fileStorageICloudMonitor.stop()
                    }
                }
            }
            .watch(value: scenePhase) { phase in
                Task { @MainActor in
                    if phase == .active {
                        startFileStorageICloudMonitorIfNeeded()
                        startActiveFileFallbackProbeIfNeeded()
                    } else {
                        stopActiveFileFallbackProbe()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .coreDataRemoteMetadataDidChange)) { _ in
                Task { @MainActor in
                    handleFileStorageRemoteMetadataDidChange()
                }
            }
            .onDisappear {
                resetActiveStorageSyncState()
                Task { @MainActor in
                    fileStorageICloudMonitor.stop()
                }
            }
    }
    
    /// Handle file status changes for currently active file
    private func handleFileStatusChange(_ status: FileStatus) {
        guard let file = activeFile else { return }
        guard activeFileLockState == .plaintext else { return }

        handleObservedICloudStatus(status.iCloudStatus, for: file)
    }

    @MainActor
    private func handleObservedICloudStatus(
        _ iCloudStatus: ICloudFileStatus,
        for file: FileState.ActiveFile
    ) {
        guard let fileID = syncStatusFileID(for: file) else { return }
        guard lastHandledICloudStatuses[fileID] != iCloudStatus else {
            return
        }

        lastHandledICloudStatuses[fileID] = iCloudStatus
        handleICloudStatus(iCloudStatus, for: file)
    }
    
    /// Unified iCloud status handling for all file types
    private func handleICloudStatus(_ iCloudStatus: ICloudFileStatus, for file: FileState.ActiveFile) {
        // Handle conflict state - show resolution sheet immediately
        if iCloudStatus == .conflict {
            if case .localFile(let url) = file {
                conflictFileURL = url
            }
            // CoreData File conflicts are handled differently (not implemented yet)
            return
        }

        if case .localFile(let url) = file {
            handleLinkedFileICloudStatus(iCloudStatus, url: url)
            return
        }
        
        guard let reference = storageFileReference(for: file) else { return }
        let syncStatusFileID = reference.fileID

        guard !pullingCloudFileIDs.contains(syncStatusFileID) else {
            return
        }

        switch iCloudStatus {
            case .downloading:
                pendingCloudPullFileIDs.insert(syncStatusFileID)
                FileStatusService.shared.markSyncInProgress(
                    fileID: syncStatusFileID,
                    operation: .download
                )
                return

            case .notDownloaded:
                pendingCloudPullFileIDs.insert(syncStatusFileID)
                pullingCloudFileIDs.remove(syncStatusFileID)
                if requestedCloudDownloadFileIDs.contains(syncStatusFileID) {
                    FileStatusService.shared.markSyncInProgress(
                        fileID: syncStatusFileID,
                        operation: .download
                    )
                    return
                }

                FileStatusService.shared.markSyncQueued(
                    fileID: syncStatusFileID,
                    operation: .download
                )
                requestCloudDownloadIfNeeded(
                    syncStatusFileID: syncStatusFileID,
                    file: file
                )
                return

            case .downloaded:
                requestedCloudDownloadFileIDs.remove(syncStatusFileID)
                guard pendingCloudPullFileIDs.remove(syncStatusFileID) != nil else {
                    checkDownloadedFileForRemoteContentUpdate(
                        syncStatusFileID: syncStatusFileID,
                        file: file,
                        reason: .downloadedStatus
                    )
                    return
                }

            case .outdated:
                requestedCloudDownloadFileIDs.remove(syncStatusFileID)
                pendingCloudPullFileIDs.insert(syncStatusFileID)

            default:
                pendingCloudPullFileIDs.remove(syncStatusFileID)
                pullingCloudFileIDs.remove(syncStatusFileID)
                requestedCloudDownloadFileIDs.remove(syncStatusFileID)
                return
        }

        guard !pullingCloudFileIDs.contains(syncStatusFileID) else { return }

        pullingCloudFileIDs.insert(syncStatusFileID)
        isSyncing = true
        FileStatusService.shared.markSyncInProgress(
            fileID: syncStatusFileID,
            operation: .download
        )

        Task { @MainActor in
            defer {
                isSyncing = false
                pullingCloudFileIDs.remove(syncStatusFileID)
            }

            do {
                _ = try await pullLatestContent(for: file)
                let hasPendingRemoteFileUpdate = await hasPendingRemoteFileContentUpdate(
                    for: file,
                    syncStatusFileID: syncStatusFileID
                )
                if hasPendingRemoteFileUpdate {
                    logger.debug("Active file iCloud Drive content is still newer after pull; keeping refresh pending: \(syncStatusFileID)")
                    pendingCloudPullFileIDs.insert(syncStatusFileID)
                    FileStatusService.shared.markSyncQueued(
                        fileID: syncStatusFileID,
                        operation: .download
                    )
                    schedulePendingCloudStatusProbe(
                        syncStatusFileID: syncStatusFileID,
                        file: file
                    )
                } else {
                    completeCloudPull(fileID: syncStatusFileID)
                }
            } catch {
                if isRecoverableICloudDriveDelay(error) {
                    logger.debug("Active file iCloud Drive content is not ready yet: \(error.localizedDescription)")
                    pendingCloudPullFileIDs.insert(syncStatusFileID)
                    FileStatusService.shared.markSyncQueued(
                        fileID: syncStatusFileID,
                        operation: .download
                    )
                    schedulePendingCloudStatusProbe(
                        syncStatusFileID: syncStatusFileID,
                        file: file
                    )
                } else {
                    logger.error("Failed to pull active file content from iCloud Drive: \(error.localizedDescription)")
                    clearCloudPullTracking(fileID: syncStatusFileID)
                    FileStatusService.shared.markSyncFailed(
                        fileID: syncStatusFileID,
                        error: error.localizedDescription
                    )
                }
            }
        }
    }

    private func hasPendingRemoteFileContentUpdate(
        for file: FileState.ActiveFile,
        syncStatusFileID: String
    ) async -> Bool {
        guard let reference = storageFileReference(for: file),
              reference.fileID == syncStatusFileID else {
            return false
        }

        do {
            return try await FileStorageManager.shared.checkForICloudUpdate(
                relativePath: reference.relativePath,
                fileID: reference.fileID
            )
        } catch {
            logger.debug("Failed to compare active file iCloud Drive freshness: \(error.localizedDescription)")
            return true
        }
    }

    private func handleLinkedFileICloudStatus(_ iCloudStatus: ICloudFileStatus, url: URL) {
        let shouldPull: Bool
        if case .downloading = iCloudStatus {
            shouldPull = true
        } else if iCloudStatus == .outdated {
            shouldPull = true
        } else {
            shouldPull = false
        }

        guard shouldPull, !isSyncing else { return }

        let fileID = url.absoluteString
        isSyncing = true
        FileStatusService.shared.markSyncInProgress(
            fileID: fileID,
            operation: .download
        )

        Task { @MainActor in
            defer {
                isSyncing = false
            }

            do {
                let latestData = try await FileSyncCoordinator.shared.openFile(url)
                onSyncing(latestData) {}
                FileStatusService.shared.markSyncCompleted(fileID: fileID)
            } catch {
                logger.error("Failed to pull linked iCloud file content: \(error.localizedDescription)")
                FileStatusService.shared.markSyncFailed(
                    fileID: fileID,
                    error: error.localizedDescription
                )
            }
        }
    }

    @MainActor
    private func handleFileStorageRemoteMetadataDidChange() {
        guard activeFileLockState == .plaintext,
              let activeFile,
              let reference = storageFileReference(for: activeFile) else {
            return
        }

        startFileStorageICloudMonitorIfNeeded()
        logActiveFileMetadataSnapshot(
            reason: .coreDataRemoteMetadata,
            file: activeFile,
            reference: reference
        )
        scheduleRemoteMetadataProbe(
            syncStatusFileID: reference.fileID,
            file: activeFile
        )
    }

    @MainActor
    private func logActiveFileMetadataSnapshot(
        reason: ActiveFileCloudRefreshReason,
        file: FileState.ActiveFile,
        reference: ActiveStorageFileReference
    ) {
        let viewContextUpdatedAt = storageMetadataUpdatedAtInViewContext(for: file)
        guard let objectReference = storageMetadataObjectReference(for: file) else {
            logger.debug("Active file metadata snapshot reason=\(reason.rawValue) id=\(reference.fileID) viewContextUpdatedAt=\(dateDescription(viewContextUpdatedAt)) freshStoreUpdatedAt=nil")
            return
        }

        Task {
            let freshStoreUpdatedAt = await freshStorageMetadataUpdatedAt(for: objectReference)
            await MainActor.run {
                logger.debug("Active file metadata snapshot reason=\(reason.rawValue) id=\(reference.fileID) viewContextUpdatedAt=\(dateDescription(viewContextUpdatedAt)) freshStoreUpdatedAt=\(dateDescription(freshStoreUpdatedAt))")
            }
        }
    }

    private func storageMetadataUpdatedAtInViewContext(for file: FileState.ActiveFile) -> Date? {
        switch file {
            case .file(let dbFile):
                return dbFile.updatedAt
            case .collaborationFile(let collabFile):
                return collabFile.updatedAt
            case .localFile, .temporaryFile, .cloudStorageFile:
                return nil
        }
    }

    private func storageMetadataObjectReference(
        for file: FileState.ActiveFile
    ) -> ActiveStorageMetadataObjectReference? {
        switch file {
            case .file(let dbFile):
                return .file(dbFile.objectID)
            case .collaborationFile(let collabFile):
                return .collaborationFile(collabFile.objectID)
            case .localFile, .temporaryFile, .cloudStorageFile:
                return nil
        }
    }

    private func freshStorageMetadataUpdatedAt(
        for reference: ActiveStorageMetadataObjectReference
    ) async -> Date? {
        let context = PersistenceController.shared.newTaskContext()
        return await context.perform {
            do {
                switch reference {
                    case .file(let objectID):
                        return (try context.existingObject(with: objectID) as? File)?.updatedAt
                    case .collaborationFile(let objectID):
                        return (try context.existingObject(with: objectID) as? CollaborationFile)?.updatedAt
                }
            } catch {
                return nil
            }
        }
    }

    private func dateDescription(_ date: Date?) -> String {
        date?.ISO8601Format() ?? "nil"
    }

    @MainActor
    private func resetActiveStorageSyncState() {
        let trackedFileIDs = pendingCloudPullFileIDs
            .union(pullingCloudFileIDs)
            .union(checkingCloudFreshnessFileIDs)
            .union(requestedCloudDownloadFileIDs)

        pendingCloudPullFileIDs.removeAll()
        pullingCloudFileIDs.removeAll()
        checkingCloudFreshnessFileIDs.removeAll()
        requestedCloudDownloadFileIDs.removeAll()
        lastHandledICloudStatuses.removeAll()
        remoteMetadataProbeTask?.cancel()
        remoteMetadataProbeTask = nil
        stopActiveFileFallbackProbe()

        for fileID in trackedFileIDs
        where FileStatusService.shared.getSyncStatus(for: fileID).isActiveCloudPullStatus {
            FileStatusService.shared.markSyncCompleted(fileID: fileID)
        }
    }

    @MainActor
    private func startActiveFileFallbackProbeIfNeeded() {
        guard scenePhase == .active,
              activeFileLockState == .plaintext,
              let activeFile,
              let reference = storageFileReference(for: activeFile) else {
            stopActiveFileFallbackProbe()
            return
        }

        guard activeFileFallbackProbeTask == nil else { return }

        activeFileFallbackProbeTask = Task { @MainActor in
            defer {
                activeFileFallbackProbeTask = nil
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)

                guard !Task.isCancelled,
                      scenePhase == .active,
                      activeFileLockState == .plaintext,
                      self.activeFile?.id == reference.fileID else {
                    return
                }

                guard !pullingCloudFileIDs.contains(reference.fileID) else {
                    continue
                }

                await refreshDownloadedFileForRemoteContentUpdate(
                    syncStatusFileID: reference.fileID,
                    file: activeFile,
                    reason: .periodicActiveFileFallback,
                    completesWhenCurrent: false
                )
            }
        }
    }

    @MainActor
    private func stopActiveFileFallbackProbe() {
        activeFileFallbackProbeTask?.cancel()
        activeFileFallbackProbeTask = nil
    }

    @MainActor
    private func clearCloudPullTracking(fileID: String) {
        pendingCloudPullFileIDs.remove(fileID)
        pullingCloudFileIDs.remove(fileID)
        checkingCloudFreshnessFileIDs.remove(fileID)
        requestedCloudDownloadFileIDs.remove(fileID)
        lastHandledICloudStatuses.removeValue(forKey: fileID)

        guard activeFile?.id == fileID else { return }
        remoteMetadataProbeTask?.cancel()
        remoteMetadataProbeTask = nil
    }

    @MainActor
    private func completeCloudPull(fileID: String) {
        clearCloudPullTracking(fileID: fileID)
        FileStatusService.shared.markSyncCompleted(fileID: fileID)
    }

    private func requestCloudDownloadIfNeeded(
        syncStatusFileID: String,
        file: FileState.ActiveFile
    ) {
        guard let reference = storageFileReference(for: file),
              reference.fileID == syncStatusFileID else {
            return
        }
        guard !requestedCloudDownloadFileIDs.contains(syncStatusFileID) else { return }

        requestedCloudDownloadFileIDs.insert(syncStatusFileID)

        Task { @MainActor in
            do {
                let didRequest = try await FileStorageManager.shared.requestICloudDownload(
                    relativePath: reference.relativePath,
                    fileID: reference.fileID
                )
                if didRequest {
                    FileStatusService.shared.markSyncInProgress(
                        fileID: syncStatusFileID,
                        operation: .download
                    )
                    scheduleCloudStatusRefresh(
                        syncStatusFileID: syncStatusFileID,
                        delayNanoseconds: 3_000_000_000
                    )
                } else {
                    completeCloudPull(fileID: syncStatusFileID)
                }
            } catch {
                completeCloudPull(fileID: syncStatusFileID)
                logger.warning("Failed to request active iCloud Drive download: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleCloudStatusRefresh(
        syncStatusFileID: String,
        delayNanoseconds: UInt64
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            let shouldRefresh = requestedCloudDownloadFileIDs.contains(syncStatusFileID) ||
                pendingCloudPullFileIDs.contains(syncStatusFileID)
            guard activeFile?.id == syncStatusFileID, shouldRefresh else {
                return
            }
            startFileStorageICloudMonitorIfNeeded()
        }
    }

    @MainActor
    private func scheduleRemoteMetadataProbe(
        syncStatusFileID: String,
        file: FileState.ActiveFile
    ) {
        guard remoteMetadataProbeTask == nil else { return }

        remoteMetadataProbeTask = Task { @MainActor in
            defer {
                remoteMetadataProbeTask = nil
            }

            let probeDelays: [UInt64] = [
                0,
                2_000_000_000,
                5_000_000_000,
                10_000_000_000,
                20_000_000_000,
                40_000_000_000,
                80_000_000_000
            ]

            for delay in probeDelays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                guard !Task.isCancelled,
                      activeFile?.id == syncStatusFileID,
                      activeFileLockState == .plaintext else {
                    return
                }

                startFileStorageICloudMonitorIfNeeded()

                let didFindUpdate = await refreshDownloadedFileForRemoteContentUpdate(
                    syncStatusFileID: syncStatusFileID,
                    file: file,
                    reason: .coreDataRemoteMetadata,
                    completesWhenCurrent: false
                )
                if didFindUpdate {
                    return
                }
            }
        }
    }

    @MainActor
    private func schedulePendingCloudStatusProbe(
        syncStatusFileID: String,
        file: FileState.ActiveFile
    ) {
        remoteMetadataProbeTask?.cancel()
        remoteMetadataProbeTask = Task { @MainActor in
            defer {
                remoteMetadataProbeTask = nil
            }

            let retryDelays: [UInt64] = [
                2_000_000_000,
                8_000_000_000,
                16_000_000_000
            ]

            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled,
                      activeFile?.id == syncStatusFileID,
                      activeFileLockState == .plaintext,
                      pendingCloudPullFileIDs.contains(syncStatusFileID) else {
                    return
                }

                startFileStorageICloudMonitorIfNeeded()
                await refreshDownloadedFileForRemoteContentUpdate(
                    syncStatusFileID: syncStatusFileID,
                    file: file,
                    reason: .pendingCloudStatus
                )
            }
        }
    }

    private func checkDownloadedFileForRemoteContentUpdate(
        syncStatusFileID: String,
        file: FileState.ActiveFile,
        reason: ActiveFileCloudRefreshReason,
        completesWhenCurrent: Bool = true
    ) {
        guard let reference = storageFileReference(for: file),
              reference.fileID == syncStatusFileID else {
            return
        }

        Task { @MainActor in
            await refreshDownloadedFileForRemoteContentUpdate(
                syncStatusFileID: syncStatusFileID,
                file: file,
                reason: reason,
                completesWhenCurrent: completesWhenCurrent
            )
        }
    }

    @MainActor
    @discardableResult
    private func refreshDownloadedFileForRemoteContentUpdate(
        syncStatusFileID: String,
        file: FileState.ActiveFile,
        reason: ActiveFileCloudRefreshReason,
        completesWhenCurrent: Bool = true
    ) async -> Bool {
        guard let reference = storageFileReference(for: file),
              reference.fileID == syncStatusFileID else {
            logger.debug("Skipped active file iCloud Drive freshness check reason=\(reason.rawValue) id=\(syncStatusFileID): active file reference mismatch")
            return false
        }
        guard !checkingCloudFreshnessFileIDs.contains(syncStatusFileID) else {
            logger.debug("Skipped active file iCloud Drive freshness check reason=\(reason.rawValue) id=\(syncStatusFileID): already checking")
            return false
        }

        checkingCloudFreshnessFileIDs.insert(syncStatusFileID)
        defer {
            checkingCloudFreshnessFileIDs.remove(syncStatusFileID)
        }

        do {
            logger.debug("Checking active file iCloud Drive freshness reason=\(reason.rawValue) id=\(reference.fileID)")
            let hasUpdate = try await FileStorageManager.shared.checkForICloudUpdate(
                relativePath: reference.relativePath,
                fileID: reference.fileID
            )
            guard hasUpdate else {
                logger.debug("Active file iCloud Drive content is current reason=\(reason.rawValue) id=\(reference.fileID) completesWhenCurrent=\(completesWhenCurrent)")
                if completesWhenCurrent {
                    completeCloudPull(fileID: reference.fileID)
                }
                return false
            }

            logger.debug("Active file iCloud Drive content is newer; pulling cloud update reason=\(reason.rawValue) id=\(reference.fileID)")
            FileStatusService.shared.markSyncQueued(
                fileID: reference.fileID,
                operation: .download
            )
            FileStatusService.shared.updateICloudStatus(
                fileID: reference.fileID,
                status: .outdated
            )
            handleICloudStatus(.outdated, for: file)
            return true
        } catch {
            logger.debug("Failed to check active iCloud Drive file freshness reason=\(reason.rawValue): \(error.localizedDescription)")
            return false
        }
    }

    private func isRecoverableICloudDriveDelay(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        switch error {
            case iCloudDriveError.fileNotFound:
                return true
            default:
                let nsError = error as NSError
                return nsError.domain == NSCocoaErrorDomain &&
                    nsError.code == NSFileReadNoSuchFileError
        }
    }

    private func syncStatusFileID(for file: FileState.ActiveFile) -> String? {
        switch file {
            case .localFile(let url):
                return url.absoluteString

            case .file(let dbFile):
                return dbFile.id?.uuidString

            case .collaborationFile(let collabFile):
                return collabFile.id?.uuidString

            case .temporaryFile:
                return nil
            case .cloudStorageFile:
                return nil
        }
    }

    @MainActor
    private func pullLatestContent(for file: FileState.ActiveFile) async throws -> Bool {
        switch file {
            case .localFile(let url):
                // LocalFile: use FileSyncCoordinator
                let latestData = try await FileSyncCoordinator.shared.openFile(url)
                onSyncing(latestData) {}
                await markCloudPullCompleted(fileID: url.absoluteString)
                return true

            case .file(let dbFile):
                guard let fileID = dbFile.id else { return false }

                // CoreData File: use FileStorageManager
                let relativePath = FileStorageContentType.file.generateRelativePath(
                    fileID: fileID.uuidString
                )
                let latestData = try await FileStorageManager.shared.loadLatestContent(
                    relativePath: relativePath,
                    fileID: fileID.uuidString
                )
                onSyncing(latestData) {}
                await markCloudPullCompleted(fileID: fileID.uuidString)
                return true

            case .collaborationFile(let collabFile):
                guard let fileID = collabFile.id else { return false }

                // CollaborationFile: use FileStorageManager
                let relativePath = FileStorageContentType.collaborationFile.generateRelativePath(
                    fileID: fileID.uuidString
                )
                let latestData = try await FileStorageManager.shared.loadLatestContent(
                    relativePath: relativePath,
                    fileID: fileID.uuidString
                )
                onSyncing(latestData) {}
                await markCloudPullCompleted(fileID: fileID.uuidString)
                return true

            case .temporaryFile:
                return false
            case .cloudStorageFile:
                return false
        }
    }

    private struct ActiveStorageFileReference: Equatable {
        let fileID: String
        let relativePath: String
    }

    private var activeStorageFileReference: ActiveStorageFileReference? {
        guard let activeFile else { return nil }
        return storageFileReference(for: activeFile)
    }

    private func storageFileReference(for file: FileState.ActiveFile) -> ActiveStorageFileReference? {
        switch file {
            case .file(let dbFile):
                guard let fileID = dbFile.id?.uuidString else { return nil }
                return ActiveStorageFileReference(
                    fileID: fileID,
                    relativePath: FileStorageContentType.file.generateRelativePath(fileID: fileID)
                )

            case .collaborationFile(let collabFile):
                guard let fileID = collabFile.id?.uuidString else { return nil }
                return ActiveStorageFileReference(
                    fileID: fileID,
                    relativePath: FileStorageContentType.collaborationFile.generateRelativePath(fileID: fileID)
                )

            case .localFile, .temporaryFile, .cloudStorageFile:
                return nil
        }
    }

    @MainActor
    private func startFileStorageICloudMonitorIfNeeded() {
        guard activeFileLockState == .plaintext,
              let reference = activeStorageFileReference else {
            fileStorageICloudMonitor.stop()
            return
        }

        fileStorageICloudMonitor.start(
            fileID: reference.fileID,
            relativePath: reference.relativePath
        ) { fileID, status in
            FileStatusService.shared.updateICloudStatus(
                fileID: fileID,
                status: status
            )
            guard fileID == reference.fileID,
                  let activeFile,
                  syncStatusFileID(for: activeFile) == fileID else {
                return
            }

            if status == .downloaded {
                checkDownloadedFileForRemoteContentUpdate(
                    syncStatusFileID: fileID,
                    file: activeFile,
                    reason: .iCloudDownloadedStatus,
                    completesWhenCurrent: pendingCloudPullFileIDs.contains(fileID) ||
                        requestedCloudDownloadFileIDs.contains(fileID)
                )
                return
            }

            handleObservedICloudStatus(status, for: activeFile)
        }
    }

    private func markCloudPullCompleted(fileID: String) async {
        await MainActor.run {
            FileStatusService.shared.updateICloudStatus(
                fileID: fileID,
                status: .downloaded
            )
        }
    }
}

private enum ActiveFileCloudRefreshReason: String {
    case coreDataRemoteMetadata
    case downloadedStatus
    case iCloudDownloadedStatus
    case pendingCloudStatus
    case periodicActiveFileFallback
}

private enum ActiveStorageMetadataObjectReference {
    case file(NSManagedObjectID)
    case collaborationFile(NSManagedObjectID)
}

private extension FileSyncStatus {
    var isActiveCloudPullStatus: Bool {
        switch self {
            case .queued(.download), .downloading(_):
                return true
            default:
                return false
        }
    }
}

extension View {
    @ViewBuilder
    func observeExcalidrawFileStatus(
        for file: FileState.ActiveFile?,
        activeFileLockState: FileContentLockState,
        conflictFileURL: Binding<URL?>,
        onSyncing: @escaping (Data, _ onDone: @escaping () -> Void) -> Void,
        onResolveConflict: @escaping (URL) -> Void
    ) -> some View {
        modifier(
            FileStatusObserverModifier(
                activeFile: file,
                activeFileLockState: activeFileLockState,
                conflictFileURL: conflictFileURL,
                onSyncing: onSyncing,
                onResolveConflict: onResolveConflict
            )
        )
    }
}
