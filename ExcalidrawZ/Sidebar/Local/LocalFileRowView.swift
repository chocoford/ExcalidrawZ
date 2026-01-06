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
    @State private var fileStatus: FileStatus?
    private var iCloudState: ICloudFileStatus? {
        fileStatus?.iCloudStatus
    }
    
    
    @State private var isDeleteConfirmationDialogPresented = false
    
    @State private var isWaitingForOpeningFile = false

    var body: some View {
        FileRowButton(
            isSelected: fileState.currentActiveFile == .localFile(file) || isWaitingForOpeningFile,
            isMultiSelected: fileState.selectedLocalFiles.contains(file)
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
                    } else if iCloudState != .downloaded {
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
//                    } else {
//                        Text(String(describing: iCloudState))
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
        .onChange(of: updateFlag) { _ in
            updateModifiedDate()
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
    
}
