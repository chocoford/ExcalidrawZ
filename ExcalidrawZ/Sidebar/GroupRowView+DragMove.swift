//
//  GroupRowView+DragMove.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let excalidrawGroupRow = UTType("com.chocoford.excalidrawGroupRow")!
}

struct GroupRowDragDropModifier: ViewModifier {

    var group: Group
    
    func body(content: Content) -> some View {
        content
            .modifier(GroupRowDragModifier(group: group))
            .modifier(GroupRowDropModifier(
                group: group,
                allow: [
                    .excalidrawFileRow,
                    .excalidrawGroupRow,
                    .excalidrawLocalFolderRow,
                    .fileURL
                ],
                dropTarget: {.exact($0)}
            ))
    }

}

struct GroupRowDragModifier: ViewModifier {
    @EnvironmentObject private var sidebarDragState: ItemDragState

    var group: Group

    func body(content: Content) -> some View {
        if group.groupType == .normal {
            content
                .onDrag {
                    let url = group.objectID.uriRepresentation()
                    sidebarDragState.currentDragItem = .group(group.objectID)
                    return NSItemProvider(
                        item: url.dataRepresentation as NSData,
                        typeIdentifier: UTType.excalidrawGroupRow.identifier
                    )
                }
        } else {
            content
        }
    }
}

struct GroupRowDropModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var sidebarDragState: ItemDragState

    var group: Group
    var allow: [UTType] = [
        .excalidrawFileRow,
        .excalidrawGroupRow,
        .excalidrawLocalFolderRow,
        .fileURL
    ]
    var dropTarget: (ItemDragState.DragItem) -> ItemDragState.GroupDropTarget

    
    @State private var folderWillBeImported: NSManagedObjectID?
    @State private var localFileWillBeImported: URL?
    
    
    func body(content: Content) -> some View {
        content
            .opacity(sidebarDragState.currentDragItem == .group(group.objectID) ? 0.3 : 1)
            .modifier(
                SidebarRowDropModifier(
                    allow: allow,
                    onTargeted: { val in
                        sidebarDragState.currentDropGroupTarget = val
                        ? dropTarget(.group(group.objectID))
                        : nil
                    },
                    onDrop: { item in
                        if case .file = item {
                            fileState.expandToGroup(group.objectID)
                        } else if group.groupType != .trash {
                            fileState.expandToGroup(group.objectID)
                        } else {
                            return
                        }
                        
                        switch item {
                            case .group(let groupID):
                                self.handleDropGroup(id: groupID)
                            case .file(let fileID):
                                self.handleDropFile(id: fileID)
                            case .localFolder(let folderID):
                                self.handleImportFolder(id: folderID)
                            case .localFile(let url):
                                self.handleImportFile(url: url)
                        }
                    }
                )
            )
            .confirmationDialog(
                "Import Folder",
                isPresented: Binding {
                    folderWillBeImported != nil
                } set: { val in
                    if !val {
                        folderWillBeImported = nil
                    }
                }
            ) {
                Button {
                    performImportFolder(id: folderWillBeImported!)
                } label: {
                    Text(.localizable(.generalButtonConfirm))
                }
            } message: {
                Text("This will import the folder and all its contents into this group, and it will be synced with iCloud.")
            }
            .confirmationDialog(
                "Import Local Files",
                isPresented: Binding {
                    localFileWillBeImported != nil
                } set: { val in
                    if !val {
                        localFileWillBeImported = nil
                    }
                }
            ) {
                Button {
                    performImportFile(url: localFileWillBeImported!)
                } label: {
                    Text(.localizable(.generalButtonConfirm))
                }
            } message: {
                Text("This will import the file into this group.")
            }
    }
    
    
    
    private func handleDropFile(id fileID: NSManagedObjectID) {
        // add files to Group
        // or move files to trash
        Task {
            do {
                try await viewContext.perform {
                    guard let file = viewContext.object(with: fileID) as? File else { return }
                    
                    if group.groupType == .trash {
                        file.inTrash = true
                    } else {
                        group.addToFiles(file)
                        file.rank = Int64((group.files?.count ?? 1) - 1)
                    }
                    
                    try viewContext.save()
                }
            } catch {
                alertToast(error)
            }
        }
    }
    
    private func handleDropGroup(id groupID: NSManagedObjectID) {
        if group.groupType == .trash { return }
        if groupID == group.objectID { return }
        Task {
            do {
                try await viewContext.perform {
                    guard let group = viewContext.object(with: groupID) as? Group else { return }
                    self.group.addToChildren(group)
                    
                    group.rank = Int64((self.group.children?.count ?? 1) - 1)
                    
                    try viewContext.save()
                }
            } catch {
                alertToast(error)
            }
        }
    }
    
    private func handleImportFolder(id folderID: NSManagedObjectID) {
        if group.groupType == .trash { return }
        folderWillBeImported = folderID
    }
    
    private func performImportFolder(id folderID: NSManagedObjectID) {
        Task {
            do {
                try await viewContext.perform {
                    guard let folder = viewContext.object(with: folderID) as? LocalFolder else { return }
                    
                    let group = try folder.importToGroup(context: viewContext)
                    group.parent = self.group
                    
                    withAnimation(.smooth) {
                        viewContext.insert(group)
                    }
                    
                    try viewContext.save()
                }
            } catch {
                alertToast(error)
            }
        }
    }
    
    private func handleImportFile(url: URL) {
        if group.groupType == .trash { return }
        localFileWillBeImported = url
    }
    
    private func performImportFile(url: URL) {
        // import file to this group
        Task {
            do {
                try await viewContext.perform {
                    let file = try File(url: url, context: viewContext)
                    file.group = self.group
                    
                    withAnimation(.smooth) {
                        viewContext.insert(file)
                    }
                    
                    try viewContext.save()
                }
            } catch {
                alertToast(error)
            }
        }
    }
}
