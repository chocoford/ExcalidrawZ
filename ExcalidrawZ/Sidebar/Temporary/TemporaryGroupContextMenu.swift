//
//  TemporaryGroupContextMenu.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/21/25.
//

import SwiftUI
import CoreData

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
            fileState.setActiveFile(nil)
            fileState.temporaryFiles.removeAll()
            fileState.currentActiveGroup = nil
        } label: {
            Label(.localizable(.sidebarTemporaryGroupRowContextMenuCloseAll), systemSymbol: .xmarkCircle)
        }
    }
    
    private func moveFiles(to groupID: NSManagedObjectID) {
        let temporaryFiles = fileState.temporaryFiles
        let currentFileURL: URL? = if case .temporaryFile(let file) = fileState.currentActiveFile {
            file
        } else {
            nil
        }
        
        Task.detached {
            do {
                var currentTemporaryFileID: NSManagedObjectID?
                for file in temporaryFiles {
                    let newFileID = try await PersistenceController.shared.fileRepository.createFileFromURL(
                        file,
                        groupObjectID: groupID
                    )
                    if file == currentFileURL {
                        currentTemporaryFileID = newFileID
                    }
                }
                
                
                await MainActor.run { [currentTemporaryFileID] in
                    fileState.temporaryFiles.removeAll()
                    fileState.expandToGroup(groupID)
                    
                    guard fileState.currentActiveGroup == .temporary else {
                        return
                    }
                    // in temprary but no destination group.
                    guard case let group as Group = viewContext.object(with: groupID) else {
                        fileState.currentActiveGroup = nil
                        fileState.setActiveFile(nil)
                        return
                    }
                    
                    fileState.currentActiveGroup = .group(group)

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
    
    private func moveLocalFiles(to targetFolderID: NSManagedObjectID) {
        let temporaryFiles = fileState.temporaryFiles
        let currentFileURL: URL? = if case .temporaryFile(let file) = fileState.currentActiveFile {
            file
        } else {
            nil
        }
        Task.detached {
            let context = PersistenceController.shared.container.newBackgroundContext()

            do {
                let mapping = try LocalFileUtils.moveLocalFiles(
                    temporaryFiles,
                    to: targetFolderID,
                    context: context
                )
                
                
                await MainActor.run {
                    fileState.temporaryFiles.removeAll()
                    fileState.expandToGroup(targetFolderID)
                    // ignore if current file is not temporary
                    guard fileState.currentActiveGroup == .temporary else {
                        return
                    }
                    
                    // in temprary but no destination folder.
                    guard let localFolder = viewContext.object(with: targetFolderID) as? LocalFolder else {
                        fileState.currentActiveGroup = nil
                        fileState.setActiveFile(nil)
                        return
                    }
                    fileState.currentActiveGroup = .localFolder(localFolder)

                    
                    guard let currentFileURL,
                          fileState.currentActiveFile == .temporaryFile(currentFileURL),
                          let currentFileNewURL = mapping[currentFileURL] else {
                        fileState.setActiveFile(nil)
                        return
                    }
                    
                    fileState.setActiveFile(.localFile(currentFileNewURL))
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

