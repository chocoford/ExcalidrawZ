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
        
    init(file: File, fileIDToBeRenamed: Binding<NSManagedObjectID?>) {
        self.file = file
        self._fileIDToBeRenamed = fileIDToBeRenamed
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
            isSelected: isSelected
        ) {
            fileState.currentFile = file
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
            
            Button {
                do {
                    let newFile = try fileState.duplicateFile(file, context: viewContext)
                    if containerHorizontalSizeClass != .compact {
                        fileState.currentFile = newFile
                    }
                } catch {
                    alertToast(error)
                }
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuDuplicate), systemSymbol: .docOnDoc)
            }
             
            moveFileMenu()
            
            Button {
                copyEntityURLToClipboard(objectID: file.objectID)
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuCopyFileLink), systemSymbol: .link)
            }
            
            Button(role: .destructive) {
                fileState.deleteFile(file)
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuDelete), systemSymbol: .trash)
            }
            
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
            
            Button {
                showPermanentlyDeleteAlert.toggle()
            } label: {
                Label(
                    .localizable(.sidebarFileRowContextMenuDeletePermanently),
                    systemSymbol: .trash
                )
            }
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
        }
    }
    
    private func moveFile(to groupID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let fileID = file.objectID
        let currentFile = fileState.currentFile
        Task.detached {
            do {
                try await context.perform {
                    guard case let group as Group = context.object(with: groupID),
                          case let file as File = context.object(with: fileID) else { return }
                    file.group = group
                    try context.save()
                }
                
                if await file == currentFile {
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
