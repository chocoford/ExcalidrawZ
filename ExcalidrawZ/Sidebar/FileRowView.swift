//
//  FileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

import ChocofordUI

struct FileRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
    var file: File
    @Binding var fileIDToBeRenamed: NSManagedObjectID?
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    var topLevelGroups: FetchedResults<Group>
    
    @FetchRequest
    private var files: FetchedResults<File>
    private var sortField: ExcalidrawFileSortField

    init(
        file: File,
        fileIDToBeRenamed: Binding<NSManagedObjectID?>,
        sortField: ExcalidrawFileSortField,
    ) {
        let group = file.group
        let groupType = group?.groupType ?? .normal
        self.file = file
        self._fileIDToBeRenamed = fileIDToBeRenamed
        
        // Files
        let sortDescriptors: [SortDescriptor<File>] = {
            switch sortField {
                case .updatedAt:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse)
                    ]
                case .name:
                    [
                        SortDescriptor(\.name, order: .reverse),
                    ]
                case .rank:
                    [
                        SortDescriptor(\.rank, order: .forward),
                    ]
            }
        }()
        
        self._files = FetchRequest<File>(
            sortDescriptors: sortDescriptors,
            predicate: groupType == .trash ? NSPredicate(
                format: "inTrash == YES"
            ) : NSPredicate(
                format: "group.id == %@ AND inTrash == NO", (group?.id ?? UUID()) as CVarArg
            ),
            animation: .smooth
        )
        self.sortField = sortField
    }
    
    @State private var showPermanentlyDeleteAlert: Bool = false
    
    @FocusState private var isFocused: Bool
    
    var isSelected: Bool {
        fileState.currentFile == file
    }
    
    var body: some View {
        FileRowButton(
            name: (file.name ?? "")/* + " - \(file.rank ?? -1)"*/,
            updatedAt: file.updatedAt,
            isSelected: isSelected,
            isMultiSelected: fileState.selectedFiles.contains(file)
        ) {
            if fileState.selectedFiles.isEmpty {
                fileState.selectedStartFile = nil
            }
            
            if NSEvent.modifierFlags.contains(.shift) {
                // 1. If this is the first shift-click, remember it and select that file.
                if fileState.selectedStartFile == nil {
                    fileState.selectedStartFile = file
                    fileState.selectedFiles.insert(file)
                } else {
                    guard let startFile = fileState.selectedStartFile,
                        let startIdx = files.firstIndex(of: startFile),
                          let endIdx = files.firstIndex(of: file) else {
                        return
                    }
                    let range = startIdx <= endIdx
                        ? startIdx...endIdx
                        : endIdx...startIdx
                    let sliceItems = files[range]
                    let sliceSet = Set(sliceItems)
                    fileState.selectedFiles = sliceSet
                }
            } else if NSEvent.modifierFlags.contains(.command) {
                if fileState.selectedFiles.isEmpty {
                    fileState.selectedStartFile = file
                }
                fileState.selectedFiles.insertOrRemove(file)
            } else {
                fileState.currentFile = file
            }
        }
        .modifier(FileRowDragDropModifier(file: file, sortField: fileState.sortField))
        .contextMenu { listRowContextMenu.labelStyle(.titleAndIcon) }
        .confirmationDialog(
            LocalizedStringKey.localizable(.sidebarFileRowDeletePermanentlyAlertTitle(file.name ?? "")),
            isPresented: $showPermanentlyDeleteAlert
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
    
    // Context Menu
    @MainActor @ViewBuilder
    private var listRowContextMenu: some View {
        if !file.inTrash {
            Button {
                fileIDToBeRenamed = self.file.objectID
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuRename), systemSymbol: .pencil)
            }
            .disabled(!fileState.selectedFiles.isEmpty)
            
            Button {
                do {
                    if fileState.selectedFiles.isEmpty {
                        let newFile = try fileState.duplicateFile(
                            file,
                            context: viewContext
                        )
                        
                        if containerHorizontalSizeClass != .compact {
                            fileState.currentFile = newFile
                        }
                    } else if fileState.selectedFiles.contains(file) {
                        for selectedFile in fileState.selectedFiles {
                            _ = try fileState.duplicateFile(
                                selectedFile,
                                context: viewContext
                            )
                        }
                    }
                } catch {
                    alertToast(error)
                }
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuDuplicate), systemSymbol: .docOnDoc)
            }
            .disabled(
                !fileState.selectedFiles.isEmpty && !fileState.selectedFiles.contains(file)
            )
             
            moveFileMenu()
            
            Button {
                copyEntityURLToClipboard(objectID: file.objectID)
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuCopyFileLink), systemSymbol: .link)
            }
            .disabled(!fileState.selectedFiles.isEmpty)

            Button(role: .destructive) {
                if fileState.selectedFiles.isEmpty {
                    fileState.deleteFile(file)
                } else {
                    for selectedFile in fileState.selectedFiles {
                        fileState.deleteFile(selectedFile)
                    }
                }
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuDelete), systemSymbol: .trash)
            }
            .disabled(
                !fileState.selectedFiles.isEmpty && !fileState.selectedFiles.contains(file)
            )
            
        } else {
            Button {
                fileState.recoverFile(file)
            } label: {
                Label(
                    .localizable(.sidebarFileRowContextMenuRecover),
                    systemSymbol: .arrowshapeTurnUpBackward
                )
                .symbolVariant(.fill)
            }
            
            .disabled(
                !fileState.selectedFiles.isEmpty && !fileState.selectedFiles.contains(file)
            )
            
            Button {
                showPermanentlyDeleteAlert.toggle()
            } label: {
                Label(
                    .localizable(.sidebarFileRowContextMenuDeletePermanently),
                    systemSymbol: .trash
                )
            }
            .disabled(
                !fileState.selectedFiles.isEmpty && !fileState.selectedFiles.contains(file)
            )
        }
    }
    
    @MainActor @ViewBuilder
    private func actions() -> some View {
        HStack {
            if #available(macOS 13.0, *) {
                Image("circle.grid.2x3.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 12)
//                    .draggable(FileLocalizable(fileID: file.id, groupID: file.group!.id!)) {
//                        FileRowView(store: self.store)
//                            .frame(width: 200)
//                            .padding(.horizontal, 4)
//                            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 8))
//                    }
            }
            
            Menu {
                listRowContextMenu
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .resizable()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
            .padding(.horizontal, 4)
        }
//        .opacity(isHovered ? 1 : 0)
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
                Label(.localizable(.sidebarFileRowContextMenuMoveTo), systemSymbol: .trayAndArrowUp)
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
                    
                } catch {
                    await alertToast(error)
                }
            }
        }
    }
    
    private func deleteFilePermanently() {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let fileID = file.objectID
        Task.detached {
            do {
                try await context.perform {
                    guard case let file as File = context.object(with: fileID) else { return }
                    
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
            } catch {
                await alertToast(error)
            }
        }
    }
}

#if DEBUG
//struct FileRowView_Previews: PreviewProvider {
//    static var previews: some View {
//        FileRowView(groups: <#T##FetchedResults<Group>#>, file: <#T##File#>)
//        .frame(width: 200)
//    }
//}
#endif
