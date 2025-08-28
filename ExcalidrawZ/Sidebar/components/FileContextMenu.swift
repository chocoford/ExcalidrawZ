//
//  FileContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/6/25.
//

import SwiftUI

struct FileContextMenuModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var fileState: FileState
    @Environment(\.alertToast) private var alertToast

    init(file: File) {
        self.file = file
    }
    
    var file: File
    
    @State private var isRenameSheetPresented = false
    @State private var isPermanentlyDeleteAlertPresented = false
    
    func body(content: Content) -> some View {
        content
            .contextMenu {
                FileContextMenu(
                    file: file
                ) {
                    isRenameSheetPresented.toggle()
                } onTogglePermanentlyDelete: {
                    isPermanentlyDeleteAlertPresented.toggle()
                }
                .labelStyle(.titleAndIcon)
            }
            .modifier(
                RenameSheetViewModifier(
                    isPresented: $isRenameSheetPresented,
                    name: self.file.name ?? ""
                ) {
                    fileState.renameFile(
                        self.file.objectID,
                        context: viewContext,
                        newName: $0
                    )
                }
            )
            .confirmationDialog(
                LocalizedStringKey.localizable(.sidebarFileRowDeletePermanentlyAlertTitle(file.name ?? "")),
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
        let fileIDsToDelete: [NSManagedObjectID] = if fileState.selectedFiles.contains(file) {
            fileState.selectedFiles.map {
                $0.objectID
            }
        } else {
            [file.objectID]
        }
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                try await context.perform {
                    for fileID in fileIDsToDelete {
                        guard case let file as File = context.object(with: fileID) else {
                            return
                        }
                        try file.delete(context: context, save: false)
                        try context.save()
                    }
                }
                await MainActor.run {
                    fileState.resetSelections()
                }
            } catch {
                await alertToast(error)
            }
            
            await MainActor.run {
                fileState.resetSelections()
            }
        }
    }
}

