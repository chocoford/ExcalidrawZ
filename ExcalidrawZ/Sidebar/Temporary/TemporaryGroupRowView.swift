//
//  TemporaryGroupRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/5/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct TemporaryGroupRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
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
    
    
    var body: some View {
        Button {
            fileState.isTemporaryGroupSelected = true
        } label: {
            HStack {
                Label {
                    Text(.localizable(.sidebarGroupRowTitleTemporary))
                } icon: {
                    Image(systemSymbol: .clock)
                }
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListButtonStyle(selected: fileState.isTemporaryGroupSelected))
        .contextMenu {
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
                        moveFiles(to: targetGroupID)
                    }
                }
            } label: {
                Label(.localizable(.sidebarTemporaryGroupRowContextMenuSaveTo), systemSymbol: .trayAndArrowDown)
            }
            
            Menu {
                ForEach(topLevelLocalFolders) { folder in
                    MoveToGroupMenu(
                        destination: folder,
                        sourceGroup: nil,
                        childrenSortKey: \LocalFolder.filePath,
                        allowSubgroups: true
                    ) { targetFolderID in
                         moveLocalFiles(to: targetFolderID)
                    }
                }
            } label: {
                Label(.localizable(.generalMoveTo), systemSymbol: .trayAndArrowUp)
            }
            
            Divider()
            Button {
                fileState.currentTemporaryFile = nil
                fileState.temporaryFiles.removeAll()
                fileState.isTemporaryGroupSelected = false
            } label: {
                Label(.localizable(.sidebarTemporaryGroupRowContextMenuCloseAll), systemSymbol: .xmarkCircle)
            }
        }
    }
    
    private func moveFiles(to groupID: NSManagedObjectID) {
        let temporaryFiles = fileState.temporaryFiles
        let currentFileURL = fileState.currentTemporaryFile
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                var currentTemporaryFileID: NSManagedObjectID?
                try await context.perform {
                    var currentFile: File?
                    for file in temporaryFiles {
                        let newFile = try File(url: file, context: context)
                        guard case let group as Group = context.object(with: groupID) else { continue }
                        newFile.group = group
                        context.insert(newFile)
                        if file == currentFileURL {
                            currentFile = newFile
                        }
                    }
                    try context.save()
                    
                    currentTemporaryFileID = currentFile?.objectID
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
    
    private func moveLocalFiles(to targetFolderID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let temporaryFiles = fileState.temporaryFiles
        let currentFileURL = fileState.currentTemporaryFile
        Task.detached {
            do {
                try await context.perform {
                    guard case let folder as LocalFolder = context.object(with: targetFolderID) else { return }
                    
                    try folder.withSecurityScopedURL { scopedURL in
                        let fileCoordinator = NSFileCoordinator()
                        fileCoordinator.coordinate(writingItemAt: scopedURL, options: .forMoving, error: nil) { url in
                            for file in fileState.temporaryFiles {
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
                    }
                    
                    var currentFileNewURL: URL?
                    for file in temporaryFiles {
                        if let newURL = folder.url?.appendingPathComponent(
                            file.lastPathComponent,
                            conformingTo: .excalidrawFile
                        ) {
                            if file == currentFileURL { currentFileNewURL = newURL }
                            // Update local file ID mapping
                            ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                            ExcalidrawFile.localFileURLIDMapping[file] = nil
                            
                            // Also update checkpoints
                            Task {
                                await MainActor.run {
                                    updateLocalFileCheckpoints(oldURL: file, newURL: newURL)
                                }
                            }
                        }
                    }
                    
                    Task { [currentFileNewURL] in
                        if await fileState.isTemporaryGroupSelected {
                            await MainActor.run {
                                fileState.temporaryFiles.removeAll()
                                fileState.expandToGroup(folder.objectID)
                                
                                fileState.currentLocalFolder = viewContext.object(with: targetFolderID) as? LocalFolder
                                fileState.currentLocalFile = currentFileNewURL
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
    TemporaryGroupRowView()
}
