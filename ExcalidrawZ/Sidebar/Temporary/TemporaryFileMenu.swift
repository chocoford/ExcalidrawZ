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
            
            fileState.currentActiveFile = nil
            
            for file in filesToClose {
                fileState.temporaryFiles.removeAll(where: {$0 == file})
            }
            
            if fileState.temporaryFiles.isEmpty {
                fileState.currentActiveGroup = nil
            } else {
                let file = fileState.temporaryFiles.first
                fileState.currentActiveFile = file != nil ? .temporaryFile(file!) : nil
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
        guard case .temporaryFile(let currentFileURL) = fileState.currentActiveFile else { return }
        let context = PersistenceController.shared.container.newBackgroundContext()
        let filesToMove: [URL] = if fileState.selectedTemporaryFiles.contains(file) {
            Array(fileState.selectedTemporaryFiles)
        } else {
            [file]
        }
        
        Task.detached {
            do {
                var currentTemporaryFileID: NSManagedObjectID?
                try await context.perform {
                    guard case let group as Group = context.object(with: groupID) else { return }
                    
                    for file in filesToMove {
                        let newFile = try File(url: file, context: context)
                        newFile.group = group
                        context.insert(newFile)
                        if file == currentFileURL {
                            currentTemporaryFileID = newFile.objectID
                        }
                    }
                    try context.save()
                }
                
                await MainActor.run { [currentTemporaryFileID] in
                    guard case let group as Group = viewContext.object(with: groupID) else { return }
                    fileState.currentActiveGroup = .group(group)
                    if let currentTemporaryFileID,
                       case let file as File = viewContext.object(with: currentTemporaryFileID) {
                        fileState.currentActiveFile = .file(file)
                    } else {
                        let firstFile = group.files?.allObjects.first as? File
                        fileState.currentActiveFile = firstFile != nil ? .file(firstFile!) : nil
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
                    fileState.temporaryFiles.removeAll(where: {filesToMove.contains($0)})
                    if fileState.temporaryFiles.isEmpty {
                        fileState.currentActiveGroup = nil
                    }
                    if case .localFile(let localFile) = fileState.currentActiveFile,
                       localFile == file,
                       let newURL = mapping[localFile] {
                        let folder = viewContext.object(with: targetFolderID) as? LocalFolder
                        fileState.currentActiveGroup = folder != nil ? .localFolder(folder!) : nil
                        fileState.currentActiveFile = .localFile(newURL)
                        // auto expand
                        if let folder {
                            fileState.expandToGroup(folder.objectID)
                        }
                    }
                }
                
            } catch {
                await alertToast(error)
            }
        }
    }
}
