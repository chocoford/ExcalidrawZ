//
//  LockedFileUnlockView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/27.
//

import CoreData
import SwiftUI
import SwiftyAlert

import ChocofordUI

struct LockedFileUnlockRequest {
    let fileObjectID: NSManagedObjectID
    let fileID: String
    let fileName: String
    let allowsAutomaticSystemUnlock: Bool
    let automaticSystemUnlockToken: UUID?
}

struct LockedFileUnlockView: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var lockedContentState: LockedContentStateStore

    let request: LockedFileUnlockRequest
    var isLoadingUnlockedContent = false
    var onUnlock: (Data) async throws -> Void

    @State private var isWorking = false
    @State private var isDeletingFile = false
    @State private var errorMessage: String?
    @State private var allowsPermanentDeleteAfterFailure = false
    @State private var systemUnlockAvailability: LockedContentSystemUnlockAvailability = .unavailable
    @State private var isRecoveryKeySheetPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var hasAttemptedAutomaticSystemUnlock = false
    @State private var showsInlineRecoveryKeyUnlock = false
    @State private var recoveryKeyText = ""
    @FocusState private var isRecoveryKeyFocused: Bool

    private var isUnlockingOrLoading: Bool {
        isWorking || isLoadingUnlockedContent || isDeletingFile
    }

    private var unlockTaskID: LockedFileUnlockTaskID {
        LockedFileUnlockTaskID(
            fileID: request.fileID,
            automaticSystemUnlockToken: request.automaticSystemUnlockToken
        )
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 18) {
                lockIcon

                VStack(spacing: 6) {
                    Text(.localizable(.lockedContentLockedFileOverlayTitle))
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Text(request.fileName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                unlockControls
                    .padding(.top, 4)

                errorView
            }
            .padding(32)
            .frame(maxWidth: 520)
        }
        .animation(.smooth(duration: 0.18), value: isUnlockingOrLoading)
        .onAppear {
            systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
        }
        .task(id: unlockTaskID) {
            recoveryKeyText = ""
            errorMessage = nil
            allowsPermanentDeleteAfterFailure = false
            showsInlineRecoveryKeyUnlock = false
            hasAttemptedAutomaticSystemUnlock = false
            await prepareUnlockMode()
        }
        .sheet(isPresented: $isRecoveryKeySheetPresented) {
            RecoveryKeyInputSheet(
                title: String(localizable: .lockedContentUseRecoveryKeyButton),
                subtitle: request.fileName,
                primaryButtonTitle: String(localizable: .lockedContentUnlockButton),
                width: 520
            ) { recoveryKey in
                do {
                    try await unlockWithRecoveryKey(recoveryKey)
                } catch {
                    let shouldOfferDelete = shouldOfferPermanentDelete(for: error)
                    if shouldOfferDelete {
                        errorMessage = LockedContentErrorPresenter.message(for: error)
                        allowsPermanentDeleteAfterFailure = true
                        lockedContentState.markUnlockFailed(fileID: request.fileID)
                        isRecoveryKeySheetPresented = false
                        return
                    }
                    throw error
                }
            }
        }
        .confirmationDialog(
            String(localizable: .lockedContentDeleteFileConfirmationTitle),
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button(String(localizable: .lockedContentDeleteFileButton), role: .destructive) {
                Task { @MainActor in
                    await deleteFilePermanently()
                }
            }
            Button(String(localizable: .generalButtonCancel), role: .cancel) {}
        } message: {
            Text(.localizable(.lockedContentDeleteCannotBeUndone))
        }
    }

    @ViewBuilder
    private var background: some View {
        Rectangle()
            .fill(.ultraThickMaterial)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var lockIcon: some View {
        Image(systemName: "lock.shield")
            .font(.system(size: 72, weight: .regular))
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var unlockControls: some View {
        if showsInlineRecoveryKeyUnlock {
            inlineRecoveryKeyUnlockControls
        } else {
            systemUnlockControls
        }
    }

    @ViewBuilder
    private var systemUnlockControls: some View {
        VStack(spacing: 6) {
            Button {
                Task {
                    await unlockWithSystemAuthentication()
                }
            } label: {
                systemUnlockButtonLabel
            }
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
            .disabled(isUnlockingOrLoading || !systemUnlockAvailability.isAvailable)
            .help(systemUnlockAvailability.buttonTitle)

            Button {
                isRecoveryKeySheetPresented = true
            } label: {
                Text(.localizable(.lockedContentUseRecoveryKeyButton))
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(isUnlockingOrLoading)
        }
    }

    @ViewBuilder
    private var inlineRecoveryKeyUnlockControls: some View {
        VStack(spacing: 10) {
            SecureField(String(localizable: .lockedContentRecoveryKeyPlaceholder), text: $recoveryKeyText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isRecoveryKeyFocused)
                .frame(maxWidth: 360)
                .disabled(isUnlockingOrLoading)
                .onSubmit {
                    guard !inlineRecoveryKeyButtonDisabled else { return }
                    Task {
                        await unlockWithRecoveryKey()
                    }
                }
#if os(iOS)
                .textInputAutocapitalization(.characters)
#endif

            Button {
                Task {
                    await unlockWithRecoveryKey()
                }
            } label: {
                recoveryUnlockButtonLabel
            }
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
            .disabled(inlineRecoveryKeyButtonDisabled)
        }
        .onAppear {
            isRecoveryKeyFocused = true
        }
    }

    private var inlineRecoveryKeyButtonDisabled: Bool {
        isUnlockingOrLoading || recoveryKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var errorView: some View {
        if let errorMessage {
            VStack(spacing: 8) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                if allowsPermanentDeleteAfterFailure {
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Text(.localizable(.lockedContentDeleteThisFileButton))
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(isUnlockingOrLoading)
                }
            }
        }
    }

    @ViewBuilder
    private var systemUnlockButtonLabel: some View {
        ZStack {
            Label(.localizable(.lockedContentUnlockButton), systemImage: systemUnlockAvailability.systemImage)
                .opacity(isUnlockingOrLoading ? 0 : 1)

            loadingButtonLabel
                .opacity(isUnlockingOrLoading ? 1 : 0)
        }
        .frame(minWidth: 118)
        .animation(.smooth(duration: 0.18), value: isUnlockingOrLoading)
    }

    @ViewBuilder
    private var recoveryUnlockButtonLabel: some View {
        ZStack {
            Text(.localizable(.lockedContentUnlockButton))
                .opacity(isUnlockingOrLoading ? 0 : 1)

            loadingButtonLabel
                .opacity(isUnlockingOrLoading ? 1 : 0)
        }
        .frame(minWidth: 118)
        .animation(.smooth(duration: 0.18), value: isUnlockingOrLoading)
    }

    @ViewBuilder
    private var loadingButtonLabel: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(localizable: .generalLoading)
        }
    }

    private var automaticSystemUnlockDelay: UInt64 {
        650_000_000
    }

    private func prepareUnlockMode() async {
        systemUnlockAvailability = LockedContentSystemUnlockStore.availability()

        if await unlockWithCurrentRecoveryKeyIfPossible() {
            return
        }

        await unlockWithSystemAuthenticationIfPossible()
    }

    private func unlockWithCurrentRecoveryKeyIfPossible() async -> Bool {
        guard let recoveryKey = await RecoveryKeyVault.shared.currentRecoveryKey() else {
            return false
        }
        guard !isWorking else { return true }

        errorMessage = nil
        allowsPermanentDeleteAfterFailure = false
        isWorking = true
        defer { isWorking = false }

        do {
            try await unlockWithRecoveryKey(recoveryKey)
        } catch {
            errorMessage = LockedContentErrorPresenter.message(for: error)
            allowsPermanentDeleteAfterFailure = shouldOfferPermanentDelete(for: error)
            if allowsPermanentDeleteAfterFailure {
                lockedContentState.markUnlockFailed(fileID: request.fileID)
            }
            return false
        }

        return true
    }

    private func unlockWithSystemAuthenticationIfPossible() async {
        guard !hasAttemptedAutomaticSystemUnlock else { return }
        hasAttemptedAutomaticSystemUnlock = true
        guard request.allowsAutomaticSystemUnlock else { return }

        systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
        guard systemUnlockAvailability.isAvailable else {
            return
        }

        try? await Task.sleep(nanoseconds: automaticSystemUnlockDelay)
        guard !Task.isCancelled else { return }

        await unlockWithSystemAuthentication(isAutomatic: true)
    }

    private func unlockWithSystemAuthentication(isAutomatic: Bool = false) async {
        guard !isWorking else { return }
        errorMessage = nil
        allowsPermanentDeleteAfterFailure = false

        isWorking = true
        defer { isWorking = false }

        do {
            let recoveryKey = try await LockedContentSystemUnlockStore.loadRecoveryKey(
                reason: LockedContentSystemUnlockReason.unlockFile
            )
            let content = try await PersistenceController.shared.fileRepository.unlockFileContent(
                fileObjectID: request.fileObjectID,
                recoveryKey: recoveryKey
            )
            _ = try? await PersistenceController.shared.fileRepository
                .unlockLockedFiles(recoveryKey: recoveryKey)
            try await onUnlock(content)
        } catch {
            systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
            if (error as? LockedContentSystemUnlockError) == .noSavedRecoveryKey {
                showsInlineRecoveryKeyUnlock = true
                isRecoveryKeyFocused = true
                return
            }
            if !isAutomatic || !isSilentAutomaticUnlockError(error) {
                errorMessage = LockedContentErrorPresenter.message(for: error)
                allowsPermanentDeleteAfterFailure = shouldOfferPermanentDelete(for: error)
                if allowsPermanentDeleteAfterFailure {
                    lockedContentState.markUnlockFailed(fileID: request.fileID)
                }
            }
        }
    }

    private func unlockWithRecoveryKey() async {
        let startedAt = Date()
        errorMessage = nil
        allowsPermanentDeleteAfterFailure = false
        isWorking = true
        defer { isWorking = false }

        do {
            let recoveryKey = try RecoveryKey(displayString: recoveryKeyText)
            try await unlockWithRecoveryKey(recoveryKey)
        } catch {
            await LockedContentSecurityDelay.waitBeforeShowingFailure(startedAt: startedAt)
            errorMessage = LockedContentErrorPresenter.message(for: error)
            allowsPermanentDeleteAfterFailure = shouldOfferPermanentDelete(for: error)
            if allowsPermanentDeleteAfterFailure {
                lockedContentState.markUnlockFailed(fileID: request.fileID)
            }
        }
    }

    private func unlockWithRecoveryKey(_ recoveryKey: RecoveryKey) async throws {
        let content = try await PersistenceController.shared.fileRepository.unlockFileContent(
            fileObjectID: request.fileObjectID,
            recoveryKey: recoveryKey
        )
        _ = try? await PersistenceController.shared.fileRepository
            .unlockLockedFiles(recoveryKey: recoveryKey)
        try await onUnlock(content)
    }

    private func isSilentAutomaticUnlockError(_ error: Error) -> Bool {
        guard let unlockError = error as? LockedContentSystemUnlockError else {
            return false
        }
        switch unlockError {
            case .canceled, .noSavedRecoveryKey:
                return true
            case .unavailable, .authenticationFailed, .keychainError:
                return false
        }
    }

    private func shouldOfferPermanentDelete(for error: Error) -> Bool {
        guard let encryptedContentError = error as? EncryptedContentError else {
            return false
        }

        return encryptedContentError.allowsPermanentDeleteFallback
    }

    @MainActor
    private func deleteFilePermanently() async {
        guard !isDeletingFile else { return }

        isDeletingFile = true
        defer { isDeletingFile = false }

        do {
            try await PersistenceController.shared.fileRepository.delete(
                fileObjectID: request.fileObjectID,
                forcePermanently: true,
                save: true
            )
            lockedContentState.removeDeletedFile(fileID: request.fileID)
            fileState.setActiveFile(nil)
            fileState.resetSelections()
        } catch {
            errorMessage = LockedContentErrorPresenter.message(for: error)
            alertToast(error)
        }
    }
}

private struct LockedFileUnlockTaskID: Equatable {
    let fileID: String
    let automaticSystemUnlockToken: UUID?
}
