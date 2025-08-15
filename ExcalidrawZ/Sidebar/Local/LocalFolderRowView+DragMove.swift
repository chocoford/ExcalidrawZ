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
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var sidebarDragState: SidebarDragState
    @EnvironmentObject private var localFolderState: LocalFolderState

    var folder: LocalFolder
    @Binding var shouldHighlight: Bool
    
    @State private var isDragging = false
    
    func body(content: Content) -> some View {
        content
            .onDrag {
                let url = folder.objectID.uriRepresentation()
                withAnimation { isDragging = true }
                sidebarDragState.currentDragItem = .localFolder(folder.objectID)
                return NSItemProvider(
                    item: url.dataRepresentation as NSData,
                    typeIdentifier: UTType.excalidrawLocalFolderRow.identifier
                )
            }
            .onDrop(
                of: [
                    .excalidrawFileRow,
                    .excalidrawGroupRow,
                    .excalidrawLocalFolderRow,
                    .fileURL
                ],
                delegate: LocalFolderRowDropDelegate(
                    folder: folder,
                    sortField: $fileState.sortField,
                    isTargeted: $shouldHighlight,
                ) { dragItem in
                    sidebarDragState.currentDragItem = nil
                    sidebarDragState.currentDropTarget = nil
                    
                    fileState.expandToGroup(folder.objectID)
                    
                    switch dragItem {
                        case .group(let groupID):
                            /// move group to this folder
                            /// --> export group to this folder
                            break
                        case .file(let fileID):
                            /// export
                            break
                        case .localFolder(let folderID):
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
                        case .localFile(let url):
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
                            break
                    }
                    
                    
                    isDragging = false
                }
            )

    }
    
}

protocol SidebarRowDropDelegate: DropDelegate { }
extension SidebarRowDropDelegate {
    func handleDrop(info: DropInfo, onDrop: @escaping (SidebarDragState.DragItem) -> Void) {
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
                    onDrop(.file(draggedObjectID))
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

struct LocalFolderRowDropDelegate: SidebarRowDropDelegate {
    var folder: LocalFolder
    @Binding var sortField: ExcalidrawFileSortField
    @Binding var isTargeted: Bool
    var onDrop: (SidebarDragState.DragItem) -> Void
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    func performDrop(info: DropInfo) -> Bool {
        handleDrop(info: info) { item in
            DispatchQueue.main.async {
                self.onDrop(item)
            }
        }
        
        isTargeted = false
        return true
    }
    
}
