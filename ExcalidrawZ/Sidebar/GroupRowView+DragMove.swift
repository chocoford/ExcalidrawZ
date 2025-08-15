//
//  GroupRowView+DragMove.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct GroupRowDragDropModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var sidebarDragState: SidebarDragState

    var group: Group
    @Binding var shouldHighlight: Bool
    
    @State private var isDragging = false
    
    func body(content: Content) -> some View {
        content
            .onDrag {
                let url = group.objectID.uriRepresentation()
                withAnimation { isDragging = true }
                sidebarDragState.currentDragItem = .group(group.objectID)
                return NSItemProvider(
                    item: url.dataRepresentation as NSData,
                    typeIdentifier: UTType.excalidrawGroupRow.identifier
                )
            }
            .onDrop(
                of: [
                    .excalidrawFileRow,
                    .excalidrawGroupRow,
                    .excalidrawLocalFolderRow,
                    .fileURL
                ],
                delegate: GroupRowDropDelegate(
                    group: group,
                    sortField: $fileState.sortField,
                    shouldHighlight: $shouldHighlight,
                    context: viewContext,
                ) { _ in
                    sidebarDragState.currentDragItem = nil
                    sidebarDragState.currentDropTarget = nil
                    
                    fileState.expandToGroup(group.objectID)
                    
                    // fileState.sortField = .rank
                    
                    isDragging = false
                }
            )
        
//            .background {
//                RoundedRectangle(cornerRadius: 12)
//                    .fill(shouldHighlight ? Color.accentColor : Color.clear)
//            }
//            .foregroundStyle(shouldHighlight ? Color.white : Color.primary)
    }
}

extension UTType {
    static let excalidrawGroupRow = UTType("com.chocoford.excalidrawGroupRow")!
}

struct GroupRowDropDelegate: SidebarRowDropDelegate {
    var group: Group
    @Binding var sortField: ExcalidrawFileSortField
    @Binding var shouldHighlight: Bool
    var context: NSManagedObjectContext
    var onDrop: (NSManagedObjectID) -> Void
    
    // var sortFilesCallback: (_ draggedID: NSManagedObjectID, _ targetID: NSManagedObjectID) -> Void
        
    @State private var draggedFileID: NSManagedObjectID?
    
    func dropEntered(info: DropInfo) {
        // print("dropEntered", group.name ?? "")
        shouldHighlight = true
    }
    
    func dropExited(info: DropInfo) {
        // print("dropExited", group.name ?? "")
        shouldHighlight = false
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        handleDrop(info: info) { item in
            DispatchQueue.main.async {
                switch item {
                    case .group(let groupID):
                        self.handleDropGroup(id: groupID)
                    case .file(let fileID):
                        self.handleDropFile(id: fileID)
                    case .localFolder(let folderID):
                        // import folder to this group
                        break
                    case .localFile(let url):
                        // import file to this group
                        break
                }
            }
        }
        
        Task {
            do {
                NotificationCenter.default.post(name: .didDropFileRow, object: nil)
                try context.save()
            } catch {
                print(error)
            }
        }
        shouldHighlight = false
        
        return true
    }
    
    private func handleDropFile(id fileID: NSManagedObjectID) {
        // add files to Group
        onDrop(fileID)
        Task {
            do {
                try await context.perform {
                    guard let file = context.object(with: fileID) as? File else { return }
                    group.addToFiles(file)
                    
                    file.rank = Int64((group.files?.count ?? 1) - 1)
                    
                    try context.save()
                }
            } catch {
                print(error)
            }
        }
    } 
    
    private func handleDropGroup(id groupID: NSManagedObjectID) {
        onDrop(groupID)
        if groupID == group.objectID { return }
        Task {
            do {
                try await context.perform {
                    guard let group = context.object(with: groupID) as? Group else { return }
                    self.group.addToChildren(group)
                    
                    group.rank = Int64((self.group.children?.count ?? 1) - 1)
                    
                    try context.save()
                }
            } catch {
                print(error)
            }
        }
    }
}
