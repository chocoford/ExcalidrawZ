//
//  FileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

import ChocofordUI

struct FileRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject var fileState: FileState
    
    var file: File
    var files: FetchedResults<File>
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil"),
        animation: .default
    )
    var topLevelGroups: FetchedResults<Group>
    
    init(
        file: File,
        files: FetchedResults<File>,
    ) {
        self.file = file
        self.files = files
    }
    
    @State private var showPermanentlyDeleteAlert: Bool = false
    
    @FocusState private var isFocused: Bool
    
    var isSelected: Bool {
        fileState.currentActiveFile == .file(file)
    }
    
    var body: some View {
        FileRowButton(
            name: (file.name ?? "")/* + " - \(file.rank)"*/,
            updatedAt: file.updatedAt,
            isInTrash: file.inTrash == true,
            isSelected: isSelected,
            isMultiSelected: fileState.selectedFiles.contains(file)
        ) {
#if os(macOS)
            if fileState.selectedFiles.isEmpty {
                fileState.selectedStartFile = nil
            }
            
            if NSEvent.modifierFlags.contains(.shift) {
                // 1. If this is the first shift-click, remember it and select that file.
                if fileState.selectedStartFile == nil {
                    fileState.selectedStartFile = file
                    fileState.selectedFiles.insert(file)
                } else {
                    guard let startFile = fileState.selectedStartFile,
                          let startIdx = files.firstIndex(of: startFile),
                          let endIdx = files.firstIndex(of: file) else {
                        return
                    }
                    let range = startIdx <= endIdx
                    ? startIdx...endIdx
                    : endIdx...startIdx
                    let sliceItems = files[range]
                    let sliceSet = Set(sliceItems)
                    fileState.selectedFiles = sliceSet
                }
            } else if NSEvent.modifierFlags.contains(.command) {
                if fileState.selectedFiles.isEmpty {
                    fileState.selectedStartFile = file
                }
                fileState.selectedFiles.insertOrRemove(file)
            } else {
                if let group = file.group {
                    fileState.currentActiveGroup = .group(group)
                }
                fileState.currentActiveFile = .file(file)
            }
#else
            if let group = file.group {
                fileState.currentActiveGroup = .group(group)
            }
            fileState.currentActiveFile = .file(file)
#endif
        }
        .modifier(FileRowDragDropModifier(file: file, files: files))
        .modifier(FileContextMenuModifier(file: file))
    }
}
