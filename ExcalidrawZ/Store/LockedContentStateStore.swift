//
//  LockedContentStateStore.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/27.
//

import Combine
import CoreData
import Foundation

struct LockedContentAutomaticUnlockRequest: Equatable, Sendable {
    let fileID: String
    let token: UUID
}

@MainActor
final class LockedContentStateStore: ObservableObject {
    @Published private(set) var activeFileLockState: FileContentLockState = .plaintext
    @Published private(set) var automaticUnlockRequest: LockedContentAutomaticUnlockRequest?
    @Published private(set) var filePreviewLockStateRevision = 0
    @Published private var fileLockStates: [String: FileContentLockState] = [:]

    private struct ManagedFileReference {
        let objectID: NSManagedObjectID
        let fileID: String
    }

    private var activeFileID: String?
    private var activeManagedFile: ManagedFileReference?
    private var suppressedAutomaticUnlockFileID: String?
    private var pendingAutomaticUnlockAfterAppReturnFileID: String?
    @Published private(set) var hasActiveUnlockSession = false
    @Published private var unlockFailedFileIDs: Set<String> = []
    private var idleRelockTask: Task<Void, Never>?
    private var lastUserActivityAt = Date.distantPast

    private let idleRelockDelay: UInt64 = 10 * 60 * 1_000_000_000
    private let userActivityThrottle: TimeInterval = 1

    func lockState(for file: FileState.ActiveFile) -> FileContentLockState {
        displayLockState(
            forStoredLockState: fileLockStates[file.id] ?? .plaintext,
            fileID: file.id
        )
    }

    func previewLockState(for file: FileState.ActiveFile) -> FileContentLockState? {
        guard case .file = file else {
            return .plaintext
        }
        guard let lockState = fileLockStates[file.id] else {
            return nil
        }
        return displayLockState(forStoredLockState: lockState, fileID: file.id)
    }

    func prepareForActiveFileChange(to activeFile: FileState.ActiveFile?) async {
        let nextManagedFile = managedFileReference(for: activeFile)

        activeManagedFile = nextManagedFile
        noteActiveFileChanged(to: activeFile?.id)

        await refresh(activeFile: activeFile)
    }

    func refresh(activeFile: FileState.ActiveFile?) async {
        guard let activeFile else {
            activeFileID = nil
            activeFileLockState = .plaintext
            return
        }

        let fileID = activeFile.id
        activeFileID = fileID
        let lockState = await loadLockState(for: activeFile)
        guard activeFileID == fileID else { return }
        cacheLockState(lockState, fileID: fileID)
    }

    func refresh(file: FileState.ActiveFile) async {
        let lockState = await loadLockState(for: file)
        cacheLockState(lockState, fileID: file.id)
    }

    func refresh(fileObjectID: NSManagedObjectID, fileID: String) async {
        await synchronizeLockState(fileObjectID: fileObjectID, fileID: fileID)
    }

    func removeDeletedFile(fileID: String) {
        let hadPreviewLockState = fileLockStates.removeValue(forKey: fileID) != nil

        if activeFileID == fileID {
            activeFileID = nil
            activeManagedFile = nil
            activeFileLockState = .plaintext
        }
        unlockFailedFileIDs.remove(fileID)

        if suppressedAutomaticUnlockFileID == fileID {
            suppressedAutomaticUnlockFileID = nil
        }
        if pendingAutomaticUnlockAfterAppReturnFileID == fileID {
            pendingAutomaticUnlockAfterAppReturnFileID = nil
        }
        if automaticUnlockRequest?.fileID == fileID {
            automaticUnlockRequest = nil
        }
        if hadPreviewLockState {
            noteFilePreviewLockStateChanged()
        }
    }

    func markUnlockFailed(fileID: String) {
        let previousDisplayLockState = displayLockStateIfKnown(for: fileID)
        unlockFailedFileIDs.insert(fileID)

        if activeFileID == fileID {
            activeFileLockState = .locked
        }
        if previousDisplayLockState != displayLockStateIfKnown(for: fileID) {
            noteFilePreviewLockStateChanged()
        }
    }

