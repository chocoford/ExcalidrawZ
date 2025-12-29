//
//  TemporaryFileMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/7/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct TemporaryFileContextMenuModifier: ViewModifier {
    var file: URL

    func body(content: Content) -> some View {
        content
            .contextMenu {
                TemporaryFileMenuItems(file: file)
                    .labelStyle(.titleAndIcon)
            }
    }
}


struct TemporaryFileMenuItems: View {
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
                    moveFile(to: targetGroupID)
                }
            }
        } label: {
            Label {
                if !fileState.selectedTemporaryFiles.isEmpty && fileState.selectedTemporaryFiles.contains(file),
                   #available(macOS 13.0, iOS 16.0, *) {
                    Text(
                        localizable: .sidebarTemporaryGroupRowContextMenuSaveFilesTo(
                            fileState.selectedTemporaryFiles.count
                        )
                    )
                } else {
                    Text(localizable: .sidebarTemporaryGroupRowContextMenuSaveTo)
                }
            } icon: {
                Image(systemSymbol: .trayAndArrowDown)
            }
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
                .localizable(
                    !fileState.selectedTemporaryFiles.isEmpty && fileState.selectedTemporaryFiles.contains(file)
                    ? .generalMoveFilesTo(
                        fileState.selectedTemporaryFiles.count
                    )
                    : .generalMoveTo
                ),
                systemSymbol: .trayAndArrowUp
            )
        }
        
        Divider()
        
        Button {
            let filesToClose: [URL] = if fileState.selectedTemporaryFiles.contains(file) {
                Array(fileState.selectedTemporaryFiles)
            } else {
                [file]
            }
            
            fileState.setActiveFile(nil)
            
            for file in filesToClose {
                fileState.temporaryFiles.removeAll(where: {$0 == file})
            }
            
            if fileState.temporaryFiles.isEmpty {
                fileState.currentActiveGroup = nil
            } else {
                let file = fileState.temporaryFiles.first
                fileState.setActiveFile(file != nil ? .temporaryFile(file!) : nil) 
            }
        } label: {
            Label {
                if !fileState.selectedTemporaryFiles.isEmpty && fileState.selectedTemporaryFiles.contains(file),
                   #available(macOS 13.0, iOS 16.0, *) {
                    Text(localizable: .sidebarTemporaryFileRowContextMenuCloseFiles(
                        fileState.selectedTemporaryFiles.count
                    ))
                } else {
                    Text(localizable: .sidebarTemporaryFileRowContextMenuCloseFile)
                }
            } icon: {
                Image(systemSymbol: .xmarkCircle)
            }
        }
    }
    
    private func moveFile(to groupID: NSManagedObjectID) {
        let currentFileURL: URL? = if case .temporaryFile(let file) = fileState.currentActiveFile {
            file
        } else {
            nil
        }
        let context = PersistenceController.shared.container.newBackgroundContext()
        let filesToMove: [URL] = if fileState.selectedTemporaryFiles.contains(file) {
            Array(fileState.selectedTemporaryFiles)
        } else {
            [file]
        }
        
        Task.detached {
            do {
                var currentTemporaryFileID :NSManagedObjectID? = nil
                for file in filesToMove {
                    let newFileID = try await PersistenceController.shared.fileRepository.createFileFromURL(
                        file,
                        groupObjectID: groupID
                    )
                    let id: NSManagedObjectID? = try await context.perform {
                        guard case let group as Group = context.object(with: groupID) else {
                            return nil
                        }
                        var currentTemporaryFileID :NSManagedObjectID? = nil
                        guard let newFile = context.object(with: newFileID) as? File else {
                            return nil
                        }
                        newFile.group = group
                        context.insert(newFile)
                        if file == currentFileURL {
                            currentTemporaryFileID = newFile.objectID
                        }
                        try context.save()
                        return currentTemporaryFileID
                    }
                    
                    if let id {
                        currentTemporaryFileID = id
                    }
                }
                
                
                await MainActor.run { [currentTemporaryFileID] in
                    fileState.expandToGroup(groupID)
                    fileState.temporaryFiles.removeAll(where: {filesToMove.contains($0)})
                    
                    guard fileState.currentActiveGroup == .temporary else { return }
                    
                    // in temporary group, but no destination group.
                    guard case let group as Group = viewContext.object(with: groupID) else {
                        if fileState.temporaryFiles.isEmpty {
                            fileState.setActiveFile(nil)
                            fileState.currentActiveGroup = nil
                        }
                        return
                    }
                    if fileState.temporaryFiles.isEmpty {
                        fileState.currentActiveGroup = .group(group)
                    }
                    if let currentFileURL,
                       fileState.currentActiveFile == .temporaryFile(currentFileURL),
                       let currentTemporaryFileID,
                       case let file as File = viewContext.object(with: currentTemporaryFileID) {
                        fileState.setActiveFile(.file(file))
                    } else {
                        fileState.setActiveFile(nil)
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func moveLocalFile(to targetFolderID: NSManagedObjectID) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let filesToMove: [URL] = if fileState.selectedTemporaryFiles.contains(file) {
            Array(fileState.selectedTemporaryFiles)
        } else {
            [file]
        }
        Task.detached {
            do {
                let mapping = try LocalFileUtils.moveLocalFiles(
                    filesToMove,
                    to: targetFolderID,
                    context: context
                )
                await MainActor.run {
                    fileState.expandToGroup(targetFolderID)
                    fileState.temporaryFiles.removeAll(where: {filesToMove.contains($0)})
                    
                    
                    guard fileState.currentActiveGroup == .temporary else { return }
                    
                    // in temporary group, but no destination folder.
                    guard let folder = viewContext.object(with: targetFolderID) as? LocalFolder else {
                        if fileState.temporaryFiles.isEmpty {
                            fileState.setActiveFile(nil)
                            fileState.currentActiveGroup = nil
                        }
                        return
                    }
                    
                    if fileState.temporaryFiles.isEmpty {
                        fileState.currentActiveGroup = .localFolder(folder)
                    }

                    if case .temporaryFile(let localFile) = fileState.currentActiveFile,
                       localFile == file,
                       let newURL = mapping[localFile] {
                        fileState.setActiveFile(.localFile(newURL))
                    } else {
                        if fileState.temporaryFiles.isEmpty {
                            fileState.setActiveFile(nil)
                        }
                    }
                }
                
            } catch {
                await alertToast(error)
            }
        }
    }
}
