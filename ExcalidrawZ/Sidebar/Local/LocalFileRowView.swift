//
//  LocalFileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/24/25.
//

import SwiftUI
import CoreData

import ChocofordUI

extension Notification.Name {
    static var fileMetadataDidModified = Notification.Name("FileMetadataDidModified")
    static var fileXattrDidModified = Notification.Name("FileXattrDidModified")
}

struct LocalFileRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
    var file: URL
    var updateFlag: Date?
    
    init(file: URL, updateFlag: Date?) {
        self.file = file
        self.updateFlag = updateFlag
    }
    
    struct ICloudState {
        var downloadStatus: URLUbiquitousItemDownloadingStatus = .notDownloaded
        var isDownloading = false
        var isUploading = false
        var isUploaded = false
    }
    
    @State private var modifiedDate: Date = .distantPast
    @State private var iCloudState: ICloudState?
    
    @State private var isRenameSheetPresented = false
    @State private var isDeleteConfirmationDialogPresented = false
    
    @State private var isWaitingForOpeningFile = false
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.filePath, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    private var topLevelLocalFolders: FetchedResults<LocalFolder>
    
    var body: some View {
        Button {
            if let iCloudState, iCloudState.downloadStatus != .current {
                // request iCloud download first
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: file)
                    isWaitingForOpeningFile = true
                } catch {
                    alertToast(error)
                }
            } else {
                fileState.currentLocalFile = file
            }
        } label: {
            FileRowLabel(
                name: file.deletingPathExtension().lastPathComponent,
                updatedAt: modifiedDate
            ) {
                if let iCloudState {
                    if isWaitingForOpeningFile {
                        Spacer()
                        ProgressView()
                            .controlSize(.mini)
                    } else if iCloudState.downloadStatus != .current {
                        Spacer()
                        Image(systemSymbol: .icloudAndArrowDown)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else if iCloudState.isUploading {
                        Spacer()
                        if #available(macOS 15.0, *) {
                            Image(systemSymbol: .icloudAndArrowUp)
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .symbolEffect(.breathe)
                        } else if #available(macOS 14.0, *) {
                            Image(systemSymbol: .icloudAndArrowUp)
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .symbolEffect(.pulse)
                        } else {
                            Image(systemSymbol: .icloudAndArrowUp)
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }
                }
            }
        }
        .buttonStyle(ListButtonStyle(
            selected: fileState.currentLocalFile == file || isWaitingForOpeningFile
        ))
        .contextMenu {
            contextMenu()
                .labelStyle(.titleAndIcon)
        }
        .modifier(
            RenameSheetViewModifier(
                isPresented: $isRenameSheetPresented,
                name: file.deletingPathExtension().lastPathComponent
            ) { newName in
                renameFile(newName: newName)
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .fileXattrDidModified)) { output in
            if let path = output.object as? String, self.file.filePath == path {
                DispatchQueue.main.async {
                    updateICloudFileState()
                }
//                do {
//                    let resources = try self.file.resourceValues(forKeys: [
//                        .ubiquitousItemDownloadingStatusKey,
//                        .ubiquitousItemIsDownloadingKey
//                    ])
//                    if let downloadingStatus = resources.ubiquitousItemDownloadingStatus,
//                       let isDownloading = resources.ubiquitousItemIsDownloading {
//
//                    }
//                } catch {
//                    
//                }
            }
        }
        .watchImmediately(of: file) { newValue in
            updateModifiedDate()
            updateICloudFileState()
            isWaitingForOpeningFile = false
        }
        .onChange(of: updateFlag) { _ in
            updateModifiedDate()
            updateICloudFileState()
        }
        .onChange(of: fileState.currentLocalFile) { newValue in
            if newValue != file && isWaitingForOpeningFile {
                isWaitingForOpeningFile = false
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        // Rename
        Button {
            isRenameSheetPresented.toggle()
        } label: {
            Label(.localizable(.sidebarFileRowContextMenuRename), systemSymbol: .squareAndPencil)
                .foregroundStyle(.red)
        }

        Button {
            do {
                guard let folder = fileState.currentLocalFolder else { return }
                try folder.withSecurityScopedURL { scopedURL in
                    let file = try ExcalidrawFile(contentsOf: file)
                    
                    var newFileName = self.file.deletingPathExtension().lastPathComponent
                    while FileManager.default.fileExists(at: scopedURL.appendingPathComponent(newFileName, conformingTo: .excalidrawFile)) {
                        let components = newFileName.components(separatedBy: "-")
                        if components.count == 2, let numComponent = components.last, let index = Int(numComponent) {
                            newFileName = "\(components[0])-\(index+1)"
                        } else {
                            newFileName = "\(newFileName)-1"
                        }
                    }
                    
                    let newURL = self.file.deletingLastPathComponent().appendingPathComponent(newFileName, conformingTo: .excalidrawFile)
                    
                    let fileCoordinator = NSFileCoordinator()
                    fileCoordinator.coordinate(writingItemAt: newURL, options: .forReplacing, error: nil) { url in
                        do {
                            try file.content?.write(to: url)
                        } catch {
                            alertToast(error)
                        }
                    }
                }
            } catch {
                
            }
        } label: {
            Label(.localizable(.sidebarFileRowContextMenuDuplicate), systemSymbol: .docOnDoc)
                .foregroundStyle(.red)
        }

        moveLocalFileMenu()
        
#if os(macOS)
        Button {
#if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.file.filePath, forType: .string)
#elseif canImport(UIKit)
            UIPasteboard.general.setObjects([self.file.filePath])
#endif
        } label: {
            Label(.localizable(.sidebarLocalFileRowContextMenuCopyPath), systemSymbol: .arrowRightDocOnClipboard)
                .foregroundStyle(.red)
        }
        
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([self.file])
        } label: {
            Label(.localizable(.generalButtonRevealInFinder), systemSymbol: .docViewfinder)
                .foregroundStyle(.red)
        }
#endif
        Divider()
        
        // Delete
        Button {
            moveToTrash()
        } label: {
            Label(.localizable(.generalButtonMoveToTrash), systemSymbol: .trash)
                .foregroundStyle(.red)
        }
    }
    
    @MainActor @ViewBuilder
    private func moveLocalFileMenu() -> some View {
        if let currentLocalFolder = fileState.currentLocalFolder {
            Menu {
                ForEach(topLevelLocalFolders) { folder in
                    MoveToGroupMenu(
                        destination: folder,
                        sourceGroup: currentLocalFolder,
                        childrenSortKey: \LocalFolder.filePath,
                        allowSubgroups: true
                    ) { targetFolderID in
                        moveLocalFile(to: targetFolderID)
                    }
                }
            } label: {
                Label(.localizable(.sidebarFileRowContextMenuMoveTo), systemSymbol: .trayAndArrowUp)
            }
        }
    }
    
    private func renameFile(newName: String) {
        do {
            if let folder = fileState.currentLocalFolder {
                try folder.withSecurityScopedURL { _ in
                    let newURL = file.deletingLastPathComponent()
                        .appendingPathComponent(
                            newName,
                            conformingTo: .excalidrawFile
                        )
                    try FileManager.default.moveItem(at: file, to: newURL)
                    
                    // Update local file ID mapping
                    ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                    self.fileState.currentLocalFile = newURL
                    ExcalidrawFile.localFileURLIDMapping[file] = nil
                    
                    // Also update checkpoints
                    updateCheckpoints(oldURL: self.file, newURL: newURL)
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func moveLocalFile(to targetFolderID: NSManagedObjectID) {
        guard case let folder as LocalFolder = viewContext.object(with: targetFolderID) else { return }
        do {
            try folder.withSecurityScopedURL { scopedURL in
                let fileCoordinator = NSFileCoordinator()
                fileCoordinator.coordinate(writingItemAt: scopedURL, options: .forMoving, error: nil) { url in
                    do {
                        try FileManager.default.moveItem(
                            at: self.file,
                            to: url.appendingPathComponent(
                                self.file.lastPathComponent,
                                conformingTo: .excalidrawFile
                            )
                        )
                    } catch {
                        alertToast(error)
                    }
                }
            }
            
            if let newURL = folder.url?.appendingPathComponent(
                self.file.lastPathComponent,
                conformingTo: .excalidrawFile
            ) {
                // Update local file ID mapping
                ExcalidrawFile.localFileURLIDMapping[newURL] = ExcalidrawFile.localFileURLIDMapping[file]
                ExcalidrawFile.localFileURLIDMapping[file] = nil
                
                // Also update checkpoints
                updateCheckpoints(oldURL: self.file, newURL: newURL)
            }
            
            if fileState.currentLocalFile == self.file {
                DispatchQueue.main.async {
                    fileState.currentLocalFolder = folder
                    fileState.expandToGroup(folder.objectID)
                }
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func updateCheckpoints(oldURL: URL, newURL: URL) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                try await context.perform {
                    let fetchRequest = NSFetchRequest<LocalFileCheckpoint>(entityName: "LocalFileCheckpoint")
                    fetchRequest.predicate = NSPredicate(format: "url = %@", oldURL as NSURL)
                    let checkpoints = try context.fetch(fetchRequest)
                    checkpoints.forEach {
                        $0.url = newURL
                    }
                    try context.save()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func updateModifiedDate() {
        self.modifiedDate = .distantPast
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.filePath)
            if let modifiedDate = attributes[FileAttributeKey.modificationDate] as? Date {
                self.modifiedDate = modifiedDate
            }
        } catch {
            print(error)
            DispatchQueue.main.async {
                alertToast(error)
            }
        }
    }
    
    private func updateICloudFileState() {
        do {
            let resourceValues = try self.file.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemIsDownloadingKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsUploadedKey,
                .ubiquitousItemIsUploadingKey,
            ])
            
            if resourceValues.isUbiquitousItem == true {
                var iCloudState = ICloudState()
                if let status = resourceValues.ubiquitousItemDownloadingStatus {
                    iCloudState.downloadStatus = status
                }
                if let isDownloading = resourceValues.ubiquitousItemIsDownloading {
                    iCloudState.isDownloading = isDownloading
                }
                if let isUploading = resourceValues.ubiquitousItemIsUploading {
                    iCloudState.isUploading = isUploading
                }
                if let isUploaded = resourceValues.ubiquitousItemIsUploaded {
                    iCloudState.isUploaded = isUploaded
                }
                self.iCloudState = iCloudState
                
                if isWaitingForOpeningFile, iCloudState.downloadStatus == .current {
                    isWaitingForOpeningFile = false
                    fileState.currentLocalFile = file
                }
            } else {
                iCloudState = nil
            }
        } catch {
            alertToast(error)
        }
    }
    
    private func moveToTrash() {
        do {
            if let folder = fileState.currentLocalFolder {
                try folder.withSecurityScopedURL { _ in
                    // Item removed will be handled in `LocalFilesListView`
                    let fileCoordinator = NSFileCoordinator()
                    fileCoordinator.coordinate(
                        writingItemAt: self.file,
                        options: .forDeleting,
                        error: nil
                    ) { url in
                        do {
                            try FileManager.default.trashItem(
                                at: url,
                                resultingItemURL: nil
                            )
                        } catch {
                            alertToast(error)
                        }
                    }
                }
                
                // Should change current local file...
                let folderURL = self.file.deletingLastPathComponent()
                let contents = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.nameKey])
                let file = contents.first(where: {$0.pathExtension == "excalidraw"})
                fileState.currentLocalFile = file
            }
        } catch {
            alertToast(error)
        }
    }
}

class ICloudFileMonitor: NSObject {
    public static var shared = ICloudFileMonitor()
    
    private var query: NSMetadataQuery?

    func startMonitoring() {
        query = NSMetadataQuery()
        // 指定搜索范围为 iCloud 数据区域（例如：Documents 或 Data）
        query?.searchScopes = [NSMetadataQueryUbiquitousDataScope]

        // 监听查询状态更新
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(queryUpdated(_:)),
                                               name: .NSMetadataQueryDidUpdate,
                                               object: query)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(queryUpdated(_:)),
                                               name: .NSMetadataQueryDidFinishGathering,
                                               object: query)

        query?.start()
    }

    @objc private func queryUpdated(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }

        for item in query.results {
            if let metadataItem = item as? NSMetadataItem,
               let fileURL = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL,
               let status = metadataItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String {
                print("文件 \(fileURL.lastPathComponent) 状态更新: \(status)")
            }
        }
    }

    func stopMonitoring() {
        query?.stop()
        query = nil
        NotificationCenter.default.removeObserver(self)
    }
}