    private func noteActiveFileChanged(to fileID: String?) {
        let didChangeFile = activeFileID != fileID
        activeFileID = fileID

        if didChangeFile {
            if let fileID, let lockState = fileLockStates[fileID] {
                activeFileLockState = displayLockState(
                    forStoredLockState: lockState,
                    fileID: fileID
                )
            } else {
                activeFileLockState = .plaintext
            }
        }
        if suppressedAutomaticUnlockFileID != fileID {
            suppressedAutomaticUnlockFileID = nil
        }
        if pendingAutomaticUnlockAfterAppReturnFileID != fileID {
            pendingAutomaticUnlockAfterAppReturnFileID = nil
        }
        if automaticUnlockRequest?.fileID != fileID {
            automaticUnlockRequest = nil
        }
    }

    func allowsAutomaticUnlock(for fileID: String) -> Bool {
        suppressedAutomaticUnlockFileID != fileID ||
        automaticUnlockRequest?.fileID == fileID
    }

    func consumeAutomaticUnlockRequestToken(for fileID: String) -> UUID? {
        guard automaticUnlockRequest?.fileID == fileID else {
            return nil
        }
        let token = automaticUnlockRequest?.token
        automaticUnlockRequest = nil
        return token
    }

    func relockCurrentSession(activeFile: FileState.ActiveFile?) async {
        suppressedAutomaticUnlockFileID = activeFile?.id
        pendingAutomaticUnlockAfterAppReturnFileID = nil
        await forgetTransientUnlockSession()
        await refresh(activeFile: activeFile)
    }

    func relockForAppInactivity(allowAutomaticUnlockOnNextActive: Bool = false) async {
        let fileID = activeManagedFile?.fileID
        suppressedAutomaticUnlockFileID = fileID
        pendingAutomaticUnlockAfterAppReturnFileID = allowAutomaticUnlockOnNextActive ? fileID : nil
        await forgetTransientUnlockSession()

        if let activeManagedFile {
            await synchronizeLockState(
                fileObjectID: activeManagedFile.objectID,
                fileID: activeManagedFile.fileID,
                fallback: .locked
            )
        }
    }

    func activatePendingAutomaticUnlockAfterAppReturn() {
        guard let fileID = pendingAutomaticUnlockAfterAppReturnFileID else { return }
        pendingAutomaticUnlockAfterAppReturnFileID = nil

        guard activeFileID == fileID,
              activeFileLockState == .locked else {
            if suppressedAutomaticUnlockFileID == fileID {
                suppressedAutomaticUnlockFileID = nil
            }
            return
        }

        if suppressedAutomaticUnlockFileID == fileID {
            suppressedAutomaticUnlockFileID = nil
        }
        automaticUnlockRequest = LockedContentAutomaticUnlockRequest(
            fileID: fileID,
            token: UUID()
        )
    }

    func noteUserActivity() {
        guard hasActiveUnlockSession else { return }

        let now = Date()
        guard now.timeIntervalSince(lastUserActivityAt) >= userActivityThrottle else {
            return
        }

        lastUserActivityAt = now
        scheduleIdleRelock()
    }

    func resetAll() {
        let hadPreviewLockState = !fileLockStates.isEmpty || hasActiveUnlockSession
        activeFileLockState = .plaintext
        fileLockStates.removeAll()
        activeFileID = nil
        activeManagedFile = nil
        suppressedAutomaticUnlockFileID = nil
        pendingAutomaticUnlockAfterAppReturnFileID = nil
        automaticUnlockRequest = nil
        let didChangeUnlockSession = setHasActiveUnlockSession(false)
        unlockFailedFileIDs.removeAll()
        idleRelockTask?.cancel()
        idleRelockTask = nil
        if hadPreviewLockState, !didChangeUnlockSession {
            noteFilePreviewLockStateChanged()
        }
    }

    func relockUnlockedContent(knownLockedFiles: [LockedFileSummary]) async {
        if let activeManagedFile,
           knownLockedFiles.contains(where: { $0.id == activeManagedFile.fileID }) {
            suppressedAutomaticUnlockFileID = activeManagedFile.fileID
        }

        await forgetTransientUnlockSession()

        for file in knownLockedFiles {
            await synchronizeLockState(
                fileObjectID: file.fileObjectID,
                fileID: file.id,
                fallback: .locked
            )
        }
    }

    private func forgetTransientUnlockSession() async {
        setHasActiveUnlockSession(false)
        idleRelockTask?.cancel()
        idleRelockTask = nil

        await RecoveryKeyVault.shared.forget()
        await LockedContentUnlockSession.shared.forgetAll()

        for (fileID, lockState) in fileLockStates where lockState == .temporarilyUnlocked {
            fileLockStates[fileID] = .locked
        }

        if let activeFileID, let lockState = fileLockStates[activeFileID] {
            activeFileLockState = displayLockState(
                forStoredLockState: lockState,
                fileID: activeFileID
            )
        } else if activeFileLockState == .temporarilyUnlocked {
            activeFileLockState = .locked
        }
    }

