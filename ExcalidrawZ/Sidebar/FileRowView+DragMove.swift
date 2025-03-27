//
//  FileRow+DragMove.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/27/25.
//

import SwiftUI

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

struct FileRowDragDropModifier<DraggableFile: DragMovableFile>: ViewModifier {
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
        var predicate: NSPredicate? = nil
        self._files = FetchRequest<CollaborationFile>(
            sortDescriptors: sortDescriptors,
            predicate: predicate,
            animation: .smooth
        )
    }
    
    @State private var isDragging = false

    func body(content: Content) -> some View {
        if #available(macOS 13.0, iOS 16.0, *), false {
            content
                .draggable(FileRowTransferable(objectID: file.objectID))
                .dropDestination(for: FileRowTransferable.self) { items, location in
                    true
                }
        } else {
            content
                .opacity(isDragging ? 0.3 : 1)
                .contentShape(Rectangle())
                .onDrag {
                    print("onDrag", file.objectID)
                    withAnimation {
                        isDragging = true
                    }
                    return NSItemProvider(object: file.objectID.uriRepresentation() as NSURL)
                }
                .onDrop(
                    of: [.url],
                    delegate: FileRowDropDelegate(
                        item: file,
                        allFiles: files,
                        sortField: $fileState.sortField
                    )
                )
                .onReceive(NotificationCenter.default.publisher(for: .didDropFileRow)) { output in
                    // print("didDropFileRow", output.object as? NSManagedObjectID, file.objectID)
//                    if let objectID = output.object as? NSManagedObjectID,
//                       objectID == file.objectID {
//
//                        withAnimation {
//                            self.isDragging = false
//                        }
//                    }
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
        for provider in info.itemProviders(for: [.url]) {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url,
                   !url.isFileURL,
                   let objectID = container.persistentStoreCoordinator.managedObjectID(
                    forURIRepresentation: url
                   ),
                   itemID != objectID {
                    Task { [context, allFiles, item] in
                        await context.perform {
                            let file = context.object(with: objectID) as? File
                            if let file {
                                // update rank
                                let fromIndex = allFiles.firstIndex(of: file)!
                                let toIndex = allFiles.firstIndex(of: item)!
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
                                        file.rank = Int64(toIndex)

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
                                        file.rank = Int64(toIndex)
                                    }
                                }
                            }
                        }
                        await MainActor.run {
                            if sortField != .rank {
                                withAnimation {
                                    sortField = .rank
                                }
                            }
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


extension View {
    @MainActor @ViewBuilder
    func fileListDropFallback() -> some View {
        onDrop(of: [.url], delegate: FileListDropDelegate())
    }
}
