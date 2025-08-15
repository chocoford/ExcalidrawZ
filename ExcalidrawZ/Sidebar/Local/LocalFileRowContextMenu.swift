//
//  LocalFileRowContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/7/25.
//

import SwiftUI

struct LocalFileRowContextMenuModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var localFolderState: LocalFolderState
    
    var file: URL
    
    @State private var isRenameSheetPresented = false
    
    func body(content: Content) -> some View {
        content
            .contextMenu {
                LocalFileRowContextMenu(file: file) {
                    isRenameSheetPresented.toggle()
                }
                .labelStyle(.titleAndIcon)
            }
            .modifier(
                RenameSheetViewModifier(
                    isPresented: $isRenameSheetPresented,
                    name: file.deletingPathExtension().lastPathComponent
                ) { newName in
                    renameFile(newName: newName)
                }
            )
    }
    
    private func renameFile(newName: String) {
        do {
            // find folder
            let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
            fetchRequest.predicate = NSPredicate(format: "filePath == %@", file.deletingLastPathComponent().filePath)
            guard let folder = try viewContext.fetch(fetchRequest).first else { return }
            
            try folder.withSecurityScopedURL { _ in
                let newURL = file.deletingLastPathComponent()
                    .appendingPathComponent(
                        newName,
                        conformingTo: .excalidrawFile
                    )
                try FileManager.default.moveItem(at: file, to: newURL)
                
                // Update local file ID mapping
                ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                ExcalidrawFile.localFileURLIDMapping[file] = nil
                
                // Also update checkpoints
                updateCheckpoints(oldURL: self.file, newURL: newURL)
                
                localFolderState.itemRenamedPublisher.send(newURL.filePath)
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
                    checkpoints.forEach {
                        $0.url = newURL
                    }
                    try context.save()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

struct LocalFileRowContextMenu: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var localFolderState: LocalFolderState

    var file: URL
    var onToggleRename: () -> Void

    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.filePath, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelLocalFolders: FetchedResults<LocalFolder>
    
    

    
    var body: some View {
        // Rename
        Button {
            onToggleRename()
        } label: {
            Label(.localizable(.sidebarFileRowContextMenuRename), systemSymbol: .squareAndPencil)
                .foregroundStyle(.red)
        }
        .disabled(
            fileState.selectedLocalFiles.count > 1 &&
            fileState.selectedLocalFiles.contains(file)
        )


        Button {
            duplicateFile()
        } label: {
            Label(
                .localizable(
                    !fileState.selectedLocalFiles.isEmpty && fileState.selectedLocalFiles.contains(file)
                    ? .sidebarFileRowContextMenuDuplicateFiles(
                        fileState.selectedLocalFiles.count
                    )
                    : .sidebarFileRowContextMenuDuplicate
                ),
                systemSymbol: .docOnDoc
            )
            .foregroundStyle(.red)
        }

        moveLocalFileMenu()
        
#if os(macOS)
        Button {
#if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.file.filePath, forType: .string)
#elseif canImport(UIKit)
            UIPasteboard.general.setObjects([self.file.filePath])
#endif
        } label: {
            Label(.localizable(.sidebarLocalFileRowContextMenuCopyPath), systemSymbol: .arrowRightDocOnClipboard)
                .foregroundStyle(.red)
        }
        .disabled(
            fileState.selectedLocalFiles.count > 1 &&
            fileState.selectedLocalFiles.contains(file)
        )

        Button {
            let filesToReveal: [URL] = if fileState.selectedLocalFiles.contains(file) {
                Array(fileState.selectedLocalFiles)
            } else {
                [file]
            }
            NSWorkspace.shared.activateFileViewerSelecting(filesToReveal)
        } label: {
            Label(
                .localizable(
                    .generalButtonRevealInFinder
                ),
                systemSymbol: .docViewfinder
            )
            .foregroundStyle(.red)
        }
#endif
        Divider()
        
        // Delete
        Button {
            moveToTrash()
        } label: {
            Label(
                .localizable(
                    !fileState.selectedLocalFiles.isEmpty && fileState.selectedLocalFiles.contains(file)
                    ? .generalButtonMoveFilesToTrash(
                        fileState.selectedLocalFiles.count
                    )
                    : .generalButtonMoveToTrash
                ),
                systemSymbol: .trash
            )
            .foregroundStyle(.red)
        }
    }
    
    
    @MainActor @ViewBuilder
    private func moveLocalFileMenu() -> some View {
        if case .localFolder(let currentLocalFolder) = fileState.currentActiveGroup {
            Menu {
                ForEach(topLevelLocalFolders) { folder in
                    MoveToGroupMenu(
                        destination: folder,
                        sourceGroup: currentLocalFolder,
                        childrenSortKey: \LocalFolder.filePath,
                        allowSubgroups: true
                    ) { targetFolderID in
                        moveLocalFile(to: targetFolderID)
                    }
                }
            } label: {
                Label(
                    .localizable(
                        !fileState.selectedLocalFiles.isEmpty && fileState.selectedLocalFiles.contains(file)
                        ? .generalMoveFilesTo(
                            fileState.selectedLocalFiles.count
                        )
                        : .generalMoveTo
                            
                    ),
                    systemSymbol: .trayAndArrowUp
                )
            }
        }
    }
    
    
    private func duplicateFile() {
        let filesToDuplicate: [URL] = if fileState.selectedLocalFiles.contains(file) {
            Array(fileState.selectedLocalFiles)
        } else {
            [file]
        }
        var fileToBeActive: URL? = nil
        
        do {
            guard case .localFolder(let folder) = fileState.currentActiveGroup else { return }
            try folder.withSecurityScopedURL { scopedURL in
                
                for file in filesToDuplicate {
                    
                    let file = try ExcalidrawFile(contentsOf: file)
                    
                    var newFileName = self.file.deletingPathExtension().lastPathComponent
                    while FileManager.default.fileExists(at: scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)) {
                        let components = newFileName.components(separatedBy: "-")
                        if components.count == 2, let numComponent = components.last, let index = Int(numComponent) {
                            newFileName = "\(components[0])-\(index+1)"
                        } else {
                            newFileName = "\(newFileName)-1"
                        }
                    }
                    
                    let newURL = self.file.deletingLastPathComponent().appendingPathComponent(newFileName, conformingTo: .excalidrawFile)
                    
                    let fileCoordinator = NSFileCoordinator()
                    fileCoordinator.coordinate(writingItemAt: newURL, options: .forReplacing, error: nil) { url in
                        do {
                            try file.content?.write(to: url)
                        } catch {
                            alertToast(error)
                        }
                    }
                    
                    if filesToDuplicate.count == 1,
                       filesToDuplicate[0] == self.file {
                        fileToBeActive = newURL
                    }
                }
                if let fileToBeActive {
                    fileState.currentActiveFile = .localFile(fileToBeActive)
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func moveLocalFile(to targetFolderID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let filesToMove: [URL] = if fileState.selectedLocalFiles.contains(file) {
            Array(fileState.selectedLocalFiles)
        } else {
            [file]
        }
        do {
            let mapping = try localFolderState.moveLocalFiles(filesToMove, to: targetFolderID, context: context)
            
            if fileState.currentActiveFile == .localFile(file), let newURL = mapping[file] {
                DispatchQueue.main.async {
                    if let folder = viewContext.object(with: targetFolderID) as? LocalFolder {
                        fileState.currentActiveGroup = .localFolder(folder)
                    }
                    fileState.currentActiveFile = .localFile(newURL)
                    fileState.expandToGroup(targetFolderID)
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func moveToTrash() {
        let filesToDelete: [URL] = if fileState.selectedLocalFiles.contains(file) {
            Array(fileState.selectedLocalFiles)
        } else {
            [file]
        }
//        var fileToBeActive: URL? = nil
        
        
        do {
            if case .localFolder(let folder) = fileState.currentActiveGroup {
                try folder.withSecurityScopedURL { _ in
                    // Item removed will be handled in `LocalFilesListView`
                    let fileCoordinator = NSFileCoordinator()
                    
                    for file in filesToDelete {
                        fileCoordinator.coordinate(
                            writingItemAt: file,
                            options: .forDeleting,
                            error: nil
                        ) { url in
                            do {
                                try FileManager.default.trashItem(
                                    at: url,
                                    resultingItemURL: nil
                                )
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                }
                
                // Should change current local file...
                let folderURL = self.file.deletingLastPathComponent()
                let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.nameKey])
                let file = contents.first(where: {$0.pathExtension == "excalidraw"})
                fileState.currentActiveFile = file == nil ? nil : .localFile(file!)
            }
        } catch {
            alertToast(error)
        }
    }
}
