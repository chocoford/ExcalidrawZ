//
//  SidebarRowDropModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/18/25.
//

import SwiftUI
import UniformTypeIdentifiers

protocol SidebarRowDropable: DropDelegate { }
extension SidebarRowDropable {
    func handleDrop(info: DropInfo, onDrop: @escaping (ItemDragState.DragItem) -> Void) {
        Task {
            for provider in info.itemProviders(
                for: [
                    .excalidrawFileRow,
                    .excalidrawGroupRow,
                    .excalidrawLocalFolderRow,
                    .fileURL
                ]
            ) {
                // handle drop file
                if let data = try? await provider.loadItem(
                    forTypeIdentifier: UTType.excalidrawFileRow.identifier
                ) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.scheme == "x-coredata",
                   let draggedObjectID = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url) {
                    let context = PersistenceController.shared.container.viewContext
                    if let file = context.object(with: draggedObjectID) as? File {
                        onDrop(.file(draggedObjectID))
                    } else if let file = context.object(with: draggedObjectID) as? CollaborationFile {
                        onDrop(.collaborationFile(draggedObjectID))
                    }
                }
                
                // handle drop group
                if let data = try? await provider.loadItem(
                    forTypeIdentifier: UTType.excalidrawGroupRow.identifier
                ) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.scheme == "x-coredata",
                   let draggedObjectID = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url) {
                    onDrop(.group(draggedObjectID))
                }
                
                // handle drop local folder
                if let data = try? await provider.loadItem(
                    forTypeIdentifier: UTType.excalidrawLocalFolderRow.identifier
                ) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.scheme == "x-coredata",
                   let draggedObjectID = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url) {
                    onDrop(.localFolder(draggedObjectID))
                }
                
                // handle drop url
                if let data = try? await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier
                ) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.isFileURL == true {
                    if url.isDirectory {
                        
                    } else {
                        onDrop(.localFile(url))
                    }
                }
                
            }
        }
    }
}

struct SidebarRowDropDelegate: SidebarRowDropable {
    var onTargeted: (_ isTargeted: Bool) -> Void
    var onDrop: (ItemDragState.DragItem) -> Void
    
    func dropEntered(info: DropInfo) {
        onTargeted(true)
    }
    func dropExited(info: DropInfo) {
        onTargeted(false)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        handleDrop(info: info) { item in
            DispatchQueue.main.async {
                self.onDrop(item)
            }
        }
        
        onTargeted(false)
        return true
    }
    
}


struct SidebarRowDropModifier: ViewModifier {
    @EnvironmentObject private var sidebarDragState: ItemDragState
    
    var allow: [UTType]
    var onTargeted: (_ isTargeted: Bool) -> Void
    var onDrop: (ItemDragState.DragItem) -> Void
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "parent == nil"))
    private var topLevelFolders: FetchedResults<LocalFolder>

    func body(content: Content) -> some View {
        content
            .onDrop(
                of: allow,
                delegate: SidebarRowDropDelegate(
                    onTargeted: onTargeted,
                    onDrop: { item in
                        sidebarDragState.reset()
                        
                        switch item {
                            case .localFile(let url):
                                if topLevelFolders.contains(where: {
                                    if let folderURL = $0.url {
                                        return url.filePath.contains(folderURL.filePath)
                                    } else {
                                        return false
                                    }
                                }) {
                                    self.onDrop(.localFile(url))
                                } else {
                                    self.onDrop(.temporaryFile(url))
                                }
                            default:
                                self.onDrop(item)
                        }
                    }
                )
            )
    }
}
