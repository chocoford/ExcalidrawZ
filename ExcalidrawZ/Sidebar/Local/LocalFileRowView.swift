//
//  LocalFileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/24/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct LocalFileRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
    var file: URL
    var updateFlag: Date?
    
    init(file: URL, updateFlag: Date?) {
        self.file = file
        self.updateFlag = updateFlag
    }
    
    @State private var modifiedDate: Date = .distantPast
    
    @State private var isRenameSheetPresented = false
    @State private var isDeleteConfirmationDialogPresented = false
    
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.filePath, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelLocalFolders: FetchedResults<LocalFolder>
    
    var body: some View {
        Button {
            fileState.currentLocalFile = file
        } label: {
            FileRowLabel(
                name: file.deletingPathExtension().lastPathComponent,
                updatedAt: modifiedDate
            )
        }
        .buttonStyle(ListButtonStyle(selected: fileState.currentLocalFile == file))
        .contextMenu {
            contextMenu()
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
        .onChange(of: file) { newValue in
            updateModifiedDate()
        }
        .onChange(of: updateFlag) { _ in
            updateModifiedDate()
        }
        .onAppear {
            updateModifiedDate()
        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        // Rename
        Button {
            isRenameSheetPresented.toggle()
        } label: {
            Label("Rename...", systemSymbol: .squareAndPencil)
                .foregroundStyle(.red)
        }

        Button {
            do {
                guard let folder = fileState.currentLocalFolder else { return }
                try folder.withSecurityScopedURL { scopedURL in
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
                }
            } catch {
                
            }
        } label: {
            Label("Duplicate", systemSymbol: .docOnDoc)
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
            Label("Copy File Path", systemSymbol: .arrowRightDocOnClipboard)
                .foregroundStyle(.red)
        }
        
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([self.file])
        } label: {
            Label("Reveal in Finder", systemSymbol: .docViewfinder)
                .foregroundStyle(.red)
        }
#endif
        Divider()
        
        // Delete
        Button {
            moveToTrash()
        } label: {
            Label("Move to Trash", systemSymbol: .trash)
                .foregroundStyle(.red)
        }
    }
    
    @MainActor @ViewBuilder
    private func moveLocalFileMenu() -> some View {
        if let currentLocalFolder = fileState.currentLocalFolder {
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
                Label(.localizable(.sidebarFileRowContextMenuMoveTo), systemSymbol: .trayAndArrowUp)
            }
        }
    }
    
    private func renameFile(newName: String) {
        do {
            if let folder = fileState.currentLocalFolder {
                try folder.withSecurityScopedURL { _ in
                    let newURL = file.deletingLastPathComponent()
                        .appendingPathComponent(
                            newName,
                            conformingTo: .excalidrawFile
                        )
                    try FileManager.default.moveItem(at: file, to: newURL)
                    
                    // Update local file ID mapping
                    ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                    self.fileState.currentLocalFile = newURL
                    ExcalidrawFile.localFileURLIDMapping[file] = nil
                    
                    // Also update checkpoints
                    updateCheckpoints(oldURL: self.file, newURL: newURL)
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func moveLocalFile(to targetFolderID: NSManagedObjectID) {
        guard case let folder as LocalFolder = viewContext.object(with: targetFolderID) else { return }
        do {
            try folder.withSecurityScopedURL { scopedURL in
                let fileCoordinator = NSFileCoordinator()
                fileCoordinator.coordinate(writingItemAt: scopedURL, options: .forMoving, error: nil) { url in
                    do {
                        try FileManager.default.moveItem(
                            at: self.file,
                            to: url.appendingPathComponent(
                                self.file.lastPathComponent,
                                conformingTo: .excalidrawFile
                            )
                        )
                    } catch {
                        alertToast(error)
                    }
                }
            }
            
            if let newURL = folder.url?.appendingPathComponent(
                self.file.lastPathComponent,
                conformingTo: .excalidrawFile
            ) {
                // Update local file ID mapping
                ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                ExcalidrawFile.localFileURLIDMapping[file] = nil
                
                // Also update checkpoints
                updateCheckpoints(oldURL: self.file, newURL: newURL)
            }
            
            if fileState.currentLocalFile == self.file {
                DispatchQueue.main.async {
                    fileState.currentLocalFolder = folder
                    fileState.expandToGroup(folder.objectID)
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
    
    private func updateModifiedDate() {
        self.modifiedDate = .distantPast
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.filePath)
            if let modifiedDate = attributes[FileAttributeKey.modificationDate] as? Date {
                self.modifiedDate = modifiedDate
            }
        } catch {
            print(error)
            DispatchQueue.main.async {
                alertToast(error)
            }
        }
    }
    
    private func moveToTrash() {
        do {
            if let folder = fileState.currentLocalFolder {
                try folder.withSecurityScopedURL { _ in
                    // Item removed will be handled in `LocalFilesListView`
                    let fileCoordinator = NSFileCoordinator()
                    fileCoordinator.coordinate(
                        writingItemAt: self.file,
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
                
                // Should change current local file...
                let folderURL = self.file.deletingLastPathComponent()
                let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.nameKey])
                let file = contents.first(where: {$0.pathExtension == "excalidraw"})
                fileState.currentLocalFile = file
            }
        } catch {
            alertToast(error)
        }
    }
}

