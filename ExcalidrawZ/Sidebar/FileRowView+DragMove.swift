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
    @Environment(\.alertToast) private var alertToast
    
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
    
    
    @State private var localFileWillBeDropped: (URL, SidebarDragState.FileRowDropTarget)? = nil

    func body(content: Content) -> some View {
        content
            .opacity(sidebarDragState.currentDragItem == .file(file.objectID) ? 0.3 : 1)
            .contentShape(Rectangle())
            .onDrag {
                let url = file.objectID.uriRepresentation()
                sidebarDragState.currentDragItem = .file(file.objectID)
                return NSItemProvider(
                    item: url.dataRepresentation as NSData,
                    typeIdentifier: UTType.excalidrawFileRow.identifier
                )
            }
            .overlay {
                let canDrop = if case .file = sidebarDragState.currentDragItem {
                    true
                } else if case .localFile = sidebarDragState.currentDragItem {
                    true
                } else {
                    false
                }
                
                if canDrop {
                    VStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .modifier(
                                SidebarRowDropModifier(
                                    allow: [.excalidrawFileRow, .fileURL],
                                    onTargeted: { val in
                                        if val {
                                            if let index = files.firstIndex(of: file) {
                                                if index > 0 {
                                                    sidebarDragState.currentDropFileRowTarget = .after(.file(files[index-1].objectID))
                                                } else if let group = file.group {
                                                    sidebarDragState.currentDropFileRowTarget = .startOfGroup(.group(group.objectID))
                                                }
                                            }
                                        } else {
                                            sidebarDragState.currentDropFileRowTarget = nil
                                        }
                                    },
                                    onDrop: { item in
                                        if let index = files.firstIndex(of: file) {
                                            let dropTarget: SidebarDragState.FileRowDropTarget = {
                                                if index > 0 {
                                                    return .after(.file(files[index-1].objectID))
                                                } else if let group = file.group {
                                                    return .startOfGroup(.group(group.objectID))
                                                } else {
                                                    return .after(.file(file.objectID))
                                                }
                                            }()
                                            switch item {
                                                case .file(let fileID):
                                                    self.sortFiles(
                                                        draggedItemID: fileID,
                                                        droppedTargt: dropTarget,
                                                        files: files.map{$0},
                                                        context: viewContext
                                                    )
                                                case .localFile(let url):
                                                    localFileWillBeDropped = (url, dropTarget)
                                                default:
                                                    break
                                            }
                                        }

                                    }
                                )
                            )
                            .simultaneousGesture(TapGesture().onEnded {
                                sidebarDragState.currentDragItem = nil
                                sidebarDragState.currentDropFileRowTarget = nil
                                sidebarDragState.currentDropGroupTarget = nil
                            })
                        
                        Color.clear
                            .contentShape(Rectangle())
                            .modifier(
                                SidebarRowDropModifier(
                                    allow: [
                                        .excalidrawFileRow, .fileURL
                                    ],
                                    onTargeted: { isTargeted in
                                        if isTargeted {
                                            if let index = files.firstIndex(of: file) {
                                                sidebarDragState.currentDropFileRowTarget = .after(.file(files[index].objectID))
                                            }
                                        } else {
                                            sidebarDragState.currentDropFileRowTarget = nil
                                        }
                                    },
                                    onDrop: { item in
                                        switch item {
                                            case .file(let fileID):
                                                self.sortFiles(
                                                    draggedItemID: fileID,
                                                    droppedTargt: .after(.file(file.objectID)),
                                                    files: files.map{$0},
                                                    context: viewContext
                                                )
                                            case .localFile(let url):
                                                localFileWillBeDropped = (url, .after(.file(file.objectID)))
                                            default:
                                                break
                                        }
                                    }
                                )
                            )
                            .simultaneousGesture(TapGesture().onEnded {
                                sidebarDragState.currentDragItem = nil
                                sidebarDragState.currentDropFileRowTarget = nil
                                sidebarDragState.currentDropGroupTarget = nil
                            })
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if sidebarDragState.currentDropFileRowTarget == .after(.file(file.objectID)) {
                    DropTargetPlaceholder()
                }
            }
            .confirmationDialog(
                "Import local file",
                isPresented: Binding {
                    localFileWillBeDropped != nil
                } set: { val in
                    if !val { localFileWillBeDropped = nil }
                }
            ) {
                Button {
                    if let localFileWillBeDropped {
                        performDropLocalFile(payload: localFileWillBeDropped)
                    }
                } label: {
                    Text(.localizable(.generalButtonConfirm))
                }
            } message: {
                Text("This will import the local file to database, and it will be synced with iCloud.")
            }
    }
    
    /// Drop to the position before the target file.
    private func sortFiles<DragFile: DragMovableFile>(
        draggedItemID draggedObjectID: NSManagedObjectID,
        droppedTargt target: SidebarDragState.FileRowDropTarget,
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
    
    private func performDropLocalFile(payload: (URL, SidebarDragState.FileRowDropTarget)) {
        let (url, dropTarget) = payload
        do {
            let newFile = try File(url: url, context: viewContext)
            viewContext.insert(newFile)
            try viewContext.save()
            
            self.sortFiles(
                draggedItemID: newFile.objectID,
                droppedTargt: dropTarget,
                files: files.map{$0},
                context: viewContext
            )
        } catch {
            alertToast(error)
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
