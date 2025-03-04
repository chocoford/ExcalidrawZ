//
//  LocalFoldersListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/21/25.
//

import SwiftUI

import ChocofordUI
import FSEventsWrapper

struct LocalFoldersListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState

    @FetchRequest(
        sortDescriptors: [
            SortDescriptor(\.importedAt, order: .forward),
            SortDescriptor(\.rank, order: .forward),
        ],
        predicate: NSPredicate(format: "parent == nil")
    )
    var folders: FetchedResults<LocalFolder>
    
    init() {
//        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
//        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LocalFolder.filePath, ascending: true)]
//        try? print("[TEST] LocalFolder", fetchRequest.execute().count)
    }
    
    
    @State private var window: NSWindow?
    @State private var localFolderMonitors: [LocalFolder : DirectoryMonitor] = [:]
    @State private var currentFolderMonitor: DirectoryMonitor?
    @State private var monitorTask: Task<Void, Never>?
    @State private var monitorTasks: [LocalFolder : Task<Void, Never>] = [:]
    
    @State private var folderUrlBeforeResignKey: URL?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(folders) { folder in
                VStack(alignment: .leading, spacing: 0) {
                    // Local folder view
                    Section {
                        LocalFoldersView(folder: folder) {
                            // switch current folder first if necessary.
                            if fileState.currentLocalFolder == folder {
                                guard let index = folders.firstIndex(of: folder) else {
                                    return
                                }
                                if index == 0 {
                                    if folders.count > 1 {
                                        fileState.currentLocalFolder = folders[1]
                                    } else {
                                        fileState.currentLocalFolder = nil
                                    }
                                } else {
                                    fileState.currentLocalFolder = folders[0]
                                }
                            }
                        }
                    }
                }
            }
        }
        .bindWindow($window)
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        ) { notification in
            if let window = notification.object as? NSWindow,
               window == self.window {
                do {
                    try self.refreshFoldersContent()
                    try redirectToCurrentFolder()
                } catch {
                    alertToast(error)
                }
                folderUrlBeforeResignKey = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow,
               window == self.window {
                self.folderUrlBeforeResignKey = fileState.currentLocalFolder?.url
            }
        }
        .watchImmediately(of: folders) { newValue in
            handleFoldersObservation(folders: newValue)
        }
        .onAppear {
            folders.forEach { try? $0.refreshChildren(context: viewContext) }
        }
    }
    
    private func refreshFoldersContent() throws {
        for i in 0..<folders.count {
            try folders[i].refreshChildren(context: viewContext)
        }
    }
    
    private func handleFoldersObservation(folders newValue: FetchedResults<LocalFolder>) {
        for folder in newValue.filter({ folder in !monitorTasks.contains(where: {$0.key == folder})}) {
            let monitorTask = Task { @MainActor in
                do {
                    try folder.withSecurityScopedURL { scopedURL in
                        for await event in FSEventAsyncStream(
                            path: scopedURL.filePath,
                            flags: FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
                        ) {
                            print("[FSEventAsyncStream]", event)
                            do {
                                switch event {
                                    case .itemCreated(let path, let itemType, _, _):
                                        switch itemType {
                                            case .dir:
                                                try folder.refreshChildren(context: viewContext)
                                            case .file:
                                                if path.hasSuffix(".excalidraw") {
                                                    localFolderState.itemCreatedPublisher.send(path)
                                                }
                                            default:
                                                break
                                        }
                                        
                                    // Move triggers `itemRenamed`, before&after
                                    // so 'Move to Trash' is actually `itemRenamed`
                                    case .itemRenamed(let path, let itemType, _, _):
                                        switch itemType {
                                            case .dir:
                                                try folder.refreshChildren(context: viewContext)
                                            case .file:
                                                guard path.hasSuffix(".excalidraw") else { return }
                                                localFolderState.itemRenamedPublisher.send(path)
                                            default:
                                                break
                                        }
                                        
                                    case .itemRemoved(let path, let itemType, _, _):
                                        if itemType == .file, path.hasSuffix(".excalidraw") {
                                            localFolderState.itemRemovedPublisher.send(path)
                                        }
                                        
                                    case .itemDataModified(let path, let itemType, _, _):
                                        if itemType == .file, path.hasSuffix(".excalidraw") {
                                            localFolderState.itemUpdatedPublisher.send(path)
                                        }
                                    default:
                                        break
                                }
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                } catch {
                    alertToast(error)
                }
            }
            monitorTasks.updateValue(monitorTask, forKey: folder)
            Task {
                await monitorTask.value
            }
        }
        
        // remove useless
        for outdatedMonitor in monitorTasks.filter({ monitor in
            !newValue.contains(monitor.key)
        }) {
            outdatedMonitor.value.cancel()
            monitorTasks.removeValue(forKey: outdatedMonitor.key)
        }
    }
    
    private func redirectToCurrentFolder() throws {
        guard fileState.currentGroup == nil, let folderUrlBeforeResignKey else { return }
        let context = viewContext
        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        let allFolders = try context.fetch(fetchRequest)
        
        fileState.currentLocalFolder = allFolders.first(where: {$0.url == folderUrlBeforeResignKey})
        
    }
}
