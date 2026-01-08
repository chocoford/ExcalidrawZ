//
//  LocalFilesProvider.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/22/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct LocalFilesProvider<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.alertToast) private var alertToast
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
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
            .watch(value: folder.url) { newValue in
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
                            fileState.setActiveFile(nil)
                        }
                    }
                }
            }
#elseif os(iOS)
            .onChange(of: scenePhase) { newValue in
                if newValue == .active {
                    getFolderContents()
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
                    fileState.setActiveFile(nil)
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
                        includingPropertiesForKeys: [
                            .nameKey, 
                            .contentModificationDateKey, 
                            .creationDateKey,
                            .ubiquitousItemDownloadingStatusKey,
                            .isUbiquitousItemKey
                        ],
                        options: [.skipsSubdirectoryDescendants]
                    )
                    let files = contents
                        .filter({
                            $0.pathExtension == "excalidraw"
                            || ($0.pathExtension == "svg" && $0.deletingPathExtension().pathExtension == "excalidraw")
                            || ($0.pathExtension == "png" && $0.deletingPathExtension().pathExtension == "excalidraw")
                        })
                        // Include files even if they are not downloaded (iCloud Drive files)
                        .filter({ url in
                            // Check if file exists locally or if it's an iCloud file (even if not downloaded)
                            if FileManager.default.fileExists(at: url) {
                                return true
                            }
                            
                            // For iCloud files that are not downloaded, we still want to include them
                            let resourceValues = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                            if let isUbiquitous = resourceValues?.isUbiquitousItem, isUbiquitous {
                                return true // Include iCloud files regardless of download status
                            }
                            
                            return false
                        })
                    withAnimation {
                        self.files = files
                        self.sortFiles(field: self.sortField)
                        
                        if case .localFolder(let folder) = fileState.currentActiveGroup,
                           folder == self.folder,
                           case .localFile(let currentFile) = fileState.currentActiveFile {
                            if !files.contains(currentFile) {
                                fileState.setActiveFile(nil)
                            }
                        }
                    }
                    self.updateFlags = files.map {
                        [$0 : Date()]
                    }.merged()
                }
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
                    return (lhsAttrs?[.creationDate] as? Date) ?? .distantPast > (rhsAttrs?[.creationDate] as? Date) ?? .distantPast
                }
                files.sort {
                    // updatedAt
                    let lhsAttrs = try? FileManager.default.attributesOfItem(atPath: $0.filePath)
                    let rhsAttrs = try? FileManager.default.attributesOfItem(atPath: $1.filePath)
                    return (lhsAttrs?[.modificationDate] as? Date) ?? .distantPast > (rhsAttrs?[.modificationDate] as? Date) ?? .distantPast
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
                    fileState.setActiveFile(nil)
                } else {
                    fileState.setActiveFile(.localFile(files[1]))
                }
            } else {
                fileState.setActiveFile(.localFile(files[0]))
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
