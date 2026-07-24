//
//  LockedFileAccessSheet.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/27.
//

import CoreData
import SwiftUI
import UniformTypeIdentifiers
import ChocofordUI

enum LockedFileAccessMode: Sendable {
    case lock
    case unlock
}

struct LockedFileAccessRequest: Identifiable {
    let id = UUID()
    let mode: LockedFileAccessMode
    let fileObjectID: NSManagedObjectID
    let fileName: String
    let fileID: String?

    init(
        mode: LockedFileAccessMode,
        fileObjectID: NSManagedObjectID,
        fileName: String,
        fileID: String? = nil
    ) {
        self.mode = mode
        self.fileObjectID = fileObjectID
        self.fileName = fileName
        self.fileID = fileID
    }
}

private enum LockRecoveryKeyMode {
    case loading
    case createUnifiedKey
    case useActiveUnifiedKey
}

private enum LockSecurityPalette {
    static let safe = Color(red: 0.27, green: 0.76, blue: 0.55)
    static let key = Color(red: 0.78, green: 0.60, blue: 0.28)
    static let ai = Color(red: 0.56, green: 0.55, blue: 0.98)
}

struct LockedFileAccessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var lockedContentState: LockedContentStateStore

    private let recoveryKeyControlHeight: CGFloat = 44

    let request: LockedFileAccessRequest
    let automaticallyRequestsSystemAuthentication: Bool
    var onComplete: ((LockedFileAccessMode) -> Void)?
    var onDelete: (() -> Void)?

    @State private var generatedRecoveryKey: RecoveryKey?
    @State private var enteredRecoveryKey = ""
    @State private var hasSavedRecoveryKey = false
    @State private var lockRecoveryKeyMode: LockRecoveryKeyMode = .loading
    @State private var isWorking = false
    @State private var isDeletingFile = false
    @State private var errorMessage: String?
    @State private var allowsPermanentDeleteAfterFailure = false
    @State private var systemUnlockAvailability: LockedContentSystemUnlockAvailability = .unavailable
    @State private var isRecoveryKeyExporterPresented = false
    @State private var isDeleteConfirmationPresented = false

    init(
        request: LockedFileAccessRequest,
        automaticallyRequestsSystemAuthentication: Bool = false,
        onComplete: ((LockedFileAccessMode) -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.request = request
        self.automaticallyRequestsSystemAuthentication = automaticallyRequestsSystemAuthentication
        self.onComplete = onComplete
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                header

                switch request.mode {
                    case .lock:
                        lockContent
                    case .unlock:
                        unlockContent
                }

                errorView
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
        .task(id: request.id) {
            errorMessage = nil
            allowsPermanentDeleteAfterFailure = false
            if request.mode == .lock {
                await prepareLockMode()
            } else {
                await prepareUnlockMode()
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
        .fileExporter(
            isPresented: $isRecoveryKeyExporterPresented,
            document: RecoveryKeyTextDocument(text: recoveryKeyExportText),
            contentType: .plainText,
            defaultFilename: recoveryKeyExportFilename
        ) { result in
            switch result {
                case .success:
                    alertToast(.init(
                        displayMode: .hud,
                        type: .complete(.green),
                        title: String(localizable: .generalFileExporterSaved)
                    ))
                case .failure(let error):
                    alertToast(error)
            }
        }
#if os(macOS)
        .frame(width: 560)
#endif
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            headerIcon

            VStack(alignment: .leading, spacing: 5) {
                Text(request.mode == .lock ? String(localizable: .lockFileTitle) : String(localizable: .unlockFileTitle))
                    .font(.title2.weight(.semibold))

                Text(request.fileName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var headerIcon: some View {
        let tint = LockSecurityPalette.safe

        Image(systemName: request.mode == .lock ? LockedContentSymbols.lockShield : LockedContentSymbols.keyShield)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .lockHeaderIconChrome(tint: tint)
    }

    @ViewBuilder
    private var lockContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            lockFeatureSummary

            switch lockRecoveryKeyMode {
                case .loading:
                    loadingRecoveryKeyInstruction
                    recoveryKeyLoadingDisplay
                    savedRecoveryKeyToggle(isOn: .constant(false))
                        .opacity(0)
                        .accessibilityHidden(true)

                case .createUnifiedKey:
                    recoveryKeyInstruction

                    recoveryKeyDisplay(
                        generatedRecoveryKey?.displayString ?? String(localizable: .lockedContentUnableToGenerateRecoveryKey)
                    )

                    savedRecoveryKeyToggle(isOn: $hasSavedRecoveryKey)

                case .useActiveUnifiedKey:
                    Label(.localizable(.lockedContentExistingRecoveryKeyNotice), systemImage: "key.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var recoveryKeyInstruction: some View {
        Text(.localizable(.lockedContentRecoveryKeyInstruction))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var loadingRecoveryKeyInstruction: some View {
        ZStack(alignment: .leading) {
            recoveryKeyInstruction
                .opacity(0)
                .accessibilityHidden(true)

            Text(.localizable(.lockedContentPreparingRecoveryKey))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var recoveryKeyLoadingDisplay: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(.localizable(.lockedContentGenerating))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: recoveryKeyControlHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recoveryKeyFieldChrome()

            copyRecoveryKeyButton(isHidden: true)
            downloadRecoveryKeyButton(isHidden: true)
        }
    }

    @ViewBuilder
    private func savedRecoveryKeyToggle(isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(.localizable(.lockedContentSavedRecoveryKeyConfirmation))
                .font(.callout.weight(.medium))
        }
#if os(macOS)
        .toggleStyle(.checkbox)
#endif
    }

    @ViewBuilder
    private func copyRecoveryKeyButton(isHidden: Bool = false) -> some View {
        CopyFeedbackButton(
            text: generatedRecoveryKey?.displayString ?? "",
            help: String(localizable: .lockedContentCopyRecoveryKeyHelp),
            iconFrame: CGSize(width: recoveryKeyControlHeight, height: recoveryKeyControlHeight),
            iconFont: .body.weight(.semibold),
            normalColor: .primary
        )
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
        .disabled(isHidden || generatedRecoveryKey == nil)
        .opacity(isHidden ? 0 : 1)
        .accessibilityHidden(isHidden)
    }

    @ViewBuilder
    private func downloadRecoveryKeyButton(isHidden: Bool = false) -> some View {
        Button {
            isRecoveryKeyExporterPresented = true
        } label: {
            Image(systemName: "square.and.arrow.down")
                .frame(width: recoveryKeyControlHeight, height: recoveryKeyControlHeight)
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
        .disabled(isHidden || generatedRecoveryKey == nil)
        .opacity(isHidden ? 0 : 1)
        .accessibilityHidden(isHidden)
        .help(String(localizable: .lockedContentSaveRecoveryKeyHelp))
    }

    @ViewBuilder
    private var lockFeatureSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            lockFeatureRow(
                icon: "key.fill",
                title: String(localizable: .lockedContentFeatureEncryptTitle),
                message: String(localizable: .lockedContentFeatureEncryptMessage),
                tint: LockSecurityPalette.safe
            )
            lockFeatureRow(
                icon: "lock.shield",
                title: String(localizable: .lockedContentFeatureUnlockTitle),
                message: String(localizable: .lockedContentFeatureUnlockMessage),
                tint: LockSecurityPalette.key
            )
            lockFeatureRow(
                icon: "sparkles",
                title: String(localizable: .lockedContentFeatureAIOutTitle),
                message: String(localizable: .lockedContentFeatureAIOutMessage),
                tint: LockSecurityPalette.ai
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .lockFeaturePanelChrome(tint: LockSecurityPalette.safe)
    }

    @ViewBuilder
    private func lockFeatureRow(icon: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var errorView: some View {
        if let errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)

                if allowsPermanentDeleteAfterFailure {
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Text(.localizable(.lockedContentDeleteThisFileButton))
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(isWorking || isDeletingFile)
                }
            }
        }
    }

    @ViewBuilder
    private var unlockContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.localizable(.lockedContentUnlockRecoveryKeyMessage))
                .font(.callout)
                .foregroundStyle(.secondary)

            if systemUnlockAvailability.isAvailable {
                Button {
                    Task {
                        await unlockWithSystemAuthentication()
                    }
                } label: {
                    Label(
                        systemUnlockAvailability.buttonTitle,
                        systemImage: systemUnlockAvailability.systemImage
                    )
                }
                .modernButtonStyle(style: .glass, size: .large, shape: .capsule)
                .disabled(isWorking)
            }

            recoveryKeyTextField(text: $enteredRecoveryKey)
        }
    }

    @ViewBuilder
    private func recoveryKeyDisplay(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 16)
                .frame(height: recoveryKeyControlHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            .recoveryKeyFieldChrome()

            copyRecoveryKeyButton()
            downloadRecoveryKeyButton()
        }
    }

    @ViewBuilder
    private func recoveryKeyTextField(text: Binding<String>) -> some View {
        TextField(String(localizable: .lockedContentRecoveryKeySamplePlaceholder), text: text)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .padding(.horizontal, 16)
            .frame(height: recoveryKeyControlHeight)
            .recoveryKeyFieldChrome()
#if os(iOS)
            .textInputAutocapitalization(.characters)
#endif
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
                    await performAction()
                }
            } label: {
                Text(request.mode == .lock ? String(localizable: .lockFileTitle) : String(localizable: .lockedContentUnlockButton))
            }
            .keyboardShortcut(.defaultAction)
            .modernButtonStyle(style: .glassProminent, size: .large, shape: .capsule)
            .disabled(primaryButtonDisabled)
        }
    }

    private var primaryButtonDisabled: Bool {
        if isWorking || isDeletingFile {
            return true
        }
        switch request.mode {
            case .lock:
                switch lockRecoveryKeyMode {
                    case .loading:
                        return true
                    case .createUnifiedKey:
                        return generatedRecoveryKey == nil || !hasSavedRecoveryKey
                    case .useActiveUnifiedKey:
                        return false
                }
            case .unlock:
                return enteredRecoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func performAction() async {
        let startedAt = Date()
        errorMessage = nil
        allowsPermanentDeleteAfterFailure = false
        isWorking = true
        defer { isWorking = false }

        do {
            switch request.mode {
                case .lock:
                    let recoveryKey = try await recoveryKeyForLocking()
                    try await PersistenceController.shared.fileRepository.lockFileContent(
                        fileObjectID: request.fileObjectID,
                        recoveryKey: recoveryKey
                    )
                case .unlock:
                    let recoveryKey = try RecoveryKey(displayString: enteredRecoveryKey)
                    try await unlockFile(with: recoveryKey)
            }
            onComplete?(request.mode)
            dismiss()
        } catch {
            if shouldDelayFailedAttempt {
                await LockedContentSecurityDelay.waitBeforeShowingFailure(startedAt: startedAt)
            }
            showUnlockFailure(error)
        }
    }

    private var shouldDelayFailedAttempt: Bool {
        switch request.mode {
            case .unlock:
                return true
            case .lock:
                return false
        }
    }

    private func prepareLockMode() async {
        errorMessage = nil
        generatedRecoveryKey = nil
        hasSavedRecoveryKey = false
        enteredRecoveryKey = ""

        if await RecoveryKeyVault.shared.currentRecoveryKey() != nil {
            lockRecoveryKeyMode = .useActiveUnifiedKey
            return
        }

        do {
            generatedRecoveryKey = try RecoveryKeyService.generate()
            lockRecoveryKeyMode = .createUnifiedKey
        } catch {
            errorMessage = LockedContentErrorPresenter.message(for: error)
        }
    }

    private func prepareUnlockMode() async {
        systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
        errorMessage = nil
        allowsPermanentDeleteAfterFailure = false
        enteredRecoveryKey = ""

        if await unlockWithCurrentRecoveryKeyIfPossible() {
            return
        }

        guard automaticallyRequestsSystemAuthentication,
              systemUnlockAvailability.isAvailable else {
            return
        }
        await unlockWithSystemAuthentication()
    }

    private func recoveryKeyForLocking() async throws -> RecoveryKey {
        if let recoveryKey = await RecoveryKeyVault.shared.currentRecoveryKey() {
            return recoveryKey
        }

        switch lockRecoveryKeyMode {
            case .createUnifiedKey:
                guard let generatedRecoveryKey else {
                    throw EncryptedContentError.invalidRecoveryMetadata
                }
                return generatedRecoveryKey

            case .useActiveUnifiedKey, .loading:
                throw EncryptedContentError.invalidRecoveryMetadata
        }
    }

    private func unlockWithSystemAuthentication() async {
        guard !isWorking else { return }
        errorMessage = nil
        allowsPermanentDeleteAfterFailure = false
        isWorking = true
        defer { isWorking = false }

        do {
            let recoveryKey = try await LockedContentSystemUnlockStore.loadRecoveryKey(
                reason: LockedContentSystemUnlockReason.unlockFile
            )
            try await unlockFile(with: recoveryKey)
            onComplete?(request.mode)
            dismiss()
        } catch {
            showUnlockFailure(error)
            systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
        }
    }

    @discardableResult
    private func unlockWithCurrentRecoveryKeyIfPossible() async -> Bool {
        guard request.mode == .unlock,
              !isWorking,
              let recoveryKey = await RecoveryKeyVault.shared.currentRecoveryKey() else {
            return false
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await unlockFile(with: recoveryKey)
            onComplete?(request.mode)
            dismiss()
            return true
        } catch {
            showUnlockFailure(error)
            return false
        }
    }

    private func unlockFile(with recoveryKey: RecoveryKey) async throws {
        try await PersistenceController.shared.fileRepository.unlockFileContent(
            fileObjectID: request.fileObjectID,
            recoveryKey: recoveryKey
        )
        _ = try? await PersistenceController.shared.fileRepository
            .unlockLockedFiles(recoveryKey: recoveryKey)

        if let fileID = request.fileID {
            await lockedContentState.refresh(
                fileObjectID: request.fileObjectID,
                fileID: fileID
            )
        }
    }

    private func showUnlockFailure(_ error: Error) {
        errorMessage = LockedContentErrorPresenter.message(for: error)
        allowsPermanentDeleteAfterFailure = shouldOfferPermanentDelete(for: error)

        if allowsPermanentDeleteAfterFailure, let fileID = request.fileID {
            lockedContentState.markUnlockFailed(fileID: fileID)
        }
    }

    private func shouldOfferPermanentDelete(for error: Error) -> Bool {
        guard request.mode == .unlock,
              let encryptedContentError = error as? EncryptedContentError else {
            return false
        }

        return encryptedContentError.allowsPermanentDeleteFallback
    }

    @MainActor
    private func deleteFilePermanently() async {
        guard request.mode == .unlock, !isDeletingFile else { return }

        isDeletingFile = true
        defer { isDeletingFile = false }

        do {
            try await PersistenceController.shared.fileRepository.delete(
                fileObjectID: request.fileObjectID,
                forcePermanently: true,
                save: true
            )
            if let fileID = request.fileID {
                lockedContentState.removeDeletedFile(fileID: fileID)
            }
            let userInfo: [AnyHashable: Any]? = request.fileID.map { ["fileID": $0] }
            NotificationCenter.default.post(
                name: .lockedContentDidDeleteFile,
                object: request.fileObjectID,
                userInfo: userInfo
            )
            onDelete?()
            dismiss()
        } catch {
            errorMessage = LockedContentErrorPresenter.message(for: error)
            alertToast(error)
        }
    }

    private var recoveryKeyExportText: String {
        guard let recoveryKey = generatedRecoveryKey?.displayString else {
            return ""
        }

        return """
        \(String(localizable: .lockedContentRecoveryKeyExportTitle))

        \(recoveryKey)

        \(String(localizable: .lockedContentRecoveryKeyExportNote))
        """
    }

    private var recoveryKeyExportFilename: String {
        String(localizable: .lockedContentRecoveryKeyExportTitle)
    }
}

private struct RecoveryKeyTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct RecoveryKeyFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .background(.quaternary, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.primary.opacity(0.06), lineWidth: 1)
                }
        } else {
            content
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }
}

private extension View {
    func recoveryKeyFieldChrome() -> some View {
        modifier(RecoveryKeyFieldChrome())
    }
}

private struct LockHeaderIconChrome: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .background {
                    Circle()
                        .fill(.clear)
                        .glassEffect(
                            Glass.regular.tint(tint.opacity(0.14)),
                            in: Circle()
                        )
                }
        } else {
            content
                .background(tint.opacity(0.16), in: Circle())
        }
    }
}

private extension View {
    func lockHeaderIconChrome(tint: Color) -> some View {
        modifier(LockHeaderIconChrome(tint: tint))
    }
}

private struct LockFeaturePanelChrome: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .background {
                    shape
                        .fill(.clear)
                        .glassEffect(
                            Glass.regular.tint(tint.opacity(0.045)),
                            in: shape
                        )
                }
                .overlay {
                    shape
                        .stroke(tint.opacity(0.08), lineWidth: 1)
                }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .background(tint.opacity(0.035), in: shape)
                .overlay {
                    shape
                        .stroke(tint.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

private extension View {
    func lockFeaturePanelChrome(tint: Color) -> some View {
        modifier(LockFeaturePanelChrome(tint: tint))
    }
}
