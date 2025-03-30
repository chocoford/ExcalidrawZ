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
    var group: Group? { get }
}

extension File: DragMovableFile {}
extension CollaborationFile: DragMovableFile {
    var group: Group? { nil }
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
    
    var file: DraggableFile
    
    @FetchRequest
    private var files: FetchedResults<DraggableFile>
    
    init(file: File, sortField: ExcalidrawFileSortField) where DraggableFile == File {
        self.file = file
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
        var predicate: NSPredicate? = nil
        if let group = file.group {
            predicate = NSPredicate(format: "group = %@ AND inTrash == false", group)
        }
        self._files = FetchRequest<File>(
            sortDescriptors: sortDescriptors,
            predicate: predicate,
            animation: .smooth
        )
    }
        
    init(file: CollaborationFile, sortField: ExcalidrawFileSortField) where DraggableFile == CollaborationFile {
        self.file = file
        let sortDescriptors: [SortDescriptor<CollaborationFile>] = {
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
        self._files = FetchRequest<CollaborationFile>(
            sortDescriptors: sortDescriptors,
            predicate: nil,
            animation: .smooth
        )
    }
    
    @State private var isDragging = false

    func body(content: Content) -> some View {
        if #available(macOS 13.0, iOS 16.0, *), false {
            // No
            content
                .draggable(FileRowTransferable(objectID: file.objectID))
                .dropDestination(for: FileRowTransferable.self) { items, location in
                    for item in items {
                        guard let objectID = item.objectID else { continue }
                        sortFiles(
                            draggedItemID: objectID,
                            droppedItemID: file.objectID,
                            files: files.map{$0},
                            container: PersistenceController.shared.container
                        ) {
                            if fileState.sortField != .rank {
                                withAnimation {
                                    fileState.sortField = .rank
                                }
                            }
                        }
                    }
                    return true
                } isTargeted: { isEntered in
                    if isEntered {
                        
                    }
                }
        } else {
            content
                .opacity(isDragging ? 0.3 : 1)
                .contentShape(Rectangle())
                .onDrag {
                    let url = file.objectID.uriRepresentation()
                    print("onDrag", url)
                    withAnimation { isDragging = true }
//                    return NSItemProvider(object: file.objectID.uriRepresentation() as NSURL)
                    return NSItemProvider(
                        item: url.dataRepresentation as NSData,
                        typeIdentifier: UTType.excalidrawFileRow.identifier
                    )
                }
                .onDrop(
                    of: [.excalidrawFileRow],
                    delegate: FileRowDropDelegate(
                        item: file,
                        allFiles: files,
                        sortField: $fileState.sortField
                    )
                )
                .onReceive(NotificationCenter.default.publisher(for: .didDropFileRow)) { output in
                    withAnimation {
                        self.isDragging = false
                    }
                }
        }
    }
    
    
}

fileprivate struct NotFoundError: Error {}

struct FileRowDropDelegate<File: DragMovableFile>: DropDelegate {
    let item: File
    var allFiles: FetchedResults<File>
    @Binding var sortField: ExcalidrawFileSortField

    let context = PersistenceController.shared.container.viewContext
    
    @State private var draggedFileID: NSManagedObjectID?
    
    func dropEntered(info: DropInfo) {
        print("dropEntered", item.name ?? "")
        performRank(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // print("performDrop", item.name ?? "")
        Task {
            do {
                NotificationCenter.default.post(name: .didDropFileRow, object: nil)
                try context.save()
            } catch {
            }
        }
        return true
    }
    
    private func performRank(info: DropInfo) {
        let itemID = item.objectID
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
                sortFiles(
                    draggedItemID: draggedObjectID,
                    droppedItemID: itemID,
                    files: allFiles.map{$0},
                    container: container
                ) {
                    if sortField != .rank {
                        withAnimation {
                            sortField = .rank
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    private func getDropFile(provider: NSItemProvider) async throws -> File? {
        let itemID = item.objectID
        let context = context
        let objectID: NSManagedObjectID = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let url,
                   !url.isFileURL,
                   let objectID = PersistenceController.shared.container.persistentStoreCoordinator.managedObjectID(
                    forURIRepresentation: url
                   ),
                   itemID != objectID {
                    continuation.resume(returning: objectID)
                    return
                }
                
                continuation.resume(throwing: NotFoundError())
            }
        }
        
        return await context.perform {
            context.object(with: objectID) as? File
        }

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

fileprivate func sortFiles<File: DragMovableFile>(
    draggedItemID draggedObjectID: NSManagedObjectID,
    droppedItemID itemID: NSManagedObjectID,
    files allFiles: [File],
    container: NSPersistentContainer,
    completionHandler: (() -> Void)? = nil
) {
    let context = container.viewContext
    guard itemID != draggedObjectID else { return }
    Task { [context, allFiles] in
        await context.perform {
            let targetFile = context.object(with: itemID) as? File
            let draggedFile = context.object(with: draggedObjectID) as? File
            if let draggedFile, let targetFile {
                // update rank
                let fromIndex = allFiles.firstIndex(of: draggedFile)!
                let toIndex = allFiles.firstIndex(of: targetFile)!
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
                            if i < toIndex {
                                file.rank = Int64(i)
                            } else if i <= fromIndex {
                                file.rank = Int64(i+1)
                            } else {
                                file.rank = Int64(i)
                            }
                        }
                        draggedFile.rank = Int64(toIndex)
                    }
                    
                    print("perfrom rank. \(fromIndex) -> \(toIndex)")
                }
            }
        }
        
        await MainActor.run {
            completionHandler?()
        }
    }
}

extension View {
    @MainActor @ViewBuilder
    func fileListDropFallback() -> some View {
        onDrop(of: [.url], delegate: FileListDropDelegate())
    }
}
