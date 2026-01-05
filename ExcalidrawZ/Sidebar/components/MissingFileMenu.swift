//
//  MissingFileMenu.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/31/25.
//

import SwiftUI
import CoreData
import SFSafeSymbols
import AlertToast
import ChocofordUI

struct MissingFileMenuProvider: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    

    var files: Set<FileState.ActiveFile>
    var content: (Triggers) -> AnyView

    init<Content: View>(
        files: Set<FileState.ActiveFile>,
        content: @escaping (Triggers) -> Content
    ) {
        self.files = files
        self.content = { AnyView(content($0)) }
    }
    
    struct Triggers {
        var onToggleTryToRecover: () -> Void
        var onToggleDelete: () -> Void
    }
    
    
    var triggers: Triggers {
        Triggers {
            tryToRecoverFiles()
        } onToggleDelete: {
            deleteFiles(files: Array(files))
        }
    }
    
    @State private var showNoRecoveryDialog = false
    @State private var fileToRecover: FileState.ActiveFile?
    @State private var checkpointRecoveryData: CheckpointRecoveryData?

    struct CheckpointRecoveryData: Identifiable {
        let id = UUID()
        let file: FileState.ActiveFile
        let checkpoints: [FileCheckpoint]
    }

    var body: some View {
        content(triggers)
            .sheet(item: $checkpointRecoveryData) { data in
                CheckpointRecoverySheet(
                    file: data.file,
                    checkpoints: data.checkpoints
                )
                .swiftyAlert()
            }
            .confirmationDialog(
                .localizable(.missingFileMenuCannotRecoverAlertButtonDelete),
                isPresented: $showNoRecoveryDialog,
                titleVisibility: .visible
            ) {
                Button(.localizable(.missingFileMenuCannotRecoverAlertButtonDelete), role: .destructive) {
                    if let file = fileToRecover {
                        deleteFiles(files: [file])
                    }
                }
                Button(.localizable(.generalButtonCancel), role: .cancel) { }
            } message: {
                Text(localizable: .missingFileMenuCannotRecoverAlertMessage)
            }
    }

    private func tryToRecoverFiles() {
        // Only process the first file (UI should limit selection to one file)
        guard let file = files.first else { return }

        Task.detached {
            let fileID = file.id

            do {
                // Attempt to recover this file from iCloud
                try await FileStorageManager.shared.attemptRecovery(
                    fileID: fileID
                )

                // Success - show success toast and reset selection
                await MainActor.run {
                    alertToast(
                        AlertToast(
                            displayMode: .hud,
                            type: .complete(.green),
                            title: String(localizable: .generalSuccess)
                        )
                    )
                    fileState.resetSelections()
                }
            } catch {
                // Recovery failed - check if there are checkpoints
                await MainActor.run {
                    fileToRecover = file

                    // Fetch checkpoints for this file
                    let fetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
                    if case .file(let file) = file {
                        fetchRequest.predicate = NSPredicate(format: "file == %@", file)
                    } else if  case .collaborationFile(let file) = file {
                        fetchRequest.predicate = NSPredicate(format: "file == %@", file)
                    } else {
                        showNoRecoveryDialog = true
                        return
                    }
                    fetchRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

                    do {
                        let checkpoints = try viewContext.fetch(fetchRequest)

                        if checkpoints.isEmpty {
                            // No checkpoints available - show deletion dialog
                            showNoRecoveryDialog = true
                        } else {
                            // Checkpoints available - show recovery sheet
                            checkpointRecoveryData = CheckpointRecoveryData(
                                file: file,
                                checkpoints: checkpoints
                            )
                        }
                    } catch {
                        // Failed to fetch checkpoints - show deletion dialog
                        showNoRecoveryDialog = true
                    }
                }
            }
        }
    }

    private func deleteFiles(files: [FileState.ActiveFile]) {
        let fileIDsToDelete: [NSManagedObjectID] = files.compactMap {
            switch $0 {
                case .file(let file): return file.objectID
                case .collaborationFile(let file): return file.objectID
                default: return nil
            }
        }
        Task.detached {
            do {
                for fileID in fileIDsToDelete {
                    try await PersistenceController.shared.fileRepository.delete(
                        fileObjectID: fileID,
                        forcePermanently: false,
                        save: true
                    )
                }
                await MainActor.run {
                    fileState.resetSelections()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}
 
struct MissingFileMenu: View {
    var files: Set<FileState.ActiveFile>
    var label: AnyView

    init<L: View>(
        files: Set<FileState.ActiveFile>,
        @ViewBuilder label: () -> L
    ) {
        self.files = files
        self.label = AnyView(label())
    }

    
    var body: some View {
        MissingFileMenuProvider(files: files) { triggers in
            Menu {
                MissingFileMenuItems(
                    files: files
                ) {
                    triggers.onToggleTryToRecover()
                } onToggleDelete: {
                    triggers.onToggleDelete()
                }
                .labelStyle(.titleAndIcon)
            } label: {
                label
            }
        }
    }
}

struct MissingFileContextMenuModifier: ViewModifier {
    var files: Set<FileState.ActiveFile>

    init(files: Set<FileState.ActiveFile>) {
        self.files = files
    }

    func body(content: Content) -> some View {
        MissingFileMenuProvider(files: files) { triggers in
            content
                .contextMenu {
                    MissingFileMenuItems(
                        files: files
                    ) {
                        triggers.onToggleTryToRecover()
                    } onToggleDelete: {
                        triggers.onToggleDelete()
                    }
                    .labelStyle(.titleAndIcon)
                }
        }
    }
}

struct MissingFileMenuItems: View {
    var files: Set<FileState.ActiveFile>
    var onToogleTryToRecover: () -> Void
    var onToggleDelete: () -> Void

    var body: some View {
        Button {
            onToogleTryToRecover()
        } label: {
            Label(.localizable(.missingFileMenuButtonRecover), systemSymbol: .arrowshapeTurnUpLeft)
        }

        Divider()

        Button(role: .destructive) {
            onToggleDelete()
        } label: {
            Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
                .foregroundStyle(.red)
        }
    }
}

// MARK: - Checkpoint Recovery Sheet

struct CheckpointRecoverySheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) var alertToast

    @EnvironmentObject var fileState: FileState

    var file: FileState.ActiveFile
    var checkpoints: [FileCheckpoint]

    @State private var selectedCheckpoint: FileCheckpoint?

    var body: some View {
        navigationView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(localizable: .missingFileCheckpointRecoverSheetTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(localizable: .missingFileCheckpointRecoverSheetMessage(file.name ?? String(localizable: .generalUnknown)))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Checkpoint List
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(checkpoints, id: \.objectID) { checkpoint in
                            CheckpointRowView(
                                checkpoint: checkpoint,
                                isSelected: selectedCheckpoint?.objectID == checkpoint.objectID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCheckpoint = checkpoint
                            }

                            if checkpoint.objectID != checkpoints.last?.objectID {
                                Divider()
                            }
                        }
                    }
                }

#if os(macOS)
                Divider()

                // Actions
                HStack {
                    Button(.localizable(.generalButtonCancel)) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .modernButtonStyle(style: .glass, shape: .modern)

                    Spacer()

                    recoverButton()
                }
                .padding()
#endif
            }
            .frame(
                minWidth: containerHorizontalSizeClass == .compact ? nil : 600,
                minHeight: containerHorizontalSizeClass == .compact ? nil : 400
            )
#if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ToolbarDismissButton()
                }
                ToolbarItem(placement: .automatic) {
                    recoverButton()
                }
            }
