//
//  GroupRowView+DragMove.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/9/25.
//

import SwiftUI
import UniformTypeIdentifiers

import ChocofordUI

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

    var ancestors: Set<Group> {
        var result = Set<Group>()
        var current: Group? = group
        while let parent = current?.parent {
            result.insert(parent)
            current = parent
        }
        return result
    }
    
    @State private var folderWillBeImported: NSManagedObjectID?
    @State private var localFileWillBeImported: URL?
    @State private var collaborationFileWillBeImported: NSManagedObjectID?
    
    @State private var importFolderSuccessCallback: ((Bool) -> Void)?
    @State private var importLocalFileSuccessCallback: ((Bool) -> Void)?
    @State private var importCollaborationFileSuccessCallback: ((Bool) -> Void)?
    
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
                        Task {
                            let success: Bool = await {
                                switch item {
                                    case .group(let groupID):
                                        return await self.handleDropGroup(id: groupID, context: viewContext)
                                    case .file(let fileID):
                                        return await self.handleDropFile(id: fileID, context: viewContext)
                                    case .localFolder(let folderID):
                                        return await self.handleImportFolder(id: folderID)
                                    case .localFile(let url):
                                        return await self.handleImportFile(url: url)
                                    case .collaborationFile(let roomID):
                                        return await self.handleDropCollaborationFile(id: roomID)
                                    case .temporaryFile(let url):
                                        return await self.handleDropTemporaryFile(url: url)
                                }
                            }()
                            
                            if success {
                                if case .file = item {
                                    fileState.expandToGroup(group.objectID)
                                } else if group.groupType != .trash {
                                    fileState.expandToGroup(group.objectID)
                                } else {
                                    return
                                }
                            }
                        }
                        
                    }
                )
            )
            .sheet(
                isPresented: Binding {
                    folderWillBeImported != nil
                } set: { val in
                    if !val {
                        folderWillBeImported = nil
                    }
                }
            ) {
                DropToGroupSheetView(
                    object: folderWillBeImported!,
                    title: .localizable(.dropLocalFolderToGroupConfirmationTitle),
                    message: .localizable(.dropLocalFolderToGroupConfirmationMessage),
                    deleteOldSourceLabel: .localizable(.dropLocalFolderToGroupConfirmationToggleAlsoDeleteSource)
                ) { folder, delete in
                    Task {
                        let success = await performImportFolder(id: folder, delete: delete, context: viewContext)
                        self.importFolderSuccessCallback?(success)
                    }
                } onCancel: {
                    self.importFolderSuccessCallback?(false)
                }
            }
            .sheet(
                isPresented: Binding {
                    localFileWillBeImported != nil
                } set: { val in
                    if !val {
                        localFileWillBeImported = nil
                    }
                }
            ) {
                DropToGroupSheetView(
                    object: localFileWillBeImported!,
                    title: .localizable(.dropLocalFileToGroupConfirmationTitle),
                    message: .localizable(.dropLocalFileToGroupConfirmationMessage),
                    deleteOldSourceLabel: .localizable(.dropLocalFileToGroupConfirmationToggleAlsoDeleteSource)
                ) { file, delete in
                    Task {
                        let success = await performImportFile(url: file, delete: delete, context: viewContext)
                        self.importLocalFileSuccessCallback?(success)
                    }
                } onCancel: {
                    self.importLocalFileSuccessCallback?(false)
                }
            }
    }
    
    
    
    private func handleDropFile(id fileID: NSManagedObjectID, context: NSManagedObjectContext) async -> Bool {
        // add files to Group
        // or move files to trash
        do {
            try await viewContext.perform {
                guard let file = context.object(with: fileID) as? File else { return }
                
                if group.groupType == .trash && !file.inTrash ||
                    group.groupType != .trash && file.group == self.group { return }
                
                if group.groupType == .trash {
                    file.inTrash = true
                } else {
                    group.addToFiles(file)
                    file.rank = Int64((group.files?.count ?? 1) - 1)
                }
                
                try context.save()
            }
            return true
        } catch {
            alertToast(error)
        }
        return false
    }
    
    private func handleDropGroup(id groupID: NSManagedObjectID, context: NSManagedObjectContext) async -> Bool {
        if group.groupType == .trash { return false }
        if groupID == group.objectID { return false }
        if ancestors.contains(where: {$0.objectID == groupID}) { return false }
        do {
            return try await context.perform {
                guard let group = context.object(with: groupID) as? Group else { return false }
                
                if group == self.group { return false }
                
                self.group.addToChildren(group)
                
                group.rank = Int64((self.group.children?.count ?? 1) - 1)
                
                try context.save()
                
                return true
            }
        } catch {
            alertToast(error)
        }
        return false
    }
    
    private func handleImportFolder(id folderID: NSManagedObjectID) async -> Bool {
        if group.groupType == .trash { return false }
        folderWillBeImported = folderID
        
        return await withCheckedContinuation { continuation in
            self.importFolderSuccessCallback = {
                continuation.resume(returning: $0)
                DispatchQueue.main.async {
                    self.importFolderSuccessCallback = nil
                }
            }
        }
    }
    
    private func performImportFolder(
        id folderID: NSManagedObjectID,
        delete: Bool,
        context: NSManagedObjectContext
    ) async -> Bool {
        do {
            return try await context.perform {
                guard let folder = viewContext.object(with: folderID) as? LocalFolder else { return false }
                
                let group = try folder.importToGroup(context: viewContext, delete: delete)
                group.parent = self.group
                
                withAnimation(.smooth) {
                    context.insert(group)
                }
                
                try context.save()
                
                return true
            }
        } catch {
            alertToast(error)
        }
        return false
    }
    
    private func handleImportFile(url: URL) async -> Bool {
        if group.groupType == .trash { return false }
        localFileWillBeImported = url
        
        return await withCheckedContinuation { continuation in
            self.importLocalFileSuccessCallback = {
                continuation.resume(returning: $0)
                DispatchQueue.main.async {
                    self.importLocalFileSuccessCallback = nil
                }
            }
        }
    }
    
    private func performImportFile(url: URL, delete: Bool, context: NSManagedObjectContext) async -> Bool {
        // import file to this group
        do {
            return try await context.perform {
                let file = try File(url: url, context: context)
                file.group = self.group
                
                withAnimation(.smooth) {
                    context.insert(file)
                }
                
                try context.save()
                
                if delete {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                return true
            }
        } catch {
            alertToast(error)
        }
        return false
    }
    
    private func handleDropCollaborationFile(id roomID: NSManagedObjectID) async -> Bool {
        if group.groupType == .trash { return false }
        collaborationFileWillBeImported = roomID
        return await withCheckedContinuation { continuation in
            self.importCollaborationFileSuccessCallback = {
                continuation.resume(returning: $0)
                DispatchQueue.main.async {
                    self.importCollaborationFileSuccessCallback = nil
                }
            }
        }
    }
    
    private func performImportCollaborationFile(
        id roomID: NSManagedObjectID,
        delete: Bool,
        context: NSManagedObjectContext
    ) async -> Bool {
        // import file to this group
        return await withCheckedContinuation { continuation in
            Task {
                do {
                    try await context.perform {
                        guard let collaborationFile = context.object(with: roomID) as? CollaborationFile else {
                            continuation.resume(returning: false)
                            return
                        }
                        try collaborationFile.archiveToLocal(
                            group: .group(self.group),
                            delete: delete
                        ) { error, target in
                            switch target {
                                case .file(_, let fileID):
                                    if fileState.currentActiveFile?.id == roomID.description {
                                        fileState.currentActiveGroup = .group(self.group)
                                        if let file = viewContext.object(with: fileID) as? File {
                                            fileState.currentActiveFile = .file(file)
                                        } else {
                                            fileState.currentActiveFile = nil
                                        }
                                    }
                                    continuation.resume(returning: true)
                                default:
                                    continuation.resume(returning: false)
                            }
                        }
                    }
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private func handleDropTemporaryFile(url: URL) async -> Bool {
        let groupID = group.objectID
        
        let context = PersistenceController.shared.container.newBackgroundContext()
        do {
            let fileID = try await context.perform {
                let file = try File(url: url, context: context)
                file.group = context.object(with: groupID) as? Group
                withAnimation {
                    context.insert(file)
                }
                try context.save()
                return file.objectID
            }
            
            await MainActor.run {
                guard case let group as Group = viewContext.object(with: groupID) else { return }
                if let file = viewContext.object(with: fileID) as? File ?? group.files?.allObjects.first as? File {
                    if fileState.currentActiveGroup == .temporary && fileState.temporaryFiles == [url] ||
                        fileState.currentActiveFile == .temporaryFile(url) {
                        fileState.currentActiveFile = .file(file)
                        fileState.currentActiveGroup = .group(group)
                    }
                } else {
                    fileState.currentActiveGroup = .group(group)
                    fileState.currentActiveFile = nil
                }
                fileState.temporaryFiles.removeAll(where: {$0 == url})
                fileState.expandToGroup(group.objectID)
            }
            return true
        } catch {
            alertToast(error)
        }
        return false
    }
}


struct DropToGroupSheetView<T: Sendable>: View {
    @AppStorage("AlsoDeleteOldFileOnImport") private var alsoDeleteOldFileOnImport = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    
    var object: T
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var deleteOldSourceLabel: LocalizedStringKey
    var onConfirm: (_ object: T, _ delete: Bool) -> Void
    var onCancel: () -> Void
    
    init(
        object: T,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        deleteOldSourceLabel: LocalizedStringKey,
        onConfirm: @escaping (_ object: T, _ delete: Bool) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.object = object
        self.title = title
        self.message = message
        self.deleteOldSourceLabel = deleteOldSourceLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title2.bold())
            
            Text(message)
                .multilineTextAlignment(.center)
            
            Toggle(deleteOldSourceLabel, isOn: $alsoDeleteOldFileOnImport)

            HStack(spacing: 10) {
                if #available(iOS 26.0, macOS 26.0, *) {
                    Button {
                        dismiss()
                    } label: {
                        Text(.localizable(.generalButtonCancel))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonBorderShape(.capsule)

                    Button {
                        onConfirm(object, alsoDeleteOldFileOnImport)
                        dismiss()
                    } label: {
                        Text(.localizable(.generalButtonConfirm))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text(.localizable(.generalButtonCancel))
                            .frame(maxWidth: .infinity)
                    }
                    
                    Button {
                        onConfirm(object, alsoDeleteOldFileOnImport)
                        dismiss()
                    } label: {
                        Text(.localizable(.generalButtonConfirm))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 360)
        .watchImmediately(of: isPresented) { val in
            print("isPresented: \(val)")
            if val {
                
            }
        }
    }
}
