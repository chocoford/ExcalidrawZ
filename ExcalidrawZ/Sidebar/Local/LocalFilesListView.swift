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
    
    @State private var files: [URL] = []
    @State private var updateFlags: [URL : Date] = [:]
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#elseif canImport(UIKit)
    @State private var window: UIWindow?
#endif
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(files, id: \.self) { file in
                    LocalFileRowView(file: file, updateFlag: updateFlags[file])
                        .id(updateFlags[file])
                }
            }
            .animation(.default, value: files)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .bindWindow($window)
        .watchImmediately(of: folder.url) { newValue in
            DispatchQueue.main.async {
                getFolderContents()
                if horizontalSizeClass != .compact {
                    fileState.currentLocalFile = files.first
                }
            }
        }
#if os(macOS)
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        ) { notification in
            if let window = notification.object as? NSWindow,
               window == self.window {
                DispatchQueue.main.async {
                    getFolderContents()
                    if fileState.currentLocalFile == nil || fileState.currentLocalFile?.deletingLastPathComponent() != folder.url {
                        fileState.currentLocalFile = files.first
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
            fileState.currentLocalFile = files.first
        }
    }

    private func getFolderContents() {
        do {
            try folder.withSecurityScopedURL { folderURL in
                let contents = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: [.nameKey],
                    options: [.skipsSubdirectoryDescendants]
                )
                let files = contents
                    .filter({ $0.pathExtension == "excalidraw" })
                    .sorted {
                        ((try? FileManager.default.attributesOfItem(atPath: $0.filePath)[FileAttributeKey.modificationDate]) as? Date) ?? .distantPast > ((try? FileManager.default.attributesOfItem(atPath: $1.filePath)[FileAttributeKey.modificationDate]) as? Date) ?? .distantPast
                    }
                withAnimation {
                    self.files = files
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
    
    private func handleItemRemoved(path: String) {
        if fileState.currentLocalFile?.filePath == path {
            let index = files.firstIndex(where: {$0.filePath == path}) ?? -1
            if index <= 0 {
                if files.count <= 1 {
//                    try folder.withSecurityScopedURL { scopedURL in
//                        do {
//                            try await fileState.createNewLocalFile(folderURL: scopedURL)
//                        } catch {
//                            alertToast(error)
//                        }
//                    }
                    fileState.currentLocalFile = nil
                } else {
                    fileState.currentLocalFile = files[1]
                }
            } else {
                fileState.currentLocalFile = files[0]
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