#endif
        }
    }
    
    
    @ViewBuilder
    private func navigationView<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        if #available(macOS 13.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
        }
    }
    
    @ViewBuilder
    private func recoverButton() -> some View {
        AsyncButton(String(localizable: .missingFileCheckpointRecoverSheetButtonRecover)) {
            if let selected = selectedCheckpoint {
                await recoverFromCheckpoint(file: file, checkpoint: selected)
            }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(selectedCheckpoint == nil)
        .modernButtonStyle(style: .glassProminent, shape: .modern)
    }
    
    private func recoverFromCheckpoint(file: FileState.ActiveFile, checkpoint: FileCheckpoint) async {
        do {
            // Load checkpoint content
            let checkpointContent = try await checkpoint.loadContent()

            // Save checkpoint content as the current file content
            _ = try await FileStorageManager.shared.saveContent(
                checkpointContent,
                fileID: file.id,
                type: .file,
                updatedAt: Date()
            )

            await MainActor.run {
                alertToast(
                    AlertToast(
                        displayMode: .hud,
                        type: .complete(.green),
                        title: String(localizable: .missingFileCheckpointRecoverSheetRecoveredToastTitle)
                    )
                )
                fileState.resetSelections()
                dismiss()
            }
        } catch {
            alertToast(error)
        }
    }
}

struct CheckpointRowView: View {
    var checkpoint: FileCheckpoint
    var isSelected: Bool

    @State private var excalidrawFile: ExcalidrawFile?
    @State private var fileSize: Int = 0
    @State private var isLoading = true

    var body: some View {
        HStack(spacing: 12) {
            // Preview thumbnail
            if let excalidrawFile {
                ExcalidrawFileCover(
                    excalidrawFile: excalidrawFile
                )
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemSymbol: .exclamationmarkTriangle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 80, height: 60)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                if let updatedAt = checkpoint.updatedAt {
                    Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                } else {
                    Text(localizable: .generalUnknown)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(.localizable(.checkpointsElementsDescription(excalidrawFile?.elements.count ?? 0)))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text(fileSize.formatted(.byteCount(style: .file)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Selection indicator
            if isSelected {
                Image(systemSymbol: .checkmarkCircleFill)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .onAppear {
            loadCheckpointData()
        }
    }

    private func loadCheckpointData() {
        Task {
            do {
                let content = try await PersistenceController.shared.checkpointRepository.loadCheckpointContent(
                    checkpointObjectID: checkpoint.objectID
                )
                let file = try JSONDecoder().decode(ExcalidrawFile.self, from: content)
                await MainActor.run {
                    self.fileSize = content.count
                    self.excalidrawFile = file
                    self.isLoading = false
                }
            } catch {
                print("Failed to load checkpoint data:", error)
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}
