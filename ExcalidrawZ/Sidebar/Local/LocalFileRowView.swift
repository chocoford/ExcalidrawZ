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
    var files: [URL]
    
    init(file: URL, updateFlag: Date?, files: [URL]) {
        self.file = file
        self.updateFlag = updateFlag
        self.files = files
    }
    
    struct ICloudState {
        var downloadStatus: URLUbiquitousItemDownloadingStatus = .notDownloaded
        var isDownloading = false
        var isUploading = false
        var isUploaded = false
    }
    
    @State private var modifiedDate: Date = .distantPast
    @State private var iCloudState: ICloudState?
    
    @State private var isDeleteConfirmationDialogPresented = false
    
    @State private var isWaitingForOpeningFile = false

    var body: some View {
        FileRowButton(
            isSelected: fileState.currentActiveFile == .localFile(file) || isWaitingForOpeningFile,
            isMultiSelected: fileState.selectedLocalFiles.contains(file)
        ) {
#if os(macOS)
            if let iCloudState, iCloudState.downloadStatus != .current {
                // request iCloud download first
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: file)
                    isWaitingForOpeningFile = true
                } catch {
                    alertToast(error)
                }
            } else if NSEvent.modifierFlags.contains(.shift) {
                // 1. If this is the first shift-click, remember it and select that file.
                if fileState.selectedLocalFiles.isEmpty {
                    fileState.selectedLocalFiles.insert(file)
                } else {
                    guard let startFile = fileState.selectedStartLocalFile,
                          let startIdx = files.firstIndex(of: startFile),
                          let endIdx = files.firstIndex(of: file) else {
                        return
                    }
                    let range = startIdx <= endIdx
                    ? startIdx...endIdx
                    : endIdx...startIdx
                    let sliceItems = files[range]
                    let sliceSet = Set(sliceItems)
                    fileState.selectedLocalFiles = sliceSet
                }
            } else if NSEvent.modifierFlags.contains(.command) {
                fileState.selectedLocalFiles.insertOrRemove(file)
                fileState.selectedStartLocalFile = file
            } else {
                activeFile(file)
                fileState.selectedStartLocalFile = file
            }
#else
            activeFile(file)
            fileState.selectedStartLocalFile = file
#endif
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
                        if #available(macOS 15.0, iOS 18.0, *) {
                            Image(systemSymbol: .icloudAndArrowUp)
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                                .symbolEffect(.breathe)
                        } else if #available(macOS 14.0, iOS 17.0, *) {
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
        .modifier(LocalFileRowContextMenuModifier(file: file))
        .modifier(LocalFileDragModifier(file: file))
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
        .watch(value: file) { newValue in
            updateModifiedDate()
            updateICloudFileState()
            isWaitingForOpeningFile = false
        }
        .onChange(of: updateFlag) { _ in
            updateModifiedDate()
            updateICloudFileState()
        }
        .onChange(of: fileState.currentActiveFile) { newValue in
            if case .localFile(let localFile) = newValue,
               localFile != file,
               isWaitingForOpeningFile {
                isWaitingForOpeningFile = false
            }
        }
    }
    
    private func activeFile(_ file: URL) {
        fileState.setActiveFile(.localFile(file))

        withOpenFileDelay {
            // fetch file's folder
            let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
            fetchRequest.predicate = NSPredicate(format: "url == %@", file.deletingLastPathComponent() as CVarArg)
            fetchRequest.fetchLimit = 1
            
            if let folder = (try? viewContext.fetch(fetchRequest))?.first {
                fileState.currentActiveGroup = .localFolder(folder)
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
                    fileState.setActiveFile(.localFile(file))
                }
            } else {
                iCloudState = nil
            }
        } catch {
            alertToast(error)
        }
    }
    
}
