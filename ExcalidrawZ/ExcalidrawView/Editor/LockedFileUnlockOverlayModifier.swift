//
//  LockedFileUnlockOverlayModifier.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/28.
//

import Foundation
import SwiftUI
import ChocofordUI

struct ExcalidrawDocumentLoadCompletion: Equatable {
    let fileID: String
    private let token = UUID()
}

private enum LockedFileUnlockPhase {
    case hidden
    case locked
    case loading
}

struct LockedFileUnlockOverlayModifier: ViewModifier {
    @Environment(LockedContentStateStore.self) private var lockedContentState

    var activeFile: FileState.ActiveFile?
    var documentLoadCompletion: ExcalidrawDocumentLoadCompletion?
    var onPrepareLockedFile: @MainActor () -> Void
    var onApplyUnlockedContent: (Data, LockedFileUnlockRequest) async throws -> Void

    @State private var request: LockedFileUnlockRequest?
    @State private var phase: LockedFileUnlockPhase = .hidden
    @State private var loadingStartedAt: Date?
    @State private var dismissTask: Task<Void, Never>?

    private let fadeDuration: UInt64 = 220_000_000
    private let minimumLoadingDuration: TimeInterval = 0.45

    private var isVisible: Bool {
        request?.fileID == activeFile?.id && phase != .hidden
    }

    private var isLoading: Bool {
        phase == .loading
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                overlay
            }
            .animation(.smooth(duration: 0.4), value: isVisible)
            .watch(value: activeFile?.id) { _ in
                reset()
                presentIfNeeded()
            }
            .watch(value: lockedContentState.activeFileLockState) { lockState in
                handleLockStateChange(lockState)
            }
            .watch(value: lockedContentState.automaticUnlockRequest) { request in
                handleAutomaticUnlockRequest(request)
            }
            .watch(value: documentLoadCompletion) { completion in
                guard let completion else { return }
                handleDocumentLoadFinished(fileID: completion.fileID)
            }
            .task(id: activeFile?.id) {
                await MainActor.run {
                    presentIfNeeded()
                }
            }
    }

    @ViewBuilder
    private var overlay: some View {
        if let request, request.fileID == activeFile?.id {
            LockedFileUnlockView(
                request: request,
                isLoadingUnlockedContent: isLoading
            ) { content in
                try await applyUnlockedContent(content, request: request)
            }
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .animation(.smooth(duration: 0.22), value: isVisible)
        }
    }

    @MainActor
    private func handleLockStateChange(_ lockState: FileContentLockState) {
        switch lockState {
            case .locked:
                presentIfNeeded()
            case .plaintext, .temporarilyUnlocked:
                guard phase != .loading,
                      let fileID = request?.fileID else { return }
                hide(fileID: fileID)
        }
    }

    @MainActor
    private func handleAutomaticUnlockRequest(_ request: LockedContentAutomaticUnlockRequest?) {
        guard let request,
              request.fileID == activeFile?.id,
              lockedContentState.activeFileLockState == .locked else { return }

        reset()
        presentIfNeeded()
    }

    @MainActor
    private func presentIfNeeded() {
        guard lockedContentState.activeFileLockState == .locked,
              phase != .loading,
              let activeFile,
              lockedContentState.lockState(for: activeFile) == .locked,
              case .file(let file) = activeFile else { return }

        if request?.fileID == activeFile.id, phase != .hidden {
            return
        }

        dismissTask?.cancel()
        dismissTask = nil
        onPrepareLockedFile()
        let automaticUnlockToken = lockedContentState
            .consumeAutomaticUnlockRequestToken(for: activeFile.id)
        let nextRequest = LockedFileUnlockRequest(
            fileObjectID: file.objectID,
            fileID: activeFile.id,
            fileName: file.name ?? String(localizable: .generalUntitled),
            allowsAutomaticSystemUnlock: automaticUnlockToken != nil
                || lockedContentState.allowsAutomaticUnlock(for: activeFile.id),
            automaticSystemUnlockToken: automaticUnlockToken
        )
        request = nextRequest
        phase = .hidden
        loadingStartedAt = nil

        let nextFileID = activeFile.id
        Task { @MainActor in
            await Task.yield()
            guard request?.fileID == nextFileID,
                  phase == .hidden else { return }
            phase = .locked
        }
    }

    private func applyUnlockedContent(
        _ content: Data,
        request: LockedFileUnlockRequest
    ) async throws {
        let canApply = await MainActor.run {
            guard self.request?.fileID == request.fileID else { return false }
            dismissTask?.cancel()
            dismissTask = nil
            phase = .loading
            loadingStartedAt = Date()
            return true
        }
        guard canApply else { return }

        do {
            try await onApplyUnlockedContent(content, request)
            await lockedContentState.refresh(
                fileObjectID: request.fileObjectID,
                fileID: request.fileID
            )
        } catch {
            await MainActor.run {
                guard self.request?.fileID == request.fileID else { return }
                phase = .locked
                loadingStartedAt = nil
            }
            throw error
        }
    }

    @MainActor
    private func handleDocumentLoadFinished(fileID: String) {
        guard phase == .loading,
              request?.fileID == fileID,
              activeFile?.id == fileID else { return }

        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            let elapsed = loadingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            let minimumRemaining = max(0, minimumLoadingDuration - elapsed)
            let delay = max(fadeDuration, UInt64(minimumRemaining * 1_000_000_000))
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled,
                  phase == .loading,
                  request?.fileID == fileID,
                  activeFile?.id == fileID else { return }
            hide(fileID: fileID)
        }
    }

    @MainActor
    private func hide(fileID: String) {
        guard request?.fileID == fileID else { return }
        phase = .hidden
        loadingStartedAt = nil

        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: fadeDuration)
            guard !Task.isCancelled,
                  phase == .hidden,
                  request?.fileID == fileID else { return }
            request = nil
            dismissTask = nil
        }
    }

    @MainActor
    private func reset() {
        dismissTask?.cancel()
        dismissTask = nil
        request = nil
        phase = .hidden
        loadingStartedAt = nil
    }
}
