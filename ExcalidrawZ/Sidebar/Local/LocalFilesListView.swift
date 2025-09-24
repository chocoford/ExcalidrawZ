//
//  LocalFilesListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/21/25.
//

import SwiftUI

import ChocofordUI

struct LocalFilesListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var horizontalSizeClass
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState
    
    var folder: LocalFolder
    var sortField: ExcalidrawFileSortField
    
    init(
        folder: LocalFolder,
        sortField: ExcalidrawFileSortField
    ) {
        self.folder = folder
        self.sortField = sortField
    }
    
    var body: some View {
        ScrollView {
            LocalFilesListContentView(folder: folder, sortField: sortField)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
#if os(macOS)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                                return
                            }
                            fileState.resetSelections()
                        }
                }
#endif
        }
    }
}

struct LocalFilesProvider<Content: View>: View {
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState

    var folder: LocalFolder
    var sortField: ExcalidrawFileSortField
    var content: (_ files: [URL], _ updateFlag: [URL : Date]) -> Content
    
    init(
        folder: LocalFolder,
        sortField: ExcalidrawFileSortField,
        @ViewBuilder content: @escaping (_ files: [URL], _ updateFlag: [URL : Date]) -> Content
    ) {
        self.folder = folder
        self.sortField = sortField
        self.content = content
    }
    
