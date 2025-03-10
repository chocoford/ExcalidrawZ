//
//  TemporaryFileListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/5/25.
//

import SwiftUI

import ChocofordUI

struct TemporaryFileListView: View {
    @EnvironmentObject private var fileState: FileState
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(fileState.temporaryFiles, id: \.self) { file in
                    TemporaryFileRowView(file: file)
                }
            }
            .animation(.default, value: fileState.temporaryFiles)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
    }
}

struct TemporaryFileRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    
    var file: URL
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    var topLevelGroups: FetchedResults<Group>
        
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.filePath, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelLocalFolders: FetchedResults<LocalFolder>
    
    
    @State private var modifiedDate: Date = .distantPast
    
    var body: some View {
        Button {
            fileState.currentTemporaryFile = file
        } label: {
            FileRowLabel(
                name: file.deletingPathExtension().lastPathComponent,
                updatedAt: modifiedDate
            )
        }
        .buttonStyle(ListButtonStyle(selected: fileState.currentTemporaryFile == file))
        .contextMenu {
            contextMenu()
                .labelStyle(.titleAndIcon)
        }
        .watchImmediately(of: file) { newValue in
            updateModifiedDate()
        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        Menu {
            let groups: [Group] = topLevelGroups
                .filter{ $0.groupType != .trash }
                .sorted { a, b in
                    a.groupType == .default && b.groupType != .default ||
                    a.groupType == b.groupType && b.groupType == .normal && a.createdAt ?? .distantPast < b.createdAt ?? .distantPast
                }
            ForEach(groups) { group in
                MoveToGroupMenu(
                    destination: group,
                    sourceGroup: nil,
                    childrenSortKey: \Group.name,
                    allowSubgroups: true
                ) { targetGroupID in
                    moveFile(to: targetGroupID)
                }
            }
        } label: {
            Label(
                .localizable(.sidebarTemporaryGroupRowContextMenuSaveTo),
                systemSymbol: .trayAndArrowDown
            )
        }
        
        Menu {
            ForEach(topLevelLocalFolders) { folder in
                MoveToGroupMenu(
                    destination: folder,
                    sourceGroup: nil,
                    childrenSortKey: \LocalFolder.filePath,
                    allowSubgroups: true
                ) { targetFolderID in
                     moveLocalFile(to: targetFolderID)
                }
            }
        } label: {
            Label(
                .localizable(.sidebarTemporaryGroupRowContextMenuMoveTo),
                systemSymbol: .trayAndArrowUp
            )
        }
        
        
        Divider()
        
        Button {
            fileState.currentTemporaryFile = nil
            fileState.temporaryFiles.removeAll(where: {$0 == file})
            
            if fileState.temporaryFiles.isEmpty {
                fileState.isTemporaryGroupSelected = false
            } else {
                fileState.currentTemporaryFile = fileState.temporaryFiles.first
            }
        } label: {
            Label(.localizable(.sidebarTemporaryFileRowContextMenuCloseFile), systemSymbol: .xmarkCircle)
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
    
    private func moveFile(to groupID: NSManagedObjectID) {
        let currentFileURL = fileState.currentTemporaryFile
        let file = self.file
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                var currentTemporaryFileID: NSManagedObjectID?
                try await context.perform {
                    let newFile = try File(url: file, context: context)
                    guard case let group as Group = context.object(with: groupID) else { return }
                    newFile.group = group
                    context.insert(newFile)
                    
                    try context.save()
                    if file == currentFileURL {
                        currentTemporaryFileID = newFile.objectID
                    }
                }
                
                await MainActor.run { [currentTemporaryFileID] in
                    guard case let group as Group = viewContext.object(with: groupID) else { return }
                    fileState.currentGroup = group
                    if let currentTemporaryFileID,
                       case let file as File = viewContext.object(with: currentTemporaryFileID) {
                        fileState.currentFile = file
                    } else {
                        fileState.currentFile = group.files?.allObjects.first as? File
                    }
                    
                    fileState.expandToGroup(group.objectID)
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func moveLocalFile(to targetFolderID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let file = self.file
        Task.detached {
            do {
                try await context.perform {
                    guard case let folder as LocalFolder = context.object(with: targetFolderID) else { return }
                    
                    try folder.withSecurityScopedURL { scopedURL in
                        let fileCoordinator = NSFileCoordinator()
                        fileCoordinator.coordinate(writingItemAt: scopedURL, options: .forMoving, error: nil) { url in
                            do {
                                try FileManager.default.moveItem(
                                    at: file,
                                    to: url.appendingPathComponent(
                                        file.lastPathComponent,
                                        conformingTo: .excalidrawFile
                                    )
                                )
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                    if let newURL = folder.url?.appendingPathComponent(
                        file.lastPathComponent,
                        conformingTo: .excalidrawFile
                    ) {
                        // Update local file ID mapping
                        ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                        ExcalidrawFile.localFileURLIDMapping[file] = nil
                        
                        // Also update checkpoints
                        Task {
                            await MainActor.run {
                                updateLocalFileCheckpoints(oldURL: file, newURL: newURL)
                            }
                        }
                        
                        Task {
                            await MainActor.run {
                                fileState.temporaryFiles.removeAll(where: {$0 == file})
                                if fileState.temporaryFiles.isEmpty {
                                    fileState.isTemporaryGroupSelected = false
                                }
                                if fileState.currentTemporaryFile == file {
                                    fileState.currentLocalFolder = viewContext.object(with: targetFolderID) as? LocalFolder
                                    fileState.currentLocalFile = newURL
                                    // auto expand
                                    fileState.expandToGroup(folder.objectID)
                                }
                            }
                        }
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func updateLocalFileCheckpoints(oldURL: URL, newURL: URL) {
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

#Preview {
    TemporaryFileListView()
}
