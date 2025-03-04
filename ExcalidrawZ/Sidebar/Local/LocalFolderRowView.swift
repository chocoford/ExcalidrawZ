//
//  LocalFolderRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

import ChocofordUI

struct LocalFolderRowView: View {
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState

    var folder: LocalFolder
    var onDelete: () -> Void
    
    init(
        folder: LocalFolder,
        onDelete: @escaping () -> Void
    ) {
        self.folder = folder
        self.onDelete = onDelete
    }
    
    @State private var isCreateSubfolderPresented = false
    @State private var newSubfolderName: String = "New Folder"

    var isSelected: Bool {
        fileState.currentLocalFolder == folder
//        if let currentLocalFolder = fileState.currentLocalFolder {
//            return currentLocalFolder.url == folder.url
//        } else {
//            return false
//        }
    }
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.filePath, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelLocalFolders: FetchedResults<LocalFolder>
    
    var body: some View {
        content()
            .contextMenu {
                contextMenu()
                    .labelStyle(.titleAndIcon)
            }
            .sheet(isPresented: $isCreateSubfolderPresented) {
                CreateGroupSheetView(
                    name: $newSubfolderName,
                    createType: .localFolder
                ) { name in
                    createSubfolder(name: name)
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if folderStructStyle == .disclosureGroup {
            Label(folder.url?.lastPathComponent ?? "Unknwon", systemSymbol: .folder)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
        } else {
            Button {
                fileState.currentLocalFolder = folder
            } label: {
                Label(folder.url?.lastPathComponent ?? "Unknwon", systemSymbol: .folder)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ListButtonStyle(selected: isSelected))
        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        if folderStructStyle == .disclosureGroup, folder.children?.allObjects.isEmpty == false {
            Button {
                self.expandAllSubFolders(folder.objectID)
            } label: {
                Label("Expand all", systemSymbol: .squareFillTextGrid1x2)
            }
        }
        
        moveLocalFileMenu()
        
        Button {
            generateNewSubfolderName()
            isCreateSubfolderPresented.toggle()
        } label: {
            Label("Add a subfolder", systemSymbol: .folderBadgePlus)
        }
        
        
        if let url = self.folder.url {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.filePath, forType: .string)
            } label: {
                Label("Copy Folder Path", systemSymbol: .arrowRightDocOnClipboard)
                    .foregroundStyle(.red)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label("Reveal in Finder", systemSymbol: .docViewfinder)
                    .foregroundStyle(.red)
            }
        }
        
        Divider()
        
        if folder.parent == nil {
            Button(role: .destructive) {
                removeObservation()
            } label: {
                Label("Remove Observation", systemSymbol: .trash)
            }
        } else {
            
            Button(role: .destructive) {
                do {
                    onDelete()
                    try folder.withSecurityScopedURL { scopedURL in
                        let fileCoordinator = NSFileCoordinator()
                        fileCoordinator.coordinate(
                            writingItemAt: scopedURL,
                            options: .forDeleting,
                            error: nil
                        ) { url in
                            do {
                                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                } catch {
                    alertToast(error)
                }
            } label: {
                Label("Move to Trash", systemSymbol: .trash)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func moveLocalFileMenu() -> some View {
        Menu {
            ForEach(topLevelLocalFolders) { folder in
                MoveToGroupMenu(
                    destination: folder,
                    sourceGroup: self.folder,
                    childrenSortKey: \LocalFolder.filePath,
                    allowSubgroups: true
                ) { targetFolderID in
                    moveLocalFolder(to: targetFolderID)
                }
            }
        } label: {
            Label(.localizable(.sidebarFileRowContextMenuMoveTo), systemSymbol: .trayAndArrowUp)
        }
    }
    
    private func expandAllSubFolders(_ folderID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        NotificationCenter.default.post(name: .shouldExpandGroup, object: folderID)
        Task.detached {
            do {
                try await context.perform {
                    guard let folder = context.object(with: folderID) as? LocalFolder else { return }
                    let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                    fetchRequest.predicate = NSPredicate(format: "parent = %@", folder)
                    let subFolders = try context.fetch(fetchRequest)
                    
                    Task {
                        for subFolder in subFolders {
                            await MainActor.run {
                                NotificationCenter.default.post(name: .shouldExpandGroup, object: subFolder.objectID)
                            }
                            
                            try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.2))
                            
                            await expandAllSubFolders(subFolder.objectID)
                        }
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }

    private func createSubfolder(name: String) {
        do {
            try folder.withSecurityScopedURL { scopedURL in
                let subfolderURL = scopedURL.appendingPathComponent(name, conformingTo: .directory)
                let fileCoordinator = NSFileCoordinator()
                fileCoordinator.coordinate(writingItemAt: subfolderURL, options: .forReplacing, error: nil) { url in
                    do {
                        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                    } catch {
                        alertToast(error)
                    }
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func generateNewSubfolderName() {
        do {
            try folder.withSecurityScopedURL { scopedURL in
                let contents = try FileManager.default.contentsOfDirectory(
                    at: scopedURL,
                    includingPropertiesForKeys: [.nameKey]
                )
                
                while contents.contains(where: {$0.lastPathComponent == newSubfolderName}) {
                    if let dividerIndex = newSubfolderName.lastIndex(of: "-"),
                       let index = Int(newSubfolderName.components(separatedBy: "-").last!) {
                        newSubfolderName = "\(newSubfolderName[newSubfolderName.startIndex..<dividerIndex])-\(index+1)"
                    } else {
                        newSubfolderName = "\(newSubfolderName)-1"
                    }
                }
                debugPrint("[TEST] contents", contents, newSubfolderName)
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func removeObservation() {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let folderID = folder.objectID
        Task.detached {
            do {
                try await context.perform {
                    guard case let folder as LocalFolder = context.object(with: folderID) else { return }
                    // also should delete the subfolders...
                    var allSubfolders: [LocalFolder] = []
                    var fetchIndex = -1
                    var parent = folder
                    while fetchIndex < allSubfolders.count {
                        if fetchIndex > -1 {
                            parent = allSubfolders[fetchIndex]
                        }
                        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                        fetchRequest.predicate = NSPredicate(format: "parent = %@", parent)
                        try allSubfolders.append(contentsOf: context.fetch(fetchRequest))
                        fetchIndex += 1
                    }
                    let batchDeletion = NSBatchDeleteRequest(objectIDs: allSubfolders.map{$0.objectID} + [folder.objectID])
                    
                    try context.executeAndMergeChanges(using: batchDeletion)
                    try context.save()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func moveLocalFolder(to targetFolderID: NSManagedObjectID) {
        guard case let targetFolder as LocalFolder = viewContext.object(with: targetFolderID),
              let targetURL = targetFolder.url,
              let sourceURL = self.folder.url else { return }
        do {
            let isSelected = self.isSelected
            try self.folder.withSecurityScopedURL { sourceURL in
                let newURL: URL = targetURL.appendingPathComponent(
                    sourceURL.lastPathComponent,
                    conformingTo: .directory
                )
                // find all files in sourceURL...
                guard let enumerator = FileManager.default.enumerator(
                    at: sourceURL,
                    includingPropertiesForKeys: []
                ) else {
                    return
                }
                
                for case let file as URL in enumerator {
                    // get the changed folder
                    let relativePath = file.filePath.suffix(from: sourceURL.filePath.endIndex)
                    let fileNewURL = if #available(macOS 13.0, *) {
                        newURL.appending(path: relativePath)
                    } else {
                        newURL.appendingPathComponent(String(relativePath))
                    }
                    
                    // Update local file ID mapping
                    ExcalidrawFile.localFileURLIDMapping[fileNewURL] = ExcalidrawFile.localFileURLIDMapping[file]
                    ExcalidrawFile.localFileURLIDMapping[file] = nil
                    
                    // Also update checkpoints
                    updateCheckpoints(oldURL: file, newURL: fileNewURL)
                }
            }
            
            try targetFolder.withSecurityScopedURL { taretURL in
                let newURL = taretURL.appendingPathComponent(
                    sourceURL.lastPathComponent,
                    conformingTo: .directory
                )
                let fileCoordinator = NSFileCoordinator()
                fileCoordinator.coordinate(writingItemAt: taretURL, options: .forMoving, error: nil) { url in
                    do {
                        try FileManager.default.moveItem(
                            at: sourceURL,
                            to: newURL
                        )
                    } catch {
                        alertToast(error)
                    }
                }
                
                // update LocalFolder
                Task {
                    do {
                        try await viewContext.perform {
                            guard case let folder as LocalFolder = viewContext.object(with: self.folder.objectID) else {
                                return
                            }
                            folder.url = newURL
                            folder.filePath = newURL.filePath
                            folder.bookmarkData = try newURL.bookmarkData(
                                options: .withSecurityScope,
                                includingResourceValuesForKeys: [.nameKey]
                            )
                            folder.parent = targetFolder
//                            print("[DEBUG] update folder done: \(folder.objectID)")
//                            print("[DEBUG] current folder: \(fileState.currentLocalFolder?.objectID)")
//                            print("[DEBUG] current folder == folder? \(fileState.currentLocalFolder == folder)")
                            try viewContext.save()
                        }
                    } catch {
                        alertToast(error)
                    }
                }
                
                if isSelected {
                    DispatchQueue.main.async {
                        localFolderState.objectWillChange.send()
                        localFolderState.refreshFilesPublisher.send()
                    }
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func updateCheckpoints(oldURL: URL, newURL: URL) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                try await context.perform {
                    let fetchRequest = NSFetchRequest<LocalFileCheckpoint>(entityName: "LocalFileCheckpoint")
                    fetchRequest.predicate = NSPredicate(format: "url = %@", oldURL as NSURL)
                    let checkpoints = try context.fetch(fetchRequest)
                    checkpoints.forEach { $0.url = newURL }
                    try context.save()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}
