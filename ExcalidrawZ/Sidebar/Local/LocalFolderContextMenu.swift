//
//  LocalFolderContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/12/25.
//

import SwiftUI
import CoreData
 
struct LocalFolderMenuProvider: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState

    struct Triggers {
        var onToggleRename: () -> Void
        var onToogleCreateSubfolder: () -> Void
        var onToggleRemoveObservation: () -> Void
    }
    
    var folder: LocalFolder
    var content: (Triggers) -> AnyView

    init<Content: View>(
        folder: LocalFolder,
        @ViewBuilder content: @escaping (Triggers) -> Content
    ) {
        self.folder = folder
        self.content = { AnyView(content($0)) }
    }
    
    @State private var newSubfolderName: String = String(localizable: .generalNewFolderName)
    @State private var isRenameSheetPresented = false
    @State private var isCreateSubfolderSheetPresented = false
    @State private var isDeleteConfirmPresented = false

    var triggers: Triggers {
        Triggers {
            isRenameSheetPresented.toggle()
        } onToogleCreateSubfolder: {
            generateNewSubfolderName()
            isCreateSubfolderSheetPresented.toggle()
        } onToggleRemoveObservation: {
            removeObservation()
        }
    }
    
    var body: some View {
        content(triggers)
            .sheet(isPresented: $isCreateSubfolderSheetPresented) {
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
        Task {
            do {
                try await folder.withSecurityScopedURL { scopedURL async throws in
                    let subfolderURL = scopedURL.appendingPathComponent(name, conformingTo: .directory)
                    try await FileCoordinator.shared.coordinatedCreateDirectory(
                        at: subfolderURL,
                        withIntermediateDirectories: false
                    )
                }
                try await MainActor.run {
                    try folder.refreshChildren(context: viewContext)
                    localFolderState.objectWillChange.send()
                    localFolderState.refreshFilesPublisher.send()
                }
            } catch {
                await MainActor.run {
                    alertToast(error)
                }
            }
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
            fileState.setActiveFile(nil)
            fileState.currentActiveGroup = nil
        }
    }

}

struct LocalFolderContextMenuModifier: ViewModifier {
    @EnvironmentObject private var fileState: FileState

    var folder: LocalFolder
    var canExpand: Bool
    var showsSwipeActions: Bool

    init(
        folder: LocalFolder,
        canExpand: Bool,
        showsSwipeActions: Bool = false
    ) {
        self.folder = folder
        self.canExpand = canExpand
        self.showsSwipeActions = showsSwipeActions
    }
    
    @State private var isCreateSubfolderPresented = false
    @State private var newSubfolderName: String = String(localizable: .generalNewFolderName)
    
    func body(content: Content) -> some View {
        LocalFolderMenuProvider(folder: folder) { triggers in
            let menuContent = content
                .contextMenu {
                    LocalFolderMenuItems(
                        folder: folder,
                        canExpand: canExpand
                    ) {
                        triggers.onToogleCreateSubfolder()
                    } onToggleRemoveObservation: {
                        triggers.onToggleRemoveObservation()
                    }
                    .labelStyle(.titleAndIcon)
                }

            if showsSwipeActions, folder.parent == nil {
                menuContent
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            triggers.onToggleRemoveObservation()
                        } label: {
                            Label(
                                .localizable(.sidebarLocalFolderRowContextMenuRemoveObservation),
                                systemSymbol: .trash
                            )
                        }
                        .tint(.red)
                    }
            } else {
                menuContent
            }
        }
    }

}

struct LocalFolderMenuItems: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState

    var folder: LocalFolder
    var canExpand: Bool
    var showsRemoveObservation: Bool
    
    var onToggleCreateSubfolder: () -> Void
    var onToggleRemoveObservation: () -> Void
    
    init(
        folder: LocalFolder,
        canExpand: Bool,
        showsRemoveObservation: Bool = true,
        onToggleCreateSubfolder: @escaping () -> Void,
        onToggleRemoveObservation: @escaping () -> Void,
    ) {
        self.folder = folder
        self.canExpand = canExpand
        self.showsRemoveObservation = showsRemoveObservation
        self.onToggleCreateSubfolder = onToggleCreateSubfolder
        self.onToggleRemoveObservation = onToggleRemoveObservation
    }
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.filePath, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelLocalFolders: FetchedResults<LocalFolder>
    
    
    var isSelected: Bool {
        fileState.currentActiveGroup == .localFolder(folder)
    }
    
    
    var body: some View {
        if canExpand, folder.children?.allObjects.isEmpty == false {
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
        
        SensoryFeedbackButton {
            try copyEntityURLToClipboard(objectID: folder.objectID)
            alertToast(
                .init(
                    displayMode: .hud,
                    type: .complete(.green),
                    title: String(localizable: .exportActionCopied)
                )
            )
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
        
        if showsRemoveObservation || folder.parent != nil {
            Divider()
        }
        
        if folder.parent == nil {
            if showsRemoveObservation {
                Button(role: .destructive) {
                    onToggleRemoveObservation()
                } label: {
                    Label(.localizable(.sidebarLocalFolderRowContextMenuRemoveObservation), systemSymbol: .trash)
                }
            }
        } else {
            Button(role: .destructive) {
                if case .localFile(let file) = fileState.currentActiveFile,
                   file.deletingLastPathComponent() == folder.url {
                    fileState.setActiveFile(nil)
                }
                if let parent = folder.parent {
                    fileState.currentActiveGroup = .localFolder(parent)
                } else {
                    fileState.currentActiveGroup = nil
                }
                Task {
                    do {
                        try await folder.withSecurityScopedURL { scopedURL async throws in
                            _ = try await FileCoordinator.shared.coordinatedTrash(url: scopedURL)
                        }
                        try await MainActor.run {
                            try deleteLocalFolder(folder, context: viewContext)
                            localFolderState.objectWillChange.send()
                            localFolderState.refreshFilesPublisher.send()
                        }
                    } catch {
                        await MainActor.run {
                            alertToast(error)
                        }
                    }
                }
            } label: {
                Label(.localizable(.generalButtonMoveToTrash), systemSymbol: .trash)
            }
        }
    }
    
    @ViewBuilder
    private func moveLocalFileMenu() -> some View {
        Menu {
            ForEach(topLevelLocalFolders) { folder in
                MoveToGroupMenu(
                    destination: folder,
                    sourceGroup: self.folder,
                    childrenSortKey: \LocalFolder.filePath,
                    allowSubgroups: false,
                    canMoveToParentGroup: false
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
        Task {
            do {
                try await localFolderState.moveLocalFolder(
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

}