struct FileContextMenu: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject var fileState: FileState

    var file: File
    var onToggleRename: () -> Void
    var onTogglePermanentlyDelete: () -> Void
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    var topLevelGroups: FetchedResults<Group>

    var body: some View {
        if !file.inTrash {
            Button {
                onToggleRename()
            } label: {
                Label(
                    .localizable(
                        .sidebarFileRowContextMenuRename
                    ),
                    systemSymbol: .pencil
                )
            }
            .disabled(!fileState.selectedFiles.isEmpty)
            
            Button {
                duplicateFile()
            } label: {
                Label(
                    .localizable(
                        !fileState.selectedFiles.isEmpty && fileState.selectedFiles.contains(file)
                        ? .sidebarFileRowContextMenuDuplicateFiles(fileState.selectedFiles.count)
                        : .sidebarFileRowContextMenuDuplicate
                    ),
                    systemSymbol: .docOnDoc
                )
            }
            
            moveFileMenu()
            
            Button {
                copyEntityURLToClipboard(objectID: file.objectID)
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuCopyFileLink), systemSymbol: .link)
            }
            .disabled(!fileState.selectedFiles.isEmpty)

            Button(role: .destructive) {
                deleteFile()
            } label: {
                Label(.localizable(
                    !fileState.selectedFiles.isEmpty && fileState.selectedFiles.contains(file)
                    ? .sidebarFileRowContextMenuDeleteFiles(fileState.selectedFiles.count)
                    : .sidebarFileRowContextMenuDelete
                ), systemSymbol: .trash)
            }
        } else {
            Button {
                let filesToRecover: [File] = if fileState.selectedFiles.contains(file) {
                    Array(fileState.selectedFiles)
                } else {
                    [file]
                }
                let fileIDs = filesToRecover.map{$0.objectID}
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
                Label(
                    .localizable(
                        !fileState.selectedFiles.isEmpty && fileState.selectedFiles.contains(file)
                        ? .sidebarFileRowContextMenuRecoverFiles(fileState.selectedFiles.count)
                        : .sidebarFileRowContextMenuRecover
                    ),
                    systemSymbol: .arrowshapeTurnUpBackward
                )
                .symbolVariant(.fill)
            }
            
            Button {
                onTogglePermanentlyDelete()
            } label: {
                Label(
                    .localizable(
                        !fileState.selectedFiles.isEmpty && fileState.selectedFiles.contains(file)
                        ? .sidebarFileRowContextMenuDeleteFilesPermanently(fileState.selectedFiles.count)
                        : .sidebarFileRowContextMenuDeletePermanently
                    ),
                    systemSymbol: .trash
                )
            }
        }
    }
    
    
    @MainActor @ViewBuilder
    private func moveFileMenu() -> some View {
        if let sourceGroup = file.group {
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
                Label(
                    .localizable(
                        !fileState.selectedFiles.isEmpty && fileState.selectedFiles.contains(file)
                        ? .generalMoveFilesTo(fileState.selectedFiles.count)
                        : .generalMoveTo
                    ),
                    systemSymbol: .trayAndArrowUp
                )
            }
            .disabled(
                !fileState.selectedFiles.isEmpty && !fileState.selectedFiles.contains(file)
            )
        }
    }
    
    private func moveFile(to groupID: NSManagedObjectID) {
        let currentFile: File? = if case .file(let currentFile) = fileState.currentActiveFile {
            currentFile
        } else { nil }
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        if fileState.selectedFiles.isEmpty {
            let fileID = file.objectID
            let currentFileID = currentFile?.objectID
            
            Task.detached {
                do {
                    try await context.perform {
                        guard case let group as Group = context.object(with: groupID),
                              case let file as File = context.object(with: fileID) else { return }
                        file.group = group
                        try context.save()
                    }
                    
                    if fileID == currentFileID {
                        await MainActor.run {
                            guard case let group as Group = viewContext.object(with: groupID),
                                  case let file as File = viewContext.object(with: fileID) else { return }
                            fileState.currentActiveGroup = .group(group)
                            fileState.currentActiveFile = .file(file)
                            
                            fileState.expandToGroup(group.objectID)
                        }
                    }
                } catch {
                    await alertToast(error)
                }
            }
        } else {
            let fileIDs = fileState.selectedFiles.map {
                $0.objectID
            }
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
                    
                    let fileID: NSManagedObjectID? = if let currentFileID {
                        fileIDs.first { $0 == currentFileID }
                    } else {
                        fileIDs.first
                    }
                    if let fileID {
                        await MainActor.run {
                            guard case let group as Group = viewContext.object(with: groupID),
                                  case let file as File = viewContext.object(with: fileID) else { return }
                            fileState.currentActiveGroup = .group(group)
                            fileState.currentActiveFile = .file(file)
                            
                            fileState.expandToGroup(group.objectID)
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
    }
    
    private func duplicateFile() {
        do {
            if fileState.selectedFiles.contains(file) {
                for selectedFile in fileState.selectedFiles {
                    _ = try fileState.duplicateFile(
                        selectedFile,
                        context: viewContext
                    )
                }
            } else {
                let newFile = try fileState.duplicateFile(
                    file,
                    context: viewContext
                )
                
                if containerHorizontalSizeClass != .compact,
                   fileState.currentActiveFile == .file(file) {
                    fileState.currentActiveFile = .file(newFile)
                }
            }
            fileState.resetSelections()
        } catch {
            alertToast(error)
        }
    }
    
    private func deleteFile() {
        let filesToBeDelete: [File] = if fileState.selectedFiles.contains(file) {
            Array(fileState.selectedFiles)
        } else {
            [file]
        }
        do {
            for selectedFile in filesToBeDelete {
                try selectedFile.delete(context: viewContext, save: false)
            }
            try viewContext.save()
            
            if .file(file) == fileState.currentActiveFile {
                fileState.currentActiveFile = nil
            }
            
            fileState.resetSelections()
        } catch {
            alertToast(error)
        }
    }
}
