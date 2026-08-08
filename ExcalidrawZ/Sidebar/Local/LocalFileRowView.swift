//
//  LocalFileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/24/25.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

import ChocofordUI

extension Notification.Name {
    static var fileMetadataDidModified = Notification.Name("FileMetadataDidModified")
    static var fileXattrDidModified = Notification.Name("FileXattrDidModified")
}

struct LocalFileRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    var file: URL
    var updateFlag: Date?
    var files: [URL]
    var fileState: FileState
    
    init(file: URL, updateFlag: Date?, files: [URL], fileState: FileState) {
        self.file = file
        self.updateFlag = updateFlag
        self.files = files
        self.fileState = fileState
    }
    
    struct ICloudState {
        var downloadStatus: URLUbiquitousItemDownloadingStatus = .notDownloaded
        var isDownloading = false
        var isUploading = false
        var isUploaded = false
    }
    
    @State private var modifiedDate: Date = .distantPast
    @State private var fileStatus: FileStatus?
    private var iCloudState: ICloudFileStatus? {
        fileStatus?.iCloudStatus
    }
    
    
    @State private var isDeleteConfirmationDialogPresented = false
    
    @State private var isWaitingForOpeningFile = false
    @StateObject private var selectionState = SidebarLocalFileRowSelectionState()

    var body: some View {
        FileRowButton(
            isSelected: selectionState.isSelected || isWaitingForOpeningFile,
            isMultiSelected: selectionState.isMultiSelected
        ) {
#if os(macOS)
            if NSEvent.modifierFlags.contains(.shift) {
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
            var fileType: UTType {
                file.pathExtension == "svg"
                ? .excalidrawSVG
                : file.pathExtension == "png"
                ? .excalidrawPNG
                : .excalidrawFile
            }
            
            
            FileRowLabel(
                name: fileType == .excalidrawPNG || fileType == .excalidrawSVG
                ? file.deletingPathExtension().deletingPathExtension().lastPathComponent
                : file.deletingPathExtension().lastPathComponent,
                fileType: fileType,
                updatedAt: modifiedDate
            ) {
                if let iCloudState {
                    if isWaitingForOpeningFile {
                        ProgressView()
                            .controlSize(.mini)
                    } else if iCloudState != .downloaded && iCloudState != .local {
                        Image(systemSymbol: .icloudAndArrowDown)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    } else if iCloudState == .uploading {
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
        .bindFileStatus(for: .localFile(file), status: $fileStatus)
        .watch(value: file) { newValue in
            updateModifiedDate()
            isWaitingForOpeningFile = false
        }
        .watch(value: updateFlag) { _ in
            updateModifiedDate()
        }
        .onAppear {
            selectionState.bind(file: file, fileState: fileState)
        }
        .onReceive(fileState.$activeFiles) { activeFiles in
            if isWaitingForOpeningFile,
               !activeFiles.contains(where: { $0 == .localFile(file) }) {
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
        let file = self.file
        Task {
            do {
                let modifiedDate = try await LocalFolder.modificationDate(
                    forLocalFileAt: file
                )
                guard self.file == file else { return }
                self.modifiedDate = modifiedDate ?? .distantPast
            } catch {
                guard self.file == file else { return }
                self.modifiedDate = .distantPast
                alertToast(error)
            }
        }
    }
    
}
