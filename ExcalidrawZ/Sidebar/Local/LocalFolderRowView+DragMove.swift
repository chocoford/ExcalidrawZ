//
//  LocalFolderRowView+DragMove.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/14/25.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let excalidrawLocalFolderRow = UTType("com.chocoford.excalidrawLocalFolderRow")!
}


struct LocalFolderRowDragDropModifier: ViewModifier {
    var folder: LocalFolder
    
    init(folder: LocalFolder) {
        self.folder = folder
    }
    

    func body(content: Content) -> some View {
        content
            .modifier(LocalFolderDragModifier(folder: folder))
            .modifier(LocalFolderDropModifier(folder: folder) {.exact($0)})
    }
    
}

struct LocalFolderDragModifier: ViewModifier {
    @EnvironmentObject private var sidebarDragState: ItemDragState

    var folder: LocalFolder

    func body(content: Content) -> some View {
        content
            .opacity(sidebarDragState.currentDragItem == .localFolder(folder.objectID) ? 0.3 : 1)
            .onDrag {
                let url = folder.objectID.uriRepresentation()
                sidebarDragState.currentDragItem = .localFolder(folder.objectID)
                return NSItemProvider(
                    item: url.dataRepresentation as NSData,
                    typeIdentifier: UTType.excalidrawLocalFolderRow.identifier
                )
            }
    }
}


struct LocalFolderDropModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var sidebarDragState: ItemDragState
    @EnvironmentObject private var localFolderState: LocalFolderState
    
    var folder: LocalFolder
    var dropTarget: (ItemDragState.DragItem) -> ItemDragState.GroupDropTarget
    
    @State private var groupIDWillBeDropped: NSManagedObjectID?
    @State private var fileIDWillBeDropped: NSManagedObjectID?
    
    var ancestors: Set<LocalFolder> {
        var result = Set<LocalFolder>()
        var current: LocalFolder? = folder
        while let parent = current?.parent {
            result.insert(parent)
            current = parent
        }
        return result
    }
    
    func body(content: Content) -> some View {
         content
            .modifier(
                SidebarRowDropModifier(
                    allow: [
                        .excalidrawFileRow,
                        .excalidrawGroupRow,
                        .excalidrawLocalFolderRow,
                        .fileURL
                    ],
                    onTargeted: { val in
                        sidebarDragState.currentDropGroupTarget = val
                        ? dropTarget(.localFolder(folder.objectID))
                        : nil
                    },
                    onDrop: { item in
                        fileState.expandToGroup(folder.objectID)
                        
                        switch item {
                            case .group(let groupID):
                                handleDropGroup(id: groupID)
                            case .file(let fileID):
                                handleDropFile(id: fileID)
                            case .localFolder(let folderID):
                                handleDropLocalFolder(id: folderID)
                            case .localFile(let url):
                                handleDropLocalFile(url: url)
                        }
                    }
                )
            )
            .confirmationDialog(
                "Export to disk",
                isPresented: Binding {
                    groupIDWillBeDropped != nil
                } set: {
                    if !$0 {
                        self.groupIDWillBeDropped = nil
                    }
                }
            ) {
                Button {
                    performExportGroupToLocalFolder(id: groupIDWillBeDropped!)
                } label: {
                    Text(.localizable(.generalButtonConfirm))
                }
            } message: {
                Text("This will export the group and its contents to disk.")
            }
            .confirmationDialog(
                "Export to disk",
                isPresented: Binding {
                    fileIDWillBeDropped != nil
                } set: {
                    if !$0 {
                        self.fileIDWillBeDropped = nil
                    }
                }
            ) {
                Button {
                    performExportFileToLocalFolder(id: fileIDWillBeDropped!)
                } label: {
                    Text(.localizable(.generalButtonConfirm))
                }
            } message: {
                Text("This will export the file to disk.")
            }
    }
    
    private func handleDropGroup(id groupID: NSManagedObjectID) {
        self.groupIDWillBeDropped = groupID
    }
    
    private func performExportGroupToLocalFolder(id groupID: NSManagedObjectID) {
        guard let group = viewContext.object(with: groupID) as? Group else {
            return
        }
        
        do {
            try folder.withSecurityScopedURL { scopedURL in
                let fileCoordinator = NSFileCoordinator()
                fileCoordinator.coordinate(
                    writingItemAt: scopedURL,
                    options: .forReplacing,
                    error: nil
                ) { url in
                    do {
                        try group.exportToDisk(folder: url)
                    } catch {
                        alertToast(error)
                    }
                }
            }
        } catch {
            alertToast(error)
        }
        
    }
    
    private func handleDropFile(id fileID: NSManagedObjectID) {
        self.fileIDWillBeDropped = fileID
    }
    
    private func performExportFileToLocalFolder(id fileID: NSManagedObjectID) {
        guard let file = viewContext.object(with: fileID) as? File else {
            return
        }
        
        do {
            try folder.withSecurityScopedURL { scopedURL in
                let fileCoordinator = NSFileCoordinator()
                fileCoordinator.coordinate(
                    writingItemAt: scopedURL,
                    options: .forReplacing,
                    error: nil
                ) { url in
                    file.exportToDisk(folder: url)
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func handleDropLocalFolder(id folderID: NSManagedObjectID) {
        if folderID == folder.objectID { return }
        
        // move folder to this folder
        do {
            try localFolderState.moveLocalFolder(
                folderID,
                to: folder.objectID,
                forceRefreshFiles: true,
                context: viewContext
            )
        } catch {
            alertToast(error)
        }
    }
    
    private func handleDropLocalFile(url: URL) {
        if folder.url == url.deletingLastPathComponent() { return }
        // move file to this folder
        do {
            let mapping = try localFolderState.moveLocalFiles(
                [url],
                to: folder.objectID,
                context: viewContext
            )
            if fileState.currentActiveFile == .localFile(url), let newURL = mapping[url] {
                DispatchQueue.main.async {
                    if let folder = viewContext.object(with: folder.objectID) as? LocalFolder {
                        fileState.currentActiveGroup = .localFolder(folder)
                    }
                    fileState.currentActiveFile = .localFile(newURL)
                    fileState.expandToGroup(folder.objectID)
                }
            }
        } catch {
            alertToast(error)
        }
    }
}
