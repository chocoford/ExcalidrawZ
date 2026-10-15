//
//  SecuritySettingsView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/27.
//

import CoreData
import SwiftUI
import SwiftyAlert

import ChocofordUI

struct SecuritySettingsView: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var lockedContentState: LockedContentStateStore

    @State private var lockedFiles: [LockedFileSummary] = []
    @State private var isLoading = false
    @State private var isManagementUnlocked = false
    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @State private var isRecoveryKeySheetPresented = false
    @State private var isLostRecoveryKeyResetSheetPresented = false
    @State private var unlockRequest: LockedFileAccessRequest?
    @State private var resetRequest: RecoveryKeyResetRequest?
    @State private var shouldContinueResetAfterUnlock = false
    @State private var systemUnlockAvailability: LockedContentSystemUnlockAvailability = .unavailable
    @State private var hasAttemptedAutomaticSystemUnlock = false
#if DEBUG
    @State private var isResettingDebugSecurityState = false
#endif

    var body: some View {
        SettingsFormContainer(
            legacyAlignment: .leading,
            legacySpacing: 18
        ) {
            content()
        }
        .task {
            await loadSecuritySettings()
        }
        .watch(value: lockedContentState.hasActiveUnlockSession) { _ in
            Task { @MainActor in
                await refreshLockedFiles()
            }
        }
        .sheet(isPresented: $isRecoveryKeySheetPresented) {
            RecoveryKeyInputSheet(
                title: String(localizable: .lockedContentUseRecoveryKeyButton),
                message: String(localizable: .settingsSecurityUnlockManagementMessage),
                primaryButtonTitle: String(localizable: .lockedContentUnlockButton)
            ) {
                try await unlockManagement(with: $0)
            }
        }
        .sheet(isPresented: $isLostRecoveryKeyResetSheetPresented) {
            LostRecoveryKeyResetSheet { result in
                Task { @MainActor in
                    hasAttemptedAutomaticSystemUnlock = false
                    isManagementUnlocked = false
                    errorMessage = nil
                    lockedContentState.resetAll()
                    await refreshLockedFiles()
                    alertToast(.init(
                        displayMode: .hud,
                        type: .complete(.green),
                        title: String(localizable: .settingsSecurityLockedContentDeletedToastTitle),
                        subTitle: String(localizable: .settingsSecurityLockedContentDeletedToastSubtitle(result.deletedFileCount + result.deletedBackupFileCount))
                    ))
                }
            }
        }
        .sheet(item: $unlockRequest) { request in
            LockedFileAccessSheet(request: request) { _ in
                Task { @MainActor in
                    let shouldContinueReset = shouldContinueResetAfterUnlock
                    isManagementUnlocked = true
                    await refreshLockedFiles()
                    if shouldContinueReset {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        await beginResetRecoveryKey()
                    }
                }
            } onDelete: {
                Task { @MainActor in
                    let shouldContinueReset = shouldContinueResetAfterUnlock
                    await refreshLockedFiles()
                    if shouldContinueReset {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        await beginResetRecoveryKey()
                    }
                }
            }
        }
        .sheet(item: $resetRequest) { request in
            RecoveryKeyResetSheet(request: request) {
                Task { @MainActor in
                    await refreshLockedFiles()
                }
            }
        }
    }

    @ViewBuilder
    private func content() -> some View {
        Section {
            if isLoading {
                HStack {
                    ProgressView()
                    Text(.localizable(.settingsSecurityLoadingLockedContent))
                        .foregroundStyle(.secondary)
                }
            } else if lockedFiles.isEmpty {
                emptyState
            } else if !isManagementUnlocked {
                managementUnlockGate
            } else {
                lockedFilesList
            }
        } header: {
            lockedContentHeader
        } footer: {
#if DEBUG
            VStack(alignment: .leading, spacing: 8) {
                Text(.localizable(.settingsSecurityFooter))

                HStack {
                    Spacer()

                    Button(role: .destructive) {
                        Task {
                            await resetDebugSecurityState()
                        }
                    } label: {
                        if isResettingDebugSecurityState {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text(.localizable(.settingsSecurityDebugResetting))
                            }
                        } else {
                            Label(.localizable(.settingsSecurityDebugResetLockState), systemImage: "trash")
                        }
                    }
                    .disabled(isResettingDebugSecurityState)
                }
            }
#else
            VStack(alignment: .leading, spacing: 8) {
                Text(.localizable(.settingsSecurityFooter))
            }
#endif
        }
    }

    @ViewBuilder
    private var lockedContentHeader: some View {
        HStack {
            Text(.localizable(.settingsSecurityLockedContentTitle))

            Spacer()

            if isManagementUnlocked, hasTemporarilyUnlockedFiles {
                Button {
                    Task {
                        await lockManagementSession()
                    }
                } label: {
                    Label(.localizable(.settingsSecurityLockButton), systemImage: "lock.shield")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button {
                    Task {
                        await beginResetRecoveryKey()
                    }
                } label: {
                    Label(.localizable(.settingsSecurityResetRecoveryKeyButton), systemImage: "key")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(.localizable(.settingsSecurityNoLockedContentTitle))
                    .font(.headline)
                Text(.localizable(.settingsSecurityNoLockedContentMessage))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var managementUnlockGate: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(.localizable(.settingsSecurityProtectedTitle))
                        .font(.headline)
                    Text(.localizable(.settingsSecurityProtectedMessage))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .bottom) {
                Button(role: .destructive) {
                    isLostRecoveryKeyResetSheetPresented = true
                } label: {
                    Text(.localizable(.settingsSecurityLostRecoveryKeyButton))
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .disabled(isUnlocking)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        isRecoveryKeySheetPresented = true
                    } label: {
                        Text(.localizable(.lockedContentUseRecoveryKeyButton))
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(isUnlocking)

                    Button {
                        Task {
                            await unlockManagementWithSystemAuthentication()
                        }
                    } label: {
                        if isUnlocking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(.localizable(.lockedContentUnlockButton), systemImage: systemUnlockAvailability.systemImage)
                        }
                    }
                    .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
                    .disabled(isUnlocking || !systemUnlockAvailability.isAvailable)
                    .help(systemUnlockAvailability.buttonTitle)
                }
            }
            .padding(.top, 2)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var lockedFilesList: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(lockedFiles) { file in
                    LockedFileSettingsRow(
                        file: file,
                        onUnlock: {
                            shouldContinueResetAfterUnlock = false
                            unlockRequest = LockedFileAccessRequest(
                                mode: .unlock,
                                fileObjectID: file.fileObjectID,
                                fileName: file.name,
                                fileID: file.id
                            )
                        },
                        onRemoveLock: {
                            Task {
                                await removeLock(from: file)
                            }
                        }
                    )

                    if file.id != lockedFiles.last?.id {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }

    private var hasTemporarilyUnlockedFiles: Bool {
        lockedFiles.contains { $0.lockState == .temporarilyUnlocked }
    }

    @MainActor
    private func beginResetRecoveryKey() async {
        errorMessage = nil
        await refreshLockedFiles()

        if let lockedFile = lockedFiles.first(where: { $0.lockState == .locked }) {
            shouldContinueResetAfterUnlock = true
            unlockRequest = LockedFileAccessRequest(
                mode: .unlock,
                fileObjectID: lockedFile.fileObjectID,
                fileName: lockedFile.name,
                fileID: lockedFile.id
            )
            return
        }

        let unlockedFileCount = lockedFiles.filter {
            $0.lockState == .temporarilyUnlocked
        }.count
        guard unlockedFileCount > 0 else {
            errorMessage = LockedContentErrorPresenter.message(
                for: EncryptedContentError.contentLocked(
                    contentType: "file",
                    contentID: "unlocked"
                )
            )
            return
        }

        shouldContinueResetAfterUnlock = false
        resetRequest = RecoveryKeyResetRequest(unlockedFileCount: unlockedFileCount)
    }

    private func loadSecuritySettings() async {
        systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
        await refreshLockedFiles()
        await unlockManagementWithSystemAuthenticationIfPossible()
    }

    private func refreshLockedFiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            lockedFiles = try await PersistenceController.shared.fileRepository.listLockedFiles(includeTrash: true)
            if lockedFiles.isEmpty {
                isManagementUnlocked = false
            }
            for file in lockedFiles {
                await lockedContentState.refresh(fileObjectID: file.fileObjectID, fileID: file.id)
            }
            synchronizeManagementUnlockState()
        } catch {
            alertToast(error)
        }
    }

    private func unlockManagement(with recoveryKey: RecoveryKey) async throws {
        let unlockedCount = try await PersistenceController.shared.fileRepository
            .unlockLockedFiles(recoveryKey: recoveryKey, includeTrash: true)

        guard unlockedCount > 0 else {
            throw EncryptedContentError.decryptionFailed
        }

        isManagementUnlocked = true
        errorMessage = nil
        await refreshLockedFiles()
    }

    private func unlockManagementWithSystemAuthenticationIfPossible() async {
        guard !hasAttemptedAutomaticSystemUnlock else { return }
        hasAttemptedAutomaticSystemUnlock = true
        guard !isManagementUnlocked, !lockedFiles.isEmpty else { return }

        systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
        guard systemUnlockAvailability.isAvailable else {
            return
        }

        await unlockManagementWithSystemAuthentication(isAutomatic: true)
    }

    private func unlockManagementWithSystemAuthentication(isAutomatic: Bool = false) async {
        guard !isUnlocking else { return }
        errorMessage = nil
        isUnlocking = true
        defer { isUnlocking = false }

        do {
            let recoveryKey = try await LockedContentSystemUnlockStore.loadRecoveryKey(
                reason: LockedContentSystemUnlockReason.manageLockedContent
            )
            try await unlockManagement(with: recoveryKey)
        } catch {
            systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
            if !isAutomatic || !isSilentAutomaticUnlockError(error) {
                errorMessage = LockedContentErrorPresenter.message(for: error)
            }
        }
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

    private func removeLock(from file: LockedFileSummary) async {
        do {
            try await PersistenceController.shared.fileRepository
                .removeFileLock(fileObjectID: file.fileObjectID)
            await lockedContentState.refresh(fileObjectID: file.fileObjectID, fileID: file.id)
            await refreshLockedFiles()
        } catch {
            alertToast(error)
        }
    }

    @MainActor
    private func lockManagementSession() async {
        errorMessage = nil
        shouldContinueResetAfterUnlock = false
        hasAttemptedAutomaticSystemUnlock = false
        isManagementUnlocked = false

        await lockedContentState.relockUnlockedContent(knownLockedFiles: lockedFiles)
        await refreshLockedFiles()
    }

    @MainActor
    private func synchronizeManagementUnlockState() {
        if lockedFiles.isEmpty {
            isManagementUnlocked = false
        } else if hasTemporarilyUnlockedFiles {
            isManagementUnlocked = true
        } else if !lockedContentState.hasActiveUnlockSession {
            isManagementUnlocked = false
        }
    }

#if DEBUG
    private func resetDebugSecurityState() async {
        guard !isResettingDebugSecurityState else { return }
        isResettingDebugSecurityState = true
        defer { isResettingDebugSecurityState = false }

        do {
            let fileRepository = PersistenceController.shared.fileRepository
            let lockedFiles = try await fileRepository.listLockedFiles(includeTrash: true)

            if !lockedFiles.isEmpty {
                let recoveryKey: RecoveryKey
                if let currentRecoveryKey = await RecoveryKeyVault.shared.currentRecoveryKey() {
                    recoveryKey = currentRecoveryKey
                } else {
                    recoveryKey = try await LockedContentSystemUnlockStore.loadRecoveryKey(
                        reason: String(localizable: .lockedContentSystemUnlockReasonResetDebugState)
                    )
                }

                for file in lockedFiles {
                    _ = try await fileRepository.unlockFileContent(
                        fileObjectID: file.fileObjectID,
                        recoveryKey: recoveryKey
                    )
                    try await fileRepository.removeFileLock(fileObjectID: file.fileObjectID)
                    await lockedContentState.refresh(fileObjectID: file.fileObjectID, fileID: file.id)
                }
            }

            LockedContentSystemUnlockStore.deleteSavedRecoveryKey()
            await RecoveryKeyVault.shared.forgetAll()
            await LockedContentUnlockSession.shared.forgetAll()

            hasAttemptedAutomaticSystemUnlock = false
            isManagementUnlocked = false
            errorMessage = nil
            await refreshLockedFiles()
        } catch let unlockError as LockedContentSystemUnlockError where unlockError == .canceled {
            return
        } catch {
            alertToast(error)
        }
    }
#endif

}

struct LockedContentDestructiveResetResult {
    let deletedFileCount: Int
    let deletedBackupFileCount: Int
}

enum LockedContentDestructiveResetError: LocalizedError {
    case encryptedBackupDeletionFailed(failedCount: Int)
    case noLockedContent

    var errorDescription: String? {
        switch self {
            case .encryptedBackupDeletionFailed(let failedCount):
                String(localizable: .settingsSecurityEncryptedBackupDeletionFailed(failedCount))
            case .noLockedContent:
                String(localizable: .settingsSecurityNoLockedContentFound)
        }
    }
}

func deleteLockedContentAfterLostRecoveryKey() async throws -> LockedContentDestructiveResetResult {
    let deletedFileCount = try await PersistenceController.shared.fileRepository
        .deleteLockedFilesPermanently(includeTrash: true)
    let deletedBackupFileCount: Int
#if canImport(AppKit)
    let backupResult = await deleteEncryptedBackupExcalidrawFiles()

    guard backupResult.failedCount == 0 else {
        throw LockedContentDestructiveResetError
            .encryptedBackupDeletionFailed(failedCount: backupResult.failedCount)
    }
    deletedBackupFileCount = backupResult.deletedCount
#else
    deletedBackupFileCount = 0
#endif

    let deletedCount = deletedFileCount + deletedBackupFileCount
    guard deletedCount > 0 else {
        throw LockedContentDestructiveResetError.noLockedContent
    }

    LockedContentSystemUnlockStore.deleteSavedRecoveryKey()
    await RecoveryKeyVault.shared.forgetAll()
    await LockedContentUnlockSession.shared.forgetAll()
    await MainActor.run {
        NotificationCenter.default.post(name: .lockedContentDidReset, object: nil)
    }

    return .init(
        deletedFileCount: deletedFileCount,
        deletedBackupFileCount: deletedBackupFileCount
    )
}

private struct LostRecoveryKeyResetSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onComplete: (LockedContentDestructiveResetResult) -> Void

    @State private var lockedFileCount: Int?
    @State private var confirmationText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var totalLockedContentCount: Int? {
        lockedFileCount
    }

    var body: some View {
        VStack(spacing: 0) {
            destructiveResetContent

            HStack(spacing: 10) {
                Spacer()
                destructiveResetFooterButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .task {
            await loadCounts()
        }
#if os(macOS)
        .frame(width: 560)
#endif
    }

    @ViewBuilder
    private var destructiveResetContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            destructiveResetHeader
            affectedContent
            confirmationField
            errorLabel
        }
        .padding(24)
    }

    @ViewBuilder
    private var destructiveResetHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)

            Text(.localizable(.settingsSecurityLostRecoveryKeyTitle))
                .font(.title2.weight(.semibold))

            Text(.localizable(.settingsSecurityLostRecoveryKeyMessage))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var affectedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.localizable(.settingsSecurityLostRecoveryKeyDeletesTitle))
                .font(.callout.weight(.medium))
                .foregroundStyle(.red)

            countRow(
                title: String(localizable: .settingsSecurityLostRecoveryKeyLockedFilesTitle),
                count: lockedFileCount,
                systemImage: "lock.shield"
            )

            Text(.localizable(.settingsSecurityLostRecoveryKeyBackupsMessage))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.red.opacity(0.22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func countRow(title: String, count: Int?, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                .frame(width: 22)

            Text(title)
                .font(.callout)

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var confirmationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.localizable(.settingsSecurityDeleteConfirmationInstruction))
                .font(.callout.weight(.medium))

            TextField(String(localizable: .settingsSecurityDeleteConfirmationPlaceholder), text: $confirmationText)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking || totalLockedContentCount == nil)
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var destructiveResetFooterButtons: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                destructiveResetFooterButtonContent
            }
        } else {
            destructiveResetFooterButtonContent
        }
    }

    @ViewBuilder
    private var destructiveResetFooterButtonContent: some View {
        HStack(spacing: 10) {
            Button(.localizable(.generalButtonCancel)) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .modernButtonStyle(style: .glass, size: .large, shape: .capsule)
            .disabled(isWorking)

            Button(role: .destructive) {
                Task {
                    await deleteLockedContent()
                }
            } label: {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(.localizable(.settingsSecurityDeleteLockedContentButton))
                }
            }
            .keyboardShortcut(.defaultAction)
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
            .disabled(destructiveResetButtonDisabled)
        }
    }

    private var destructiveResetButtonDisabled: Bool {
        isWorking ||
        totalLockedContentCount == nil ||
        totalLockedContentCount == 0 ||
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) != "DELETE"
    }

    @MainActor
    private func loadCounts() async {
        do {
            let lockedFiles = try await PersistenceController.shared.fileRepository
                .listLockedFiles(includeTrash: true)
            lockedFileCount = lockedFiles.count
        } catch {
            lockedFileCount = 0
            errorMessage = LockedContentErrorPresenter.message(for: error)
        }
    }

    @MainActor
    private func deleteLockedContent() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await deleteLockedContentAfterLostRecoveryKey()
            onComplete(result)
            dismiss()
        } catch {
            errorMessage = LockedContentErrorPresenter.message(for: error)
            await loadCounts()
        }
    }
}

