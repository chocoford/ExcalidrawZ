//
//  FileContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/6/25.
//

import SwiftUI
import CoreData

struct FileMenuProvider: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    
    var file: File?
    var content: (Triggers) -> AnyView

    init<Content: View>(
        file: File?,
        content: @escaping (Triggers) -> Content
    ) {
        self.file = file
        self.content = { AnyView(content($0)) }
    }
    
    struct Triggers {
        var onToggleRename: () -> Void
        var onTogglePermanentlyDelete: () -> Void
    }
    
    @State private var isRenameSheetPresented = false
    @State private var isPermanentlyDeleteAlertPresented = false
    
    var triggers: Triggers {
        Triggers {
            isRenameSheetPresented.toggle()
        } onTogglePermanentlyDelete: {
            isPermanentlyDeleteAlertPresented.toggle()
        }
    }
    
    private var files: Set<File> {
        if let file {
            if fileState.selectedFiles.contains(file) {
                return fileState.selectedFiles
            }
            return [file]
        }
        return fileState.selectedFiles
    }
    
    var body: some View {
        content(triggers)
            .modifier(
                RenameSheetViewModifier(
                    isPresented: $isRenameSheetPresented,
                    name: self.files.first?.name ?? ""
                ) {
                    guard let file = self.files.first else { return }
                    fileState.renameFile(
                        file.objectID,
                        context: viewContext,
                        newName: $0
                    )
                }
            )
            .confirmationDialog(
                String(localizable: .sidebarFileRowDeletePermanentlyAlertTitle(files.first?.name ?? "")),
                isPresented: $isPermanentlyDeleteAlertPresented
            ) {
                Button(role: .destructive) {
                    deleteFilePermanently()
                } label: {
                    Text(.localizable(.sidebarFileRowDeletePermanentlyAlertButtonConfirm))
                }
            } message: {
                Text(.localizable(.generalCannotUndoMessage))
            }
    }

    private func deleteFilePermanently() {
        let fileIDsToDelete: [NSManagedObjectID] = files.map { $0.objectID }

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

struct FileContextMenuModifier: ViewModifier {
    var file: File

    init(file: File) {
        self.file = file
    }

    func body(content: Content) -> some View {
        FileMenuProvider(file: file) { triggers in
            content
                .contextMenu {
                    FileMenuItems(
                        file: file
                    ) {
                        triggers.onToggleRename()
                    } onTogglePermanentlyDelete: {
                        triggers.onTogglePermanentlyDelete()
                    }
                    .labelStyle(.titleAndIcon)
                }
        }
    }
}

struct FileMenu: View {
    var file: File?
    var label: AnyView

    init<L: View>(
        file: File?,
        @ViewBuilder label: () -> L
    ) {
        self.file = file
        self.label = AnyView(label())
    }

    var body: some View {
        FileMenuProvider(file: file) { triggers in
            Menu {
                FileMenuItems(
                    file: file
                ) {
                    triggers.onToggleRename()
                } onTogglePermanentlyDelete: {
                    triggers.onTogglePermanentlyDelete()
                }
            } label: {
                label
            }
        }

    }
}

struct FileMenuItems: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @EnvironmentObject var fileState: FileState

    var file: File?
    var onToggleRename: () -> Void
    var onTogglePermanentlyDelete: () -> Void

    private var files: Set<File> {
        if let file {
            if fileState.selectedFiles.contains(file) {
                return fileState.selectedFiles
            }
            return [file]
        }
        return fileState.selectedFiles
    }

    private var isSingleFile: Bool {
        !files.isEmpty && files.count == 1
    }

    private var firstFile: File? {
        files.first
    }
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    var topLevelGroups: FetchedResults<Group>

    @State private var copySensoryFeedbackFlag = false
    
    var body: some View {
        if firstFile?.inTrash != true {
            // Open - only for single file
            var isInEditMode: Bool {
#if os(iOS)
                editMode?.wrappedValue == .active
#else
                false
#endif
            }
            
            
            if !isInEditMode,
               let file = firstFile,
               fileState.currentActiveFile != .file(file) {
                Button {
                    if let file = firstFile {
                        fileState.setActiveFile(.file(file))
                    }
                } label: {
                    Label(
                        .localizable(.generalButtonOpen),
                        systemSymbol: .arrowUpRightSquare
                    )
                }
                .disabled(!isSingleFile)
            }
            // Rename - only for single file
            Button {
                onToggleRename()
            } label: {
                Label(
                    .localizable(.sidebarFileRowContextMenuRename),
                    systemSymbol: .squareAndPencil
                )
            }
            .disabled(!isSingleFile)

            // Duplicate - works for single and multiple files
            Button {
                Task {
                    await duplicateFile()
                }
            } label: {
                Label {
                    if #available(macOS 13.0, iOS 16.0, *), files.count > 1 {
                        Text(localizable: .sidebarFileRowContextMenuDuplicateFiles(files.count))
                    } else {
                        Text(localizable: .sidebarFileRowContextMenuDuplicate)
                    }
                } icon: {
                    Image(systemSymbol: .plusSquareOnSquare)
                }
            }
            .disabled(files.isEmpty)

            // Move - works for single and multiple files
            moveFileMenu()

            // Copy file link - only for single file
            SensoryFeedbackButton {
                if let firstFile {
                    try copyEntityURLToClipboard(objectID: firstFile.objectID)
                    copySensoryFeedbackFlag.toggle()
                    alertToast(
                        .init(
                            displayMode: .hud,
                            type: .complete(.green),
                            title: String(localizable: .exportActionCopied)
                        )
                    )
                }
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuCopyFileLink), systemSymbol: .link)
            }
            .disabled(!isSingleFile)

            Divider()
            
            // Delete - works for single and multiple files
            Button(role: .destructive) {
                Task {
                    await deleteFile()
                }
            } label: {
                Label {
                    if #available(macOS 13.0, iOS 16.0, *), files.count > 1 {
                        Text(localizable: .sidebarFileRowContextMenuDeleteFiles(files.count))
                    } else {
                        Text(localizable: .sidebarFileRowContextMenuDelete)
                    }
                } icon: {
                    Image(systemSymbol: .trash)
                }
                .foregroundStyle(.red)
            }
            .disabled(files.isEmpty)
            
        } else if let firstFile, firstFile.inTrash {
            // Recover - works for single and multiple files
            Button {
                let fileIDs = files.map { $0.objectID }
                Task.detached {
                    let context = PersistenceController.shared.container.newBackgroundContext()
                    for fileID in fileIDs {
                        do {
                            try await fileState.recoverFile(fileID: fileID, context: context)
                        } catch {
                            await alertToast(error)
                        }
                    }
                }
            } label: {
                Label {
                    if #available(macOS 13.0, iOS 16.0, *), files.count > 1 {
                        Text(localizable: .sidebarFileRowContextMenuRecoverFiles(files.count))
                    } else {
                        Text(localizable: .sidebarFileRowContextMenuRecover)
                    }
                } icon: {
                    Image(systemSymbol: .arrowshapeTurnUpBackward)
                        .symbolVariant(.fill)
                }
            }

            // Permanently delete - works for single and multiple files
            Button(role: .destructive) {
                onTogglePermanentlyDelete()
            } label: {
                Label {
                    if #available(macOS 13.0, iOS 16.0, *), files.count > 1 {
                        Text(localizable: .sidebarFileRowContextMenuDeleteFilesPermanently(files.count))
                    } else {
                        Text(localizable: .sidebarFileRowContextMenuDeletePermanently)
                    }
                } icon: {
                    Image(systemSymbol: .trash)
                }
                .foregroundStyle(.red)
            }
        }
    }
    
    
    @MainActor @ViewBuilder
    private func moveFileMenu() -> some View {
        if let sourceGroup = firstFile?.group {
            Menu {
                let groups: [Group] = topLevelGroups
                    .filter{ $0.groupType != .trash }
                    .sorted { a, b in
                        a.groupType == .default && b.groupType != .default ||
                        a.groupType == b.groupType && b.groupType == .normal && a.createdAt ?? .distantPast < b.createdAt ?? .distantPast
                    }
                ForEach(groups) { group in
                    MoveToGroupMenu(
                        destination: group,
                        sourceGroup: sourceGroup,
                        childrenSortKey: \Group.name,
                        allowSubgroups: true
                    ) { targetGroupID in
                        moveFile(to: targetGroupID)
                    }
                }
            } label: {
                Label {
                    if #available(macOS 13.0, iOS 16.0, *), files.count > 1 {
                        Text(localizable: .generalMoveFilesTo(files.count))
                    } else {
                        Text(localizable: .generalMoveTo)
                    }
                } icon: {
                    Image(systemSymbol: .trayAndArrowUp)
                }
            }
        }
    }
    
    private func moveFile(to groupID: NSManagedObjectID) {
        let currentFile: File? = if case .file(let currentFile) = fileState.currentActiveFile {
            currentFile
        } else { nil }
        let context = PersistenceController.shared.container.newBackgroundContext()
        let fileIDs = files.map { $0.objectID }
        let currentFileID = currentFile?.objectID

        Task.detached {
            do {
                try await context.perform {
                    guard case let group as Group = context.object(with: groupID) else {
                        return
                    }
                    for fileID in fileIDs {
                        if case let file as File = context.object(with: fileID) {
                            file.group = group
                        }
                    }
                    try context.save()
                }

                let fileID: NSManagedObjectID? = fileIDs.first { $0 == currentFileID }
                if let fileID {
                    await MainActor.run {
                        guard viewContext.object(with: groupID) is Group,
                              case let file as File = viewContext.object(with: fileID) else { return }
                        fileState.setActiveFile(.file(file))
                    }
                }
                await MainActor.run {
                    fileState.resetSelections()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func duplicateFile() async {
        do {
            var lastNewFileID: NSManagedObjectID?
            for selectedFile in files {
                let newFileID = try await fileState.duplicateFile(
                    selectedFile,
                    context: viewContext
                )
                lastNewFileID = newFileID
            }

            // If single file and not compact mode, switch to the new file
            if isSingleFile,
               containerHorizontalSizeClass != .compact,
               let firstFile,
               fileState.currentActiveFile == .file(firstFile),
               let newFileID = lastNewFileID,
               let newFile = viewContext.object(with: newFileID) as? File {
                fileState.setActiveFile(.file(newFile))
            }

            fileState.resetSelections()
        } catch {
            alertToast(error)
        }
    }
    
    private func deleteFile() async {
        do {
            for selectedFile in files {
                try await PersistenceController.shared.fileRepository.delete(
                    fileObjectID: selectedFile.objectID
                )
            }
            try viewContext.save()

            // If the current file was deleted, clear it
            if let firstFile, .file(firstFile) == fileState.currentActiveFile {
                fileState.setActiveFile(nil)
            }

            fileState.resetSelections()
        } catch {
            alertToast(error)
        }
    }
}
