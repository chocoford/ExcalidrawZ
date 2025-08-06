//
//  FileContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/6/25.
//

import SwiftUI

struct FileContextMenuModifier: ViewModifier {
    @EnvironmentObject var fileState: FileState
    @Environment(\.alertToast) private var alertToast

    init(file: File) {
        self.file = file
    }
    
    var file: File
    
    @State private var isPermanentlyDeleteAlertPresented = false
    
    func body(content: Content) -> some View {
        content
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
            .contextMenu {
                FileContextMenu(
                    file: file,
                    isPermanentlyDeleteAlertPresented: $isPermanentlyDeleteAlertPresented
                )
                .labelStyle(.titleAndIcon)
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
                        
                        // also delete checkpoints
                        let checkpointsFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
                        checkpointsFetchRequest.predicate = NSPredicate(format: "file = %@", file)
                        let fileCheckpoints = try context.fetch(checkpointsFetchRequest)
                        let objectIDsToBeDeleted = fileCheckpoints.map{$0.objectID}
                        if !objectIDsToBeDeleted.isEmpty {
                            let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: objectIDsToBeDeleted)
                            try context.executeAndMergeChanges(using: batchDeleteRequest)
                        }
                        context.delete(file)
                        try context.save()
                    }
                }
                await fileState.resetSelections()
            } catch {
                await alertToast(error)
            }
            
            await fileState.resetSelections()
        }
    }
}

struct FileContextMenu: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject var fileState: FileState

    var file: File
    @Binding var isPermanentlyDeleteAlertPresented: Bool
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    var topLevelGroups: FetchedResults<Group>
    
    @State private var isRenameSheetPresented = false

    
    var body: some View {
        if !file.inTrash {
            Button {
                // fileIDToBeRenamed = self.file.objectID
                isRenameSheetPresented.toggle()
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
                for file in filesToRecover {
                    fileState.recoverFile(file)
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
                isPermanentlyDeleteAlertPresented.toggle()
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
        let context = PersistenceController.shared.container.newBackgroundContext()
        
        
        if fileState.selectedFiles.isEmpty {
            let fileID = file.objectID
            let currentFileID = fileState.currentFile?.objectID
            
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
                            fileState.currentGroup = group
                            fileState.currentFile = file
                            
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
            let currentFileID = fileState.currentFile?.objectID

            
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
                            fileState.currentGroup = group
                            fileState.currentFile = file
                            
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
                
                if containerHorizontalSizeClass != .compact {
                    fileState.currentFile = newFile
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
        for selectedFile in filesToBeDelete {
            fileState.deleteFile(selectedFile)
        }
        fileState.resetSelections()
    }
}
