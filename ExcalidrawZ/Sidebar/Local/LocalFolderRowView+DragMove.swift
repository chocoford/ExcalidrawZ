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
    @State private var collborationFileIDWillBeDropped: NSManagedObjectID?
    
    @State private var dropGroupCallback: ((Bool) -> Void)?
    @State private var dropFileCallback: ((Bool) -> Void)?
    @State private var dropCollborationFileCallback: ((Bool) -> Void)?
    
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
                        Task {
                            let success: Bool = await {
                                switch item {
                                    case .group(let groupID):
                                        return await handleDropGroup(id: groupID)
                                    case .file(let fileID):
                                        return await handleDropFile(id: fileID)
                                    case .localFolder(let folderID):
                                        return await handleDropLocalFolder(id: folderID, context: viewContext)
                                    case .localFile(let url):
                                        return await handleDropLocalFile(url: url, context: viewContext)
                                    case .collaborationFile(let roomID):
                                        return await handleDropCollaborationFile(id: roomID)
                                    case .temporaryFile(let url):
                                        return await handleDropTemporaryFile(url: url)
                                }
                            }()
                            
                            if success {
                                fileState.expandToGroup(folder.objectID)
                            }
                        }
                    }
                )
            )
            .sheet(
                isPresented: Binding {
                    groupIDWillBeDropped != nil
                } set: {
                    if !$0 {
                        self.groupIDWillBeDropped = nil
                    }
                }
            ) {
                DropToGroupSheetView(
                    object: groupIDWillBeDropped!,
                    title: .localizable(.dropGroupToLocalFolderConfirmationTitle),
                    message: .localizable(.dropGroupToLocalFolderConfirmationMessage),
                    deleteOldSourceLabel: .localizable(.dropGroupToLocalFolderConfirmationToggleAlsoDeleteSource)
                ) { groupID, delete in
                    Task {
                        let success = await performExportGroupToLocalFolder(id: groupID, delete: delete, context: viewContext)
                        self.dropGroupCallback?(success)
                    }
                } onCancel: {
                    self.dropGroupCallback?(false)
                }
            }
            .sheet(
                isPresented: Binding {
                    fileIDWillBeDropped != nil
                } set: {
                    if !$0 {
                        self.fileIDWillBeDropped = nil
                    }
                }
            ) {
                DropToGroupSheetView(
                    object: fileIDWillBeDropped!,
                    title: .localizable(.dropFileToLocalFolderConfirmationTitle),
                    message: .localizable(.dropFileToLocalFolderConfirmationMessage),
                    deleteOldSourceLabel: .localizable(.dropFileToLocalFolderConfirmationToggleAlsoDeleteSource)
                ) { fileID, delete in
                    Task {
                        let success = await performExportFileToLocalFolder(id: fileID, delete: delete, context: viewContext)
                        self.dropFileCallback?(success)
                    }
                } onCancel: {
                    self.dropGroupCallback?(false)
                }
            }
            .sheet(
                isPresented: Binding {
                    collborationFileIDWillBeDropped != nil
                } set: {
                    if !$0 {
                        self.collborationFileIDWillBeDropped = nil
                    }
                }
            ) {
                DropToGroupSheetView(
                    object: collborationFileIDWillBeDropped!,
                    title: "Import collaboration room",
                    message: "",
                    deleteOldSourceLabel: "Also delete the original collaboration room"
                ) { fileID, delete in
                    Task {
                        let success = await performImportCollaborationFile(
                            id: fileID,
                            delete: delete,
                            context: viewContext
                        )
                        self.dropCollborationFileCallback?(success)
                    }
                } onCancel: {
                    self.dropCollborationFileCallback?(false)
                }
            }
    }
    
    private func handleDropGroup(id groupID: NSManagedObjectID) async -> Bool {
        self.groupIDWillBeDropped = groupID
        
        return await withCheckedContinuation { continuation in
            self.dropGroupCallback = {
                continuation.resume(returning: $0)
                DispatchQueue.main.async {
                    self.dropGroupCallback = nil
                }
            }
        }
    }
    
    private func performExportGroupToLocalFolder(
        id groupID: NSManagedObjectID,
        delete: Bool,
        context: NSManagedObjectContext
    ) async -> Bool {
        guard let group = context.object(with: groupID) as? Group else {
            return false
        }
        
        do {
            try await folder.withSecurityScopedURL { scopedURL in
                let fileCoordinator = NSFileCoordinator()
                return await withCheckedContinuation { continuation in
                    fileCoordinator.coordinate(
                        writingItemAt: scopedURL,
                        options: .forReplacing,
                        error: nil
                    ) { url in
                        do {
                            try group.exportToDisk(folder: url)
                            continuation.resume(returning: true)
                        } catch {
                            alertToast(error)
                            continuation.resume(returning: false)
                        }
                    }
                }
            }
            
            if delete {
                try withAnimation {
                    try group.delete(
                        context: context,
                        forcePermanently: true,
                        save: true
                    )
                }
            }
            
            return true
        } catch {
            alertToast(error)
        }
        return false
    }
    
    private func handleDropFile(id fileID: NSManagedObjectID) async -> Bool {
        self.fileIDWillBeDropped = fileID
        
        return await withCheckedContinuation { continuation in
            self.dropFileCallback = {
                continuation.resume(returning: $0)
                DispatchQueue.main.async {
                    self.dropFileCallback = nil
                }
            }
        }
    }
    
    private func performExportFileToLocalFolder(
        id fileID: NSManagedObjectID,
        delete: Bool,
        context: NSManagedObjectContext
    ) async -> Bool {
        guard let file = context.object(with: fileID) as? File else {
            return false
        }
        
        do {
            try await folder.withSecurityScopedURL { (scopedURL: URL) async -> Void in
                let fileCoordinator = NSFileCoordinator()
                fileCoordinator.coordinate(
                    writingItemAt: scopedURL,
                    options: .forReplacing,
                    error: nil
                ) { url in
                    file.exportToDisk(folder: url)
                }
            }
            
            if delete {
                try withAnimation {
                    try file.delete(
                        context: context,
                        forcePermanently: true,
                        save: true
                    )
                }
            }
            
            return true
        } catch {
            alertToast(error)
        }
        
        return false
    }
    
    private func handleDropLocalFolder(
        id folderID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) async -> Bool {
        if folderID == folder.objectID { return false }
        
        // move folder to this folder
        do {
            try localFolderState.moveLocalFolder(
                folderID,
                to: folder.objectID,
                forceRefreshFiles: true,
                context: context
            )
            
            return true
        } catch {
            alertToast(error)
        }
        
        return false
    }
    
    private func handleDropLocalFile(url: URL, context: NSManagedObjectContext) async -> Bool {
        if folder.url == url.deletingLastPathComponent() { return false }
        // move file to this folder
        do {
            let mapping = try LocalFileUtils.moveLocalFiles(
                [url],
                to: folder.objectID,
                context: context
            )
            if fileState.currentActiveFile == .localFile(url), let newURL = mapping[url] {
                DispatchQueue.main.async {
                    if let folder = viewContext.object(with: folder.objectID) as? LocalFolder {
                        fileState.currentActiveGroup = .localFolder(folder)
                    }
                    fileState.currentActiveFile = .localFile(newURL)
                }
            }
            return true
        } catch {
            alertToast(error)
        }
        
        return false
    }
    
    private func handleDropCollaborationFile(id roomID: NSManagedObjectID) async -> Bool {
        self.collborationFileIDWillBeDropped = roomID
        
        return await withCheckedContinuation { continuation in
            self.dropCollborationFileCallback = {
                continuation.resume(returning: $0)
                DispatchQueue.main.async {
                    self.dropCollborationFileCallback = nil
                }
            }
        }
    }
    
    private func performImportCollaborationFile(
        id roomID: NSManagedObjectID,
        delete: Bool,
        context: NSManagedObjectContext
    ) async -> Bool {
        guard let collaborationFile = context.object(with: roomID) as? CollaborationFile else {
            return false
        }
        
        return await withCheckedContinuation { continuation in
            do {
                try collaborationFile.archiveToLocal(
                    group: .localFolder(folder),
                    delete: delete
                ) { error, target in
                    switch target {
                        case .localFile:
                            continuation.resume(returning: true)
                        default:
                            if let error {
                                alertToast(error)
                            }
                            continuation.resume(returning: false)
                    }
                }
            } catch {
                alertToast(error)
            }
        }
    }
    
    
    private func handleDropTemporaryFile(url: URL) async -> Bool {
        let folderID = folder.objectID
        let context = PersistenceController.shared.container.newBackgroundContext()
        do {
            let mapping = try LocalFileUtils.moveLocalFiles(
                [url],
                to: folderID,
                context: context
            )
            
            await MainActor.run {
                if let newURL = mapping[url],
                   fileState.currentActiveFile == .temporaryFile(url) ||
                    fileState.currentActiveGroup == .temporary && fileState.temporaryFiles == [url] {
                    fileState.currentActiveGroup = .localFolder(folder)
                    fileState.currentActiveFile = .localFile(newURL)
                } else {
                    fileState.currentActiveGroup = .localFolder(folder)
                    fileState.currentActiveFile = nil
                }
                fileState.temporaryFiles.removeAll(where: {$0 == url})
            }
            return true
        } catch {
            alertToast(error)
        }
        return false
    }
}
