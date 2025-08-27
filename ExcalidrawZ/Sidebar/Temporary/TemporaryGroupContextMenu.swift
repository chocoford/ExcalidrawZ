//
//  TemporaryGroupContextMenu.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/21/25.
//

import SwiftUI

struct TemporaryGroupMenuItems: View {
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
    
    init() {}
    
    var body: some View {
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
            fileState.currentActiveFile = nil
            fileState.temporaryFiles.removeAll()
            fileState.currentActiveGroup = nil
        } label: {
            Label(.localizable(.sidebarTemporaryGroupRowContextMenuCloseAll), systemSymbol: .xmarkCircle)
        }
    }
    
    private func moveFiles(to groupID: NSManagedObjectID) {
        let temporaryFiles = fileState.temporaryFiles
        guard case .temporaryFile(let currentFileURL) = fileState.currentActiveFile else {
            return
        }
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
                    fileState.currentActiveGroup = .group(group)
                    if let currentTemporaryFileID,
                       case let file as File = viewContext.object(with: currentTemporaryFileID) {
                        fileState.currentActiveFile = .file(file)
                    } else {
                        let file = group.files?.allObjects.first as? File
                        fileState.currentActiveFile = file != nil ? .file(file!) : nil
                    }
                    
                    fileState.expandToGroup(group.objectID)
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func moveLocalFiles(to targetFolderID: NSManagedObjectID) {
        let temporaryFiles = fileState.temporaryFiles
        guard case .temporaryFile(let currentFileURL) = fileState.currentActiveFile else {
            return
        }
        Task.detached {
            let context = PersistenceController.shared.container.newBackgroundContext()

            do {
                let mapping = try await LocalFileUtils.moveLocalFiles(
                    temporaryFiles,
                    to: targetFolderID,
                    context: context
                )
                
                let currentFileNewURL = mapping[currentFileURL]
                
                if await fileState.currentActiveGroup == .temporary {
                    await MainActor.run {
                        fileState.temporaryFiles.removeAll()
                        fileState.expandToGroup(targetFolderID)
                        let localFolder = viewContext.object(with: targetFolderID) as? LocalFolder
                        fileState.currentActiveGroup = localFolder != nil ? .localFolder(localFolder!) : nil
                        fileState.currentActiveFile = currentFileNewURL != nil ? .localFile(currentFileNewURL!) : nil
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

