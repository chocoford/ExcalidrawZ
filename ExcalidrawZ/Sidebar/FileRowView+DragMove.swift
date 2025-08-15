//
//  FileRow+DragMove.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/27/25.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

protocol DragMovableFile: NSManagedObject {
    var rank: Int64 { get set }
    var updatedAt: Date? { get set }
    var createdAt: Date? { get set }
    var name: String? { get set }
    var group: Group? { get set }
}

extension File: DragMovableFile {}
extension CollaborationFile: DragMovableFile {
    var group: Group? {
        get { nil }
        set { }
    }
}

@available(macOS 13.0, *)
struct FileRowTransferable: Transferable {
    var objectID: NSManagedObjectID?
    
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { item in
            item.objectID?.uriRepresentation() ?? URL(fileURLWithPath: "/dev/null")
        } importing: { uri in
            FileRowTransferable(
                objectID: PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: uri)
            )
        }
    }
}

extension Notification.Name {
    static let didDropFileRow = Notification.Name("DidDropFileRow")
}

extension UTType {
    static let excalidrawFileRow = UTType("com.chocoford.excalidrawFileRow")!
}

struct FileRowDragDropModifier<DraggableFile: DragMovableFile>: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var sidebarDragState: SidebarDragState
    
    var file: DraggableFile
    var files: FetchedResults<DraggableFile>
    
    init(file: File, files: FetchedResults<File>) where DraggableFile == File {
        self.file = file
        self.files = files
    }
        
    init(file: CollaborationFile, files: FetchedResults<CollaborationFile>) where DraggableFile == CollaborationFile {
        self.file = file
        self.files = files
    }
    
    @State private var isDragging = false

    func body(content: Content) -> some View {
        if #available(macOS 13.0, iOS 16.0, *), false {
            // No
//            content
//                .draggable(FileRowTransferable(objectID: file.objectID))
//                .dropDestination(for: FileRowTransferable.self) { items, location in
//                    for item in items {
//                        guard let objectID = item.objectID else { continue }
//                        sortFiles(
//                            draggedItemID: objectID,
//                            drop: file.objectID,
//                            files: files.map{$0},
//                            context: viewContext
//                        ) {
//                            if fileState.sortField != .rank {
//                                withAnimation {
//                                    fileState.sortField = .rank
//                                }
//                            }
//                        }
//                    }
//                    return true
//                } isTargeted: { isEntered in
//                    if isEntered {
//                        
//                    }
//                }
        } else {
            content
                .opacity(isDragging ? 0.3 : 1)
                .contentShape(Rectangle())
                .onDrag {
                    let url = file.objectID.uriRepresentation()
                    print("onDrag", url)
                    withAnimation { isDragging = true }
                    sidebarDragState.currentDragItem = .file(file.objectID)
                    return NSItemProvider(
                        item: url.dataRepresentation as NSData,
                        typeIdentifier: UTType.excalidrawFileRow.identifier
                    )
                }
                .overlay {
                    if sidebarDragState.currentDropTarget != nil {
                        VStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [.excalidrawFileRow],
                                    delegate: FileRowDropDelegate(
                                        item: file,
                                        onEntered: {
                                            if let index = files.firstIndex(of: file) {
                                                if index > 0 {
                                                    sidebarDragState.currentDropTarget = .after(.file(files[index-1].objectID))
                                                } else if let group = file.group {
                                                    sidebarDragState.currentDropTarget = .startOfGroup(.group(group.objectID))
                                                }
                                            }
                                        },
                                        onLeave: {
                                            sidebarDragState.currentDropTarget = nil
                                        },
                                        onDrop: { draggedItemID in
                                            DispatchQueue.main.async {
                                                sidebarDragState.currentDropTarget = nil
                                                sidebarDragState.currentDragItem = nil
                                                if let index = files.firstIndex(of: file) {
                                                    self.sortFiles(
                                                        draggedItemID: draggedItemID,
                                                        droppedTargt: {
                                                            if index > 0 {
                                                                return .after(.file(files[index-1].objectID))
                                                            } else if let group = file.group {
                                                                return .startOfGroup(.group(group.objectID))
                                                            } else {
                                                                return .after(.file(file.objectID))
                                                            }
                                                        }(),
                                                        files: files.map{$0},
                                                        context: viewContext
                                                    )
                                                }
                                            }
                                        }
                                    ),
                                )
                                .simultaneousGesture(TapGesture().onEnded {
                                    sidebarDragState.currentDragItem = nil
                                    sidebarDragState.currentDropTarget = nil
                                })
                            
                            Color.clear
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [.excalidrawFileRow],
                                    delegate: FileRowDropDelegate(
                                        item: file,
                                        onEntered: {
                                            if let index = files.firstIndex(of: file) {
                                                sidebarDragState.currentDropTarget = .after(.file(files[index].objectID))
                                            }
                                        },
                                        onLeave: {
                                            sidebarDragState.currentDropTarget = nil
                                        },
                                        onDrop: { draggedItemID in
                                            DispatchQueue.main.async {
                                                sidebarDragState.currentDropTarget = nil
                                                sidebarDragState.currentDragItem = nil
                                                self.sortFiles(
                                                    draggedItemID: draggedItemID,
                                                    droppedTargt: .after(.file(file.objectID)),
                                                    files: files.map{$0},
                                                    context: viewContext
                                                )
                                            }
                                        }
                                    )
                                )
                                .simultaneousGesture(TapGesture().onEnded {
                                    sidebarDragState.currentDragItem = nil
                                    sidebarDragState.currentDropTarget = nil
                                })
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if sidebarDragState.currentDropTarget == .after(.file(file.objectID)) {
                        DropTargetPlaceholder()
                            
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didDropFileRow)) { output in
                    withAnimation {
                        self.isDragging = false
                    }
                }
        }
    }
    
    /// Drop to the position before the target file.
    private func sortFiles<DragFile: DragMovableFile>(
        draggedItemID draggedObjectID: NSManagedObjectID,
        droppedTargt target: SidebarDragState.DropTarget,
        files allFiles: [DragFile],
        context: NSManagedObjectContext,
        completionHandler: (() -> Void)? = nil
    ) {
        // guard itemID != draggedObjectID else { return }
        Task { [context, allFiles] in
            try await context.perform {
                guard let draggedFile = context.object(with: draggedObjectID) as? DragFile else {
                    return
                }
                switch target {
                    case .after(let item):
                        guard case .file(let itemID) = item,
                              let targetFile = context.object(with: itemID) as? DragFile else {
                            return
                        }
                        // update rank
                        guard let toIndex = allFiles.firstIndex(of: targetFile) else {
                            return
                        }
                        
                        
                        if let fromIndex = allFiles.firstIndex(of: draggedFile) {
                            // In Group Drag
                            if fromIndex == toIndex { return }
                            
                            withAnimation {
                                /// If  move up to a certain cell, it is always considered that you are moving to the cell above it.
                                /// And vice versa.
                                if fromIndex < toIndex { // Move down ⬇️
                                    for (i, file) in allFiles.enumerated() {
                                        if i < fromIndex {
                                            file.rank = Int64(i)
                                        } else if i <= toIndex {
                                            file.rank = Int64(i-1)
                                        } else {
                                            file.rank = Int64(i)
                                        }
                                    }
                                    draggedFile.rank = Int64(toIndex)
                                } else if toIndex < fromIndex  { // Move up ⬆️
                                    for (i, file) in allFiles.enumerated() {
                                        if i <= toIndex {
                                            file.rank = Int64(i)
                                        } else if i <= fromIndex {
                                            file.rank = Int64(i+1)
                                        } else {
                                            file.rank = Int64(i)
                                        }
                                    }
                                    draggedFile.rank = Int64(toIndex+1)
                                }
                                
                                print("perfrom rank. \(fromIndex) -> \(toIndex)")
                            }
                        } else {
                            withAnimation {
                                // Not in Group Drag
                                for (i, file) in allFiles.enumerated() {
                                    if i > toIndex {
                                        file.rank = Int64(i+1)
                                    }
                                }
                                draggedFile.group = targetFile.group
                                draggedFile.rank = Int64(toIndex+1)
                                
                                if let group = targetFile.group {
                                    fileState.expandToGroup(group.objectID)
                                }
                            }
                        }
                        
                        
                    case .startOfGroup(let item):
                        guard case .group(let groupID) = item else { return }
                        if draggedFile.group?.objectID == groupID,
                           let fromIndex = allFiles.firstIndex(of: draggedFile),
                           fromIndex == 0 {
                            return
                        }
                        
                        withAnimation {
                            for (i, file) in allFiles.enumerated() {
                                if let fromIndex = allFiles.firstIndex(of: draggedFile),
                                   i > fromIndex {
                                    file.rank = Int64(i)
                                } else {
                                    file.rank = Int64(i+1)
                                }
                            }
                            draggedFile.rank = Int64(0)
                            
                            if let group = context.object(with: groupID) as? Group {
                                draggedFile.group = group
                                fileState.expandToGroup(group.objectID)
                            }
                            
                        }
                        
                }
                
                fileState.sortField = .rank

                try context.save()
            }
            
            await MainActor.run {
                completionHandler?()
            }
        }
    }
}