private struct LockedFileSettingsRow: View {
    let file: LockedFileSummary
    var onUnlock: () -> Void
    var onRemoveLock: () -> Void

    private var isUnlocked: Bool {
        file.lockState == .temporarilyUnlocked
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isUnlocked ? LockedContentSymbols.keyShield : LockedContentSymbols.lockShield)
                .font(.body.weight(.semibold))
                .foregroundStyle(isUnlocked ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(isUnlocked ? String(localizable: .settingsSecurityTemporarilyUnlockedStatus) : String(localizable: .settingsSecurityLockedStatus))
                    if let updatedAt = file.updatedAt {
                        Text(updatedAt.formatted())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                if isUnlocked {
                    Button(role: .destructive) {
                        onRemoveLock()
                    } label: {
                        Label(.localizable(.settingsSecurityRemoveLockButton), systemImage: LockedContentSymbols.removeLock)
                    }
                } else {
                    Button {
                        onUnlock()
                    } label: {
                        Label(.localizable(.settingsSecurityUnlockMenuButton), systemImage: LockedContentSymbols.keyShield)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

private struct RecoveryKeyResetRequest: Identifiable {
    let id = UUID()
    let unlockedFileCount: Int
}

private struct RecoveryKeyResetSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: RecoveryKeyResetRequest
    var onComplete: () -> Void

    @State private var generatedRecoveryKey: RecoveryKey?
    @State private var hasSavedRecoveryKey = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header

                Text(.localizable(.settingsSecurityResetRecoveryKeyMessage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Text(generatedRecoveryKey?.displayString ?? String(localizable: .lockedContentUnableToGenerateRecoveryKey))
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    CopyFeedbackButton(
                        text: generatedRecoveryKey?.displayString ?? "",
                        help: String(localizable: .lockedContentCopyRecoveryKeyHelp),
                        iconFrame: CGSize(width: 18, height: 18),
                        iconFont: .body
                    )
                    .buttonStyle(.borderless)
                    .disabled(generatedRecoveryKey == nil)
                }

                Toggle(isOn: $hasSavedRecoveryKey) {
                    Text(.localizable(.settingsSecuritySavedNewRecoveryKeyConfirmation))
                        .font(.callout.weight(.medium))
                }
#if os(macOS)
                .toggleStyle(.checkbox)
#endif

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)

            HStack(spacing: 10) {
                Spacer()
                footerButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .onAppear {
            if generatedRecoveryKey == nil {
                do {
                    generatedRecoveryKey = try RecoveryKeyService.generate()
                } catch {
                    errorMessage = LockedContentErrorPresenter.message(for: error)
                }
            }
        }
#if os(macOS)
        .frame(width: 560)
#endif
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)

            Text(.localizable(.settingsSecurityResetRecoveryKeyTitle))
                .font(.title2.weight(.semibold))

            Text(.localizable(.settingsSecurityResetRecoveryKeyUnlockedFileCount(request.unlockedFileCount)))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                footerButtonContent
            }
        } else {
            footerButtonContent
        }
    }

    @ViewBuilder
    private var footerButtonContent: some View {
        HStack(spacing: 10) {
            Button(.localizable(.generalButtonCancel)) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .modernButtonStyle(style: .glass, size: .large, shape: .capsule)
            .disabled(isWorking)

            Button {
                Task {
                    await resetRecoveryKey()
                }
            } label: {
                Text(.localizable(.settingsSecurityResetKeyButton))
            }
            .keyboardShortcut(.defaultAction)
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
            .disabled(isWorking || generatedRecoveryKey == nil || !hasSavedRecoveryKey)
        }
    }

    private func resetRecoveryKey() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        do {
            guard let generatedRecoveryKey else { return }
            let resetCount = try await PersistenceController.shared.fileRepository
                .resetUnlockedFilesRecoveryKey(newRecoveryKey: generatedRecoveryKey, includeTrash: true)
            guard resetCount > 0 else {
                throw EncryptedContentError.contentLocked(contentType: "file", contentID: "unlocked")
            }
            onComplete()
            dismiss()
        } catch {
            errorMessage = LockedContentErrorPresenter.message(for: error)
        }
    }

}
