//
//  LocalFolderContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/12/25.
//

import SwiftUI
import CoreData
 
struct LocalFolderContextMenuModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    var folder: LocalFolder
    var folderStructStyle: FolderStructureStyle
    var isSelected: Bool
    
    @State private var isCreateSubfolderPresented = false
    @State private var newSubfolderName: String = String(localizable: .generalNewFolderName)
    
    func body(content: Content) -> some View {
        content
            .contextMenu {
                LocalFolderContextMenu(
                    folder: folder,
                    folderStructStyle: folderStructStyle,
                    isSelected: isSelected
                ) {
                    generateNewSubfolderName()
                    isCreateSubfolderPresented.toggle()
                } onDelete: {
                    removeObservation()
                }
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
            }
        } catch {
            alertToast(error)
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
                // LocalFolder creation will be in FSEventStream...
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
        
        if case .localFolder(let localFoder) = fileState.currentActiveGroup, localFoder == folder {
            fileState.currentActiveFile = nil
            fileState.currentActiveGroup = nil
        }
    }

}

struct LocalFolderContextMenu: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState

    var folder: LocalFolder
    var folderStructStyle: FolderStructureStyle
    var isSelected: Bool
    
    var onToggleCreateSubfolder: () -> Void
    var onDelete: () -> Void
    
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.filePath, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelLocalFolders: FetchedResults<LocalFolder>
    
    var body: some View {
        if folderStructStyle == .disclosureGroup, folder.children?.allObjects.isEmpty == false {
            Button {
                self.expandAllSubFolders(folder.objectID)
            } label: {
                Label(.localizable(.sidebarGroupRowContextMenuExpandAll), systemSymbol: .squareFillTextGrid1x2)
            }
        }
        
        moveLocalFileMenu()
        
        Button {
            onToggleCreateSubfolder()
        } label: {
            Label(.localizable(.sidebarLocalFolderRowContextMenuAddSubfolder), systemSymbol: .folderBadgePlus)
        }
        
        Button {
            copyEntityURLToClipboard(objectID: folder.objectID)
        } label: {
            Label(.localizable(.sidebarLocalFolderRowContextMenuCopyFolderLink), systemSymbol: .link)
        }
        
        if let url = self.folder.url {
#if os(macOS)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.filePath, forType: .string)
            } label: {
                Label(.localizable(.sidebarLocalFolderRowContextMenuCopyFolderPath), systemSymbol: .arrowRightDocOnClipboard)
                    .foregroundStyle(.red)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Label(.localizable(.generalButtonRevealInFinder), systemSymbol: .docViewfinder)
                    .foregroundStyle(.red)
            }
#endif
        }
        
        Divider()
        
        if folder.parent == nil {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(.localizable(.sidebarLocalFolderRowContextMenuRemoveObservation), systemSymbol: .trash)
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
                Label(.localizable(.generalButtonMoveToTrash), systemSymbol: .trash)
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
                    allowSubgroups: false
                ) { targetFolderID in
                    moveLocalFolder(to: targetFolderID)
                }
            }
        } label: {
            Label(.localizable(.generalMoveTo), systemSymbol: .trayAndArrowUp)
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
                            let id = subFolder.objectID
                            await MainActor.run {
                                NotificationCenter.default.post(
                                    name: .shouldExpandGroup,
                                    object: id
                                )
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

    private func moveLocalFolder(to targetFolderID: NSManagedObjectID) {
        do {
            try localFolderState.moveLocalFolder(
                self.folder.objectID,
                to: targetFolderID,
                forceRefreshFiles: self.isSelected,
                context: viewContext
            )
            fileState.currentActiveGroup = .localFolder(folder)
        } catch {
            alertToast(error)
        }
    }
}
