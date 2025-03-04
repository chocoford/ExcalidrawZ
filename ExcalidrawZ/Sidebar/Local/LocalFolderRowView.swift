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
    }
    
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
        
        Button {
            generateNewSubfolderName()
            isCreateSubfolderPresented.toggle()
        } label: {
            Label("Add a subfolder", systemSymbol: .folderBadgePlus)
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
}