    static func withSibling(
        file: URL,
        sortField: ExcalidrawFileSortField,
        @ViewBuilder content: @escaping (_ files: [URL], _ updateFlag: [URL : Date]) -> Content
    ) -> Self? {
        let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
        fetchRequest.predicate = NSPredicate(format: "filePath == %@", file.deletingLastPathComponent().filePath)
        fetchRequest.fetchLimit = 1
        
        guard let folder = (try? PersistenceController.shared.container.viewContext.fetch(fetchRequest))?.first else {
            return nil
        }
        
        return LocalFilesProvider(
            folder: folder,
            sortField: sortField,
            content: content
        )
    }
    
    
    @State private var files: [URL] = []
    @State private var updateFlags: [URL : Date] = [:]
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    var body: some View {
        content(files, updateFlags)
            .bindWindow($window)
            .watchImmediately(of: folder.url) { newValue in
                DispatchQueue.main.async { getFolderContents() }
            }
    #if os(macOS)
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            ) { notification in
                if let window = notification.object as? NSWindow,
                   window == self.window {
                    DispatchQueue.main.async {
                        guard fileState.currentActiveGroup == .localFolder(folder) else { return }
                        getFolderContents()
                        if fileState.currentActiveFile == nil || {
                            if case .localFile(let localFile) = fileState.currentActiveFile {
                                return localFile.deletingLastPathComponent() != folder.url
                            } else {
                                return true
                            }
                        }() {
                            fileState.currentActiveFile = nil
                        }
                    }
                }
            }
    #elseif os(iOS)
            .onChange(of: scenePhase) { newValue in
                if newValue == .active {
                    DispatchQueue.main.async {
                        getFolderContents()
                        if horizontalSizeClass != .compact {
                            if fileState.currentLocalFile == nil || fileState.currentLocalFile?.deletingLastPathComponent() != folder.url {
                                fileState.currentLocalFile = files.first
                            }
                        }
                    }
                }
            }
    #endif
            .onChange(of: sortField) { newValue in
                sortFiles(field: newValue)
            }
            .onReceive(localFolderState.itemCreatedPublisher) { path in
                getFolderContents()
            }
            .onReceive(localFolderState.itemRemovedPublisher) { path in
                handleItemRemoved(path: path)
            }
            .onReceive(localFolderState.itemUpdatedPublisher) { path in
                handleItemUpdated(path: path)
            }
            .onReceive(localFolderState.itemRenamedPublisher) { path in
                handleItemRenamed(path: path)
            }
            .onReceive(localFolderState.refreshFilesPublisher) { _ in
                getFolderContents()
                if case .localFile(let file) = fileState.currentActiveFile,
                   !files.contains(file) {
                    fileState.currentActiveFile = nil
                }
            }
    }
    
    private func getFolderContents() {
        // wait a liitle
        DispatchQueue.main.async {
            do {
                try folder.withSecurityScopedURL { folderURL in
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: folderURL,
                        includingPropertiesForKeys: [.nameKey, .contentModificationDateKey, .creationDateKey],
                        options: [.skipsSubdirectoryDescendants]
                    )
                    let files = contents
                        .filter({ $0.pathExtension == "excalidraw" })
                    withAnimation {
                        self.files = files
                        self.sortFiles(field: self.sortField)
                        
                        if case .localFolder(let folder) = fileState.currentActiveGroup,
                            folder == self.folder,
                            case .localFile(let currentFile) = fileState.currentActiveFile {
                            if !files.contains(currentFile) {
                                fileState.currentActiveFile = nil
                            }
                        }
                    }
                    self.updateFlags = files.map {
                        [$0 : Date()]
                    }.merged()
                }
                // debugPrint("[DEBUG] getFolderContents...", self.files)
            } catch {
                alertToast(error)
            }
        }
    }

    private func sortFiles(field: ExcalidrawFileSortField) {
        switch field {
            case .updatedAt, .rank:
                files.sort {
                    // createdAt
                    let lhsAttrs = try? FileManager.default.attributesOfItem(atPath: $0.filePath)
                    let rhsAttrs = try? FileManager.default.attributesOfItem(atPath: $1.filePath)
                    return (lhsAttrs?[.creationDate] as? Date) ?? .distantPast < (rhsAttrs?[.creationDate] as? Date) ?? .distantPast
                }
                files.sort {
                    // updatedAt
                    let lhsAttrs = try? FileManager.default.attributesOfItem(atPath: $0.filePath)
                    let rhsAttrs = try? FileManager.default.attributesOfItem(atPath: $1.filePath)
                    return (lhsAttrs?[.modificationDate] as? Date) ?? .distantPast < (rhsAttrs?[.modificationDate] as? Date) ?? .distantPast
                }
            case .name:
                files.sort {
                    $0.deletingPathExtension().lastPathComponent < $1.deletingPathExtension().lastPathComponent
                }
        }
    }
    
    private func handleItemRemoved(path: String) {
        if case .localFile(let file) = fileState.currentActiveFile, file.filePath == path {
            let index = files.firstIndex(where: {$0.filePath == path}) ?? -1
            if index <= 0 {
                if files.count <= 1 {
                    fileState.currentActiveFile = nil
                } else {
                    fileState.currentActiveFile = .localFile(files[1])
                }
            } else {
                fileState.currentActiveFile = .localFile(files[0])
            }
        }
        files.removeAll(where: { $0.filePath == path })
    }
    
    private func handleItemUpdated(path: String) {
        guard let file = self.files.first(where: {$0.filePath == path}) else { return }
        self.updateFlags[file] = Date()
        self.files.sort {
                ((try? FileManager.default.attributesOfItem(atPath: $0.filePath)[FileAttributeKey.modificationDate]) as? Date) ?? .distantPast > ((try? FileManager.default.attributesOfItem(atPath: $1.filePath)[FileAttributeKey.modificationDate]) as? Date) ?? .distantPast
            }
    }
    
    private func handleItemRenamed(path: String) {
        getFolderContents()
    }
}

struct LocalFilesListContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var horizontalSizeClass

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState
    @EnvironmentObject private var sidebarDragState: ItemDragState

    var folder: LocalFolder
    var sortField: ExcalidrawFileSortField
    
    @State private var isBeingDropped: Bool = false
    
    var body: some View {
        LocalFilesProvider(folder: folder, sortField: sortField) { files, updateFlags in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files, id: \.self) { file in
                    LocalFileRowView(
                        file: file,
                        updateFlag: updateFlags[file],
                        files: files
                    )
                    .id(updateFlags[file])
                }
            }
            .animation(.default, value: files)
            .modifier(LocalFolderDropModifier(folder: folder) {.below($0)})
        }
    }
}