    @discardableResult
    private func synchronizeLockState(
        fileObjectID: NSManagedObjectID,
        fileID: String,
        fallback: FileContentLockState = .plaintext
    ) async -> FileContentLockState {
        let lockState = (try? await PersistenceController.shared.fileRepository
            .fileContentLockState(fileObjectID: fileObjectID)) ?? fallback
        cacheLockState(lockState, fileID: fileID)
        return lockState
    }

    private func cacheLockState(_ lockState: FileContentLockState, fileID: String) {
        let previousDisplayLockState = displayLockStateIfKnown(for: fileID)
        let didChangeUnlockSession = noteUnlockSessionActiveIfNeeded(for: lockState)

        let storedLockState = storedLockState(for: lockState)
        // Identical @Published writes would invalidate all observing file cards.
        if fileLockStates[fileID] != storedLockState {
            fileLockStates[fileID] = storedLockState
        }
        if (lockState == .plaintext || lockState == .temporarilyUnlocked),
           unlockFailedFileIDs.contains(fileID) {
            unlockFailedFileIDs.remove(fileID)
        }

        if activeFileID == fileID {
            let displayState = displayLockState(
                forStoredLockState: storedLockState,
                fileID: fileID
            )
            if activeFileLockState != displayState {
                activeFileLockState = displayState
            }
        }

        if !didChangeUnlockSession {
            let nextDisplayLockState = displayLockStateIfKnown(for: fileID)
            if previousDisplayLockState != nil,
               previousDisplayLockState != nextDisplayLockState {
                noteFilePreviewLockStateChanged()
            }
        }
    }

    @discardableResult
    private func noteUnlockSessionActiveIfNeeded(for lockState: FileContentLockState) -> Bool {
        guard lockState == .temporarilyUnlocked else { return false }
        let didChange = setHasActiveUnlockSession(true)
        scheduleIdleRelock()
        return didChange
    }

    private func storedLockState(for lockState: FileContentLockState) -> FileContentLockState {
        switch lockState {
            case .plaintext:
                .plaintext
            case .locked, .temporarilyUnlocked:
                .locked
        }
    }

    private func displayLockState(
        forStoredLockState lockState: FileContentLockState,
        fileID: String
    ) -> FileContentLockState {
        switch lockState {
            case .plaintext:
                .plaintext
            case .locked, .temporarilyUnlocked:
                hasActiveUnlockSession && !unlockFailedFileIDs.contains(fileID)
                ? .temporarilyUnlocked
                : .locked
        }
    }

    private func displayLockStateIfKnown(for fileID: String) -> FileContentLockState? {
        guard let lockState = fileLockStates[fileID] else { return nil }
        return displayLockState(forStoredLockState: lockState, fileID: fileID)
    }

    @discardableResult
    private func setHasActiveUnlockSession(_ isActive: Bool) -> Bool {
        guard hasActiveUnlockSession != isActive else { return false }
        hasActiveUnlockSession = isActive
        noteFilePreviewLockStateChanged()
        return true
    }

    private func noteFilePreviewLockStateChanged() {
        filePreviewLockStateRevision &+= 1
    }

    private func scheduleIdleRelock() {
        idleRelockTask?.cancel()
        idleRelockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: idleRelockDelay)
            guard !Task.isCancelled else { return }
            await relockAfterIdleTimeout()
        }
    }

    private func relockAfterIdleTimeout() async {
        guard hasActiveUnlockSession else { return }
        await relockForAppInactivity()
    }

    private func managedFileReference(for activeFile: FileState.ActiveFile?) -> ManagedFileReference? {
        guard let activeFile,
              case .file(let file) = activeFile else { return nil }
        return ManagedFileReference(
            objectID: file.objectID,
            fileID: activeFile.id
        )
    }

    private func loadLockState(for file: FileState.ActiveFile) async -> FileContentLockState {
        guard case .file(let managedFile) = file else {
            return .plaintext
        }

        return (try? await PersistenceController.shared.fileRepository
            .fileContentLockState(fileObjectID: managedFile.objectID)) ?? .plaintext
    }
}
