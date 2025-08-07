//
//  TemporaryFileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/7/25.
//

import SwiftUI

struct TemporaryFileRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    
    var file: URL
    
    @State private var modifiedDate: Date = .distantPast
    
    var body: some View {
        FileRowButton(
            name: file.deletingPathExtension().lastPathComponent,
            updatedAt: modifiedDate,
            isSelected: {
                if case .temporaryFile(let tempFile) = fileState.currentActiveFile {
                    return tempFile == file
                } else {
                    return false
                }
            }(),
            isMultiSelected: fileState.selectedTemporaryFiles.contains(file)
        ) {
#if os(macOS)
            if NSEvent.modifierFlags.contains(.shift) {
                let files = fileState.temporaryFiles
                if fileState.selectedStartTemporaryFile == nil {
                    fileState.selectedStartTemporaryFile = file
                    fileState.selectedTemporaryFiles.insert(file)
                } else {
                    guard let startFile = fileState.selectedStartTemporaryFile,
                          let startIdx = files.firstIndex(of: startFile),
                          let endIdx = files.firstIndex(of: file) else {
                        return
                    }
                    let range = startIdx <= endIdx
                    ? startIdx...endIdx
                    : endIdx...startIdx
                    let sliceItems = files[range]
                    let sliceSet = Set(sliceItems)
                    fileState.selectedTemporaryFiles = sliceSet
                }
            } else if NSEvent.modifierFlags.contains(.command) {
                if fileState.selectedTemporaryFiles.isEmpty {
                    fileState.selectedStartTemporaryFile = file
                }
                fileState.selectedTemporaryFiles.insertOrRemove(file)
            } else {
                fileState.currentActiveFile = .temporaryFile(file)
            }
#else
            fileState.currentTemporaryFile = file
#endif
        }
        .modifier(TemporaryFileContextMenuModifier(file: file))
        .watchImmediately(of: file) { newValue in
            updateModifiedDate()
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
