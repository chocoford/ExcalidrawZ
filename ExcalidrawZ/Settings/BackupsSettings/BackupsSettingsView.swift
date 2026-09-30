//
//  BackupsSettingsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/15.
//

import SwiftUI
import SwiftyAlert
import CoreData
#if os(macOS)
import AppKit
#endif

import ChocofordUI

#if os(macOS)
private struct BackupFilePreview {
    let url: URL
    let file: ExcalidrawFile
}

struct BackupsSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) var alertToast
    
    @State private var backups: [URL] = []
    
    @State private var selectedBackup: URL?
    @State private var selectedBackupSize: Int = 0

    @State private var selectedBackupDirs: [String : [URL]] = [:]
    
    @State private var selectedFile: URL?
    
    @State private var backupToBeDeleted: URL?
    @State private var isExportingBackup = false
    @State private var unlockedBackupPreview: BackupFilePreview?
    @State private var isUnlockingBackupPreview = false
    @State private var backupPreviewErrorMessage: String?
    @State private var isBackupPreviewRecoveryKeySheetPresented = false
    @State private var systemUnlockAvailability: LockedContentSystemUnlockAvailability = .unavailable
    
    enum Route: Hashable {
        case dateList
        case folderList
    }
    
    @State private var route: Route = .dateList
    
    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                switch route {
                    case .dateList:
                        backupsDateList()
                    case .folderList:
                        VStack(spacing: 0) {
                            HStack {
                                Button {
                                    route = .dateList
                                    self.selectedBackup = nil
                                    self.selectedFile = nil
                                } label: {
                                    Label(.localizable(.navigationButtonBack), systemSymbol: .chevronLeft)
                                }
                                .buttonStyle(.borderless)
                                Spacer()
                            }
                            .padding(6)
                            .transition(.opacity)
                            
                            if let selectedBackup {
                                BackupContentView(
                                    backup: selectedBackup,
                                    selectedFile: $selectedFile,
                                    selectedBackupSize: $selectedBackupSize
                                )
                                .transition(.opacity.combined(with: .offset(x: 50)).animation(.smooth(duration: 0.2)))
                            }
                        }
                        .animation(.default, value: selectedBackup)
                }
            }
            .clipped()
            .animation(.default, value: route)
            .frame(width: 240)
            // .visualEffect(material: .sidebar)

            Divider()
            
            ZStack {
                if let selectedFile {
                    if let unlockedBackupPreview,
                       unlockedBackupPreview.url == selectedFile {
                        ExcalidrawRenderer(file: unlockedBackupPreview.file)
                    } else if let excalidrawFile = try? ExcalidrawFile(contentsOf: selectedFile) {
                        ExcalidrawRenderer(file: excalidrawFile)
                    } else if isAppEncryptedBackupFile(selectedFile) {
                        backupEncryptedPreviewLoadingView()
                    } else if isRecoveryKeyEncryptedBackupFile(selectedFile) {
                        encryptedBackupFileView(selectedFile)
                    } else if let selectedBackup {
                        backupHomeView(selectedBackup)
                    }
                } else if let selectedBackup {
                    backupHomeView(selectedBackup)
                } else {
                    placeholderView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .watch(value: selectedFile) { newValue in
            unlockedBackupPreview = nil
            backupPreviewErrorMessage = nil
            isBackupPreviewRecoveryKeySheetPresented = false
            guard let newValue else { return }
            if isAppEncryptedBackupFile(newValue) {
                Task {
                    await loadBackupPreviewWithBackupKey(newValue)
                }
            } else if isRecoveryKeyEncryptedBackupFile(newValue) {
                Task {
                    await unlockBackupPreviewWithSystemAuthentication(newValue, isAutomatic: true)
                }
            }
        }
        .confirmationDialog(
            String(localizable: .backupsDeleteConfirmationTitle),
            isPresented: Binding { backupToBeDeleted != nil } set: { if !$0 { backupToBeDeleted = nil } }
        ) {
            Button(role: .destructive) {
                deleteBackup()
            } label: {
                Text(.localizable(.generalButtonConfirm))
            }
        }
        .sheet(isPresented: $isBackupPreviewRecoveryKeySheetPresented) {
            if let selectedFile {
                RecoveryKeyInputSheet(
                    title: String(localizable: .lockedContentUseRecoveryKeyButton),
                    subtitle: selectedFile.deletingPathExtension().lastPathComponent,
                    primaryButtonTitle: String(localizable: .lockedContentUnlockButton),
                    headerLayout: .compact,
                    width: 520
                ) { recoveryKey in
                    try await unlockBackupPreview(selectedFile, recoveryKey: recoveryKey)
                }
            } else {
                EmptyView()
            }
        }
        .onAppear {
            systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
            loadBackups()
        }
        .onDisappear {
            unlockedBackupPreview = nil
            backupPreviewErrorMessage = nil
            isBackupPreviewRecoveryKeySheetPresented = false
        }
    }
    
    @ViewBuilder
    private func backupsDateList() -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(backups, id: \.self) { item in
                    Button {
                        route = .folderList
                        selectedBackup = item
                    } label: {
                        Text(item.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.listCell(selected: selectedBackup == item))
                    .contextMenu {
                        Button(role: .destructive) {
                            backupToBeDeleted = item
                        } label: {
                            Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
            .padding(10)
            .frame(minHeight: 400, alignment: .top)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedBackup = nil
                    }
            }
        }
    }
    
    @ViewBuilder
    private func placeholderView() -> some View {
        BackupsPlaceholderView()
    }

    @ViewBuilder
    private func encryptedBackupFileView(_ url: URL) -> some View {
        BackupLockedPreviewView(
            isUnlocking: isUnlockingBackupPreview,
            errorMessage: backupPreviewErrorMessage,
            systemUnlockAvailability: systemUnlockAvailability
        ) {
            Task {
                await unlockBackupPreviewWithSystemAuthentication(url)
            }
        } onUseRecoveryKey: {
            isBackupPreviewRecoveryKeySheetPresented = true
        }
    }

    @ViewBuilder
    private func backupEncryptedPreviewLoadingView() -> some View {
        BackupEncryptedPreviewLoadingView(
            isUnlocking: isUnlockingBackupPreview,
            errorMessage: backupPreviewErrorMessage
        )
    }

    @MainActor
    private func loadBackupPreviewWithBackupKey(_ url: URL) async {
        guard selectedFile == url else { return }
        guard !isUnlockingBackupPreview else { return }
        backupPreviewErrorMessage = nil

        isUnlockingBackupPreview = true
        defer { isUnlockingBackupPreview = false }

        do {
            let file = try await backupExcalidrawFile(
                from: url,
                context: viewContext,
                recoveryKey: nil
            )
            guard selectedFile == url else { return }
            unlockedBackupPreview = BackupFilePreview(url: url, file: file)
        } catch {
            guard selectedFile == url else { return }
            backupPreviewErrorMessage = LockedContentErrorPresenter.message(for: error)
        }
    }

    @MainActor
    private func unlockBackupPreviewWithSystemAuthentication(
        _ url: URL,
        isAutomatic: Bool = false
    ) async {
        guard selectedFile == url else { return }
        guard !isUnlockingBackupPreview else { return }
        backupPreviewErrorMessage = nil
        systemUnlockAvailability = LockedContentSystemUnlockStore.availability()

        isUnlockingBackupPreview = true
        defer { isUnlockingBackupPreview = false }

        do {
            let recoveryKey: RecoveryKey
            if let currentRecoveryKey = await RecoveryKeyVault.shared.currentRecoveryKey() {
                recoveryKey = currentRecoveryKey
            } else {
                recoveryKey = try await LockedContentSystemUnlockStore.loadRecoveryKey(
                    reason: LockedContentSystemUnlockReason.previewBackupFile
                )
            }
            try await unlockBackupPreview(url, recoveryKey: recoveryKey)
        } catch let unlockError as LockedContentSystemUnlockError {
            systemUnlockAvailability = LockedContentSystemUnlockStore.availability()
            switch unlockError {
                case .canceled:
                    break
                case .noSavedRecoveryKey:
                    if !isAutomatic {
                        isBackupPreviewRecoveryKeySheetPresented = true
                    }
                default:
                    if !isAutomatic {
                        backupPreviewErrorMessage = LockedContentErrorPresenter.message(for: unlockError)
                    }
            }
        } catch {
            if !isAutomatic {
                backupPreviewErrorMessage = LockedContentErrorPresenter.message(for: error)
            }
        }
    }

    @MainActor
    private func unlockBackupPreview(_ url: URL, recoveryKey: RecoveryKey) async throws {
        guard selectedFile == url else { return }
        let file = try await unlockedEncryptedBackupExcalidrawFile(
            from: url,
            context: viewContext,
            recoveryKey: recoveryKey
        )
        guard selectedFile == url else { return }
        await RecoveryKeyVault.shared.activate(recoveryKey)
        unlockedBackupPreview = BackupFilePreview(url: url, file: file)
        backupPreviewErrorMessage = nil
    }

    @ViewBuilder
    private func backupHomeView(_ backup: URL) -> some View {
        BackupHomeView(
            backup: backup,
            selectedBackupSize: selectedBackupSize,
            isExporting: isExportingBackup
        ) { title in
            Task {
                await exportBackup(backup, title: title)
            }
        } onRevealInFinder: {
#if DEBUG
            NSWorkspace.shared.activateFileViewerSelecting([backup])
#endif
        } onDelete: {
            backupToBeDeleted = backup
        }
    }

    @MainActor
    private func exportBackup(_ backup: URL, title: String) async {
        guard !isExportingBackup else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = title
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let targetURL = panel.url else {
            return
        }

        isExportingBackup = true
        defer { isExportingBackup = false }

        do {
            let recoveryKey: RecoveryKey?
            let containsEncryptedFiles = try await Task.detached(priority: .userInitiated) {
                try backupContainsEncryptedExcalidrawFiles(backup)
            }.value

            if containsEncryptedFiles {
                if let currentRecoveryKey = await RecoveryKeyVault.shared.currentRecoveryKey() {
                    recoveryKey = currentRecoveryKey
                } else {
                    recoveryKey = try await LockedContentSystemUnlockStore.loadRecoveryKey(
                        reason: LockedContentSystemUnlockReason.exportBackup
                    )
                }
            } else {
                recoveryKey = nil
            }

            try await exportBackupRecord(
                from: backup,
                to: targetURL,
                context: viewContext,
                recoveryKey: recoveryKey
            )

            alertToast(.init(
                displayMode: .hud,
                type: .complete(.green),
                title: String(localizable: .generalFileExporterSaved)
            ))
        } catch let unlockError as LockedContentSystemUnlockError where unlockError == .canceled {
            return
        } catch {
            alertToast(error)
        }
    }

    private func loadBackups() {
        do {
            let backupsDir = try getBackupsDir()
            
            let backupDirs: [URL] = try FileManager.default.contentsOfDirectory(
                at: backupsDir,
                includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .creationDateKey]
            )
                .filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
                .sorted(by: {
                    ((try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast)
                })
                        
            self.backups = backupDirs
        } catch {
            alertToast(error)
        }
    }
    
    private func deleteBackup() {
        guard let item = backupToBeDeleted, let index = backups.firstIndex(of: item) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: item)
            backups.remove(at: index)
            selectedBackup = nil
            selectedBackupSize = 0
            selectedBackupDirs = [:]
            selectedFile = nil
            backupToBeDeleted = nil
            route = .dateList
        } catch {
            alertToast(error)
        }
    }
}

#elseif os(iOS)
struct BackupsSettingsView: View {
    var body: some View {
        Text(.localizable(.settingsBackupUnavailableDescription))
    }
}
#endif
#Preview {
    BackupsSettingsView()
}
