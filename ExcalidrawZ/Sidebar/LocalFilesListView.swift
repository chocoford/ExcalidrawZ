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
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState
    
    var folder: LocalFolder
    
    @State private var files: [URL] = []
    @State private var updateFlags: [URL : Date] = [:]
    
    @State private var window: NSWindow?
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(files, id: \.self) { file in
                    LocalFileRowView(file: file, updateFlag: updateFlags[file])
                }
            }
            .animation(.default, value: files)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .bindWindow($window)
        .watchImmediately(of: folder.url) { newValue in
            getFolderContents()
            fileState.currentLocalFile = files.first
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        ) { notification in
            if let window = notification.object as? NSWindow,
               window == self.window {
                getFolderContents()
            }
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
    }

    private func getFolderContents() {
        do {
            debugPrint("[TEST] getFolderContents...")
            try folder.withSecurityScopedURL { folderURL in
                let contents = try FileManager.default.contentsOfDirectory(
                    at: folderURL,
                    includingPropertiesForKeys: [.nameKey],
                    options: [.skipsSubdirectoryDescendants]
                )
                
                self.files = contents
                    .filter({ $0.pathExtension == "excalidraw" })
                    .sorted {
                        ((try? FileManager.default.attributesOfItem(atPath: $0.filePath)[FileAttributeKey.modificationDate]) as? Date) ?? .distantPast > ((try? FileManager.default.attributesOfItem(atPath: $1.filePath)[FileAttributeKey.modificationDate]) as? Date) ?? .distantPast
                    }
                self.updateFlags = self.files.map {
                    [$0 : Date()]
                }.merged()
            }
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
}
