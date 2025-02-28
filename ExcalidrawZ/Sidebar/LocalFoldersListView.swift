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
        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LocalFolder.filePath, ascending: true)]
        try? print("[TEST] LocalFolder", fetchRequest.execute().count)
    }
    
    
    @State private var window: NSWindow?
    @State private var localFolderMonitors: [LocalFolder : DirectoryMonitor] = [:]
    @State private var currentFolderMonitor: DirectoryMonitor?
    @State private var monitorTask: Task<Void, Never>?
    @State private var monitorTasks: [LocalFolder : Task<Void, Never>] = [:]

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
                } catch {
                    alertToast(error)
                }
            }
        }
        .watchImmediately(of: folders) { newValue in
            handleFoldersObservation(folders: newValue)
        }
//        .onChange(of: fileState.currentLocalFolder) { newValue in
//            currentFolderMonitor?.stop()
//            currentFolderMonitor = nil
//            monitorTask?.cancel()
//            guard let folder = newValue else { return }
//            monitorTask = Task{
//                do {
//                    try folder.withSecurityScopedURL { scopedURL in
//                        for await event in FSEventAsyncStream(
//                            path: scopedURL.filePath,
//                            flags: FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
//                        ) {
//                            print("[FSEventAsyncStream]", event)
//                            switch event {
//                                case .itemCreated(let path, let itemType, _, _):
//                                    break
//                                default:
//                                    break
//                            }
//                            
//                        }
////                    let monitor = DirectoryMonitor(url: scopedURL) { event in
////                        do {
////                            debugPrint("Refresing folder: \(String(describing: folder.url))")
////                            try folder.refreshChildren(context: viewContext)
////                        } catch {
////                            alertToast(error)
////                        }
////                    }
////                    monitor.start()
////                    currentFolderMonitor = monitor
//                    }
//                } catch {
//                    alertToast(error)
//                }
//            }
//
//            Task {
//                 await monitorTask?.value
//            }
//        }
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
                                        
                                    // Folders Deletion triggers `itemRenamed`
                                    case .itemRenamed(let path, let itemType, _, _):
                                        switch itemType {
                                            case .dir:
                                                try folder.refreshChildren(context: viewContext)
                                            case .file:
                                                guard path.hasSuffix(".excalidraw") else { return }
                                                localFolderState.itemRemovedPublisher.send(path)
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
}

struct LocalFoldersView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    
    var folder: LocalFolder
    var depth: Int
    var onDeleteSelected: () -> Void
        
    @FetchRequest
    private var folderChildren: FetchedResults<LocalFolder>
    
    init(folder: LocalFolder, depth: Int = 0, onDeleteSelected: @escaping () -> Void) {
        self.folder = folder
        self.depth = depth
        self._folderChildren = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \LocalFolder.filePath, ascending: true),
                NSSortDescriptor(keyPath: \LocalFolder.rank, ascending: true),
            ],
            predicate: NSPredicate(format: "parent = %@", folder),
            animation: .default
        )
        self.onDeleteSelected = onDeleteSelected
    }
    
    let paddingBase: CGFloat = 14
    
    var isSelected: Bool {
        fileState.currentLocalFolder == folder
    }
    
    var body: some View {
        Button {
            fileState.currentLocalFolder = folder
        } label: {
            Text(folder.url?.lastPathComponent ?? "Unknwon")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(ListButtonStyle(selected: isSelected))
        .contextMenu {
            contextMenu()
                .labelStyle(.titleAndIcon)
        }
        
        ForEach(folderChildren) { folder in
            let isLast = folder == folderChildren.last
            
            LocalFoldersView(folder: folder, depth: depth + 1) {
                // switch current folder first if necessary.
                if fileState.currentLocalFolder == folder {
                    guard let index = folderChildren.firstIndex(of: folder) else {
                        return
                    }
                    if index == 0 {
                        if folderChildren.count > 1 {
                            fileState.currentLocalFolder = folderChildren[1]
                        } else {
                            fileState.currentLocalFolder = nil
                        }
                    } else {
                        fileState.currentLocalFolder = folderChildren[0]
                    }
                }
            }
            .padding(.leading, CGFloat(depth+1) * paddingBase)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1)
                        
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1)
                            .opacity(isLast ? 0 : 1)
                    }
                    
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 5, height: 1)
                }
                .padding(.leading, CGFloat(depth+1) * paddingBase - 6)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        if folder.parent == nil {
            Button(role: .destructive) {
                Task {
                    await managedObjectContext.perform {
                        managedObjectContext.delete(folder)
                    }
                }
            } label: {
                Label("Remove Observation", systemSymbol: .trash)
            }
        } else {
            Button(role: .destructive) {
                do {
                    onDeleteSelected()
                    try folder.withSecurityScopedURL { scopedURL in
                        let fileCoordinator = NSFileCoordinator()
                        fileCoordinator.coordinate(
                            writingItemAt: scopedURL,
                            options: .forDeleting,
                            error: nil
                        ) { url in
                            do {
                                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                            } catch {
                                alertToast(error)
                            }
                        }
                    }
                } catch {
                    alertToast(error)
                }
            } label: {
                Label("Move to Trash", systemSymbol: .trash)
            }
        }
    }
}