fileprivate struct NotFoundError: Error {}

struct FileRowDropDelegate<File: DragMovableFile>: DropDelegate {
    let item: File
    // @Binding var sortField: ExcalidrawFileSortField
    // var sortFilesCallback: (_ draggedID: NSManagedObjectID, _ targetID: NSManagedObjectID) -> Void
    var onEntered: () -> Void
    var onLeave: () -> Void
    var onDrop: (_ draggedItemID: NSManagedObjectID) -> Void

    let context = PersistenceController.shared.container.viewContext
    
    @State private var draggedFileID: NSManagedObjectID?
    
    func dropEntered(info: DropInfo) { onEntered() }
    func dropExited(info: DropInfo) { onLeave() }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        NotificationCenter.default.post(name: .didDropFileRow, object: nil)
        let container = PersistenceController.shared.container
        for provider in info.itemProviders(for: [UTType.excalidrawFileRow]) {
            provider.loadItem(
                forTypeIdentifier: UTType.excalidrawFileRow.identifier
            ) { item, error in
                if let error {
                    print(error)
                    return
                }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                print("Load Item: \(url)")
                guard url.scheme == "x-coredata",
                      let draggedObjectID = container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url) else {
                    return
                }
                onDrop(draggedObjectID)
            }
        }
        
        return true
    }
    
    
}

// only for cancel
struct FileListDropDelegate: DropDelegate {
    func dropExited(info: DropInfo) {
        NotificationCenter.default.post(name: .didDropFileRow, object: nil)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    func performDrop(info: DropInfo) -> Bool {
        NotificationCenter.default.post(name: .didDropFileRow, object: nil)
        return true
    }
}

struct DropTargetPlaceholder: View {
    @Environment(\.diclosureGroupDepth) private var depth

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 5, height: 5)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .frame(height: 5)
        .padding(.leading, 14 + CGFloat(depth+1) * 8)
    }
}

extension View {
    @MainActor @ViewBuilder
    func fileListDropFallback() -> some View {
        onDrop(of: [.url], delegate: FileListDropDelegate())
    }
}
