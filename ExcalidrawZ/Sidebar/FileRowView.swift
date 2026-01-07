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
    
    init(file: File, sameGroupFiles files: FetchedResults<File>) {
        self.file = file
        self.files = files
    }
    
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
            if NSEvent.modifierFlags.contains(.shift) {
                // 1. If this is the first shift-click, remember it and select that file.
                // Shift don't change the start file.
                if fileState.selectedFiles.isEmpty {
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
                fileState.selectedFiles.insertOrRemove(file)
                fileState.selectedStartFile = file
            } else {
                activeFile(file)
                fileState.selectedStartFile = file
            }
#else
            activeFile(file)
            fileState.selectedStartFile = file
#endif
        }
        .modifier(FileRowDragDropModifier(file: file, sameGroupFiles: files))
        .modifier(FileContextMenuModifier(file: file))
    }
    
    private func activeFile(_ file: File) {
        fileState.setActiveFile(.file(file))

        withOpenFileDelay {
            if file.inTrash {
                if let trashGroup = {
                    let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
                    fetchRequest.predicate = NSPredicate(format: "type == 'trash'")
                    return (try? viewContext.fetch(fetchRequest))?.first
                }() {
                    fileState.currentActiveGroup = .group(trashGroup)
                }
            } else if let group = file.group {
                fileState.currentActiveGroup = .group(group)
            }
        }
    }
}

func withOpenFileDelay(_ action: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        action()
    }
}
