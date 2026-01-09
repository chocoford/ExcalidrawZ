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
    @State private var fileStatus: FileStatus?
    @FocusState private var isFocused: Bool
    
    var isSelected: Bool {
        fileState.currentActiveFile == .file(file)
    }
    
    var body: some View {
        if fileStatus?.contentAvailability == .missing {
            content()
                .modifier(MissingFileContextMenuModifier(file: .file(file)))
        } else {
            content()
                .modifier(FileContextMenuModifier(file: file))
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        MissingFileMenuProvider(file: .file(file)) { triggers in
            FileRowButton(
                isSelected: isSelected,
                isMultiSelected: fileState.selectedFiles.contains(file)
            ) {
#if os(macOS)
                if NSEvent.modifierFlags.contains(.shift) {
                    // 1. If this is the first shift-click, remember it and select that file.
                    // Shift don't change the start file.
                    if fileState.selectedFiles.isEmpty {
                        fileState.selectedFiles.insert(file)
                        fileState.selectedStartFile = file
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
                    guard FileStatusService.shared.statusBox(for: .file(file)).status.contentAvailability != .missing else {
                        triggers.onToggleTryToRecover()
                        return
                    }
                    activeFile(file)
                    fileState.selectedStartFile = file
                }
#else
                guard FileStatusService.shared.statusBox(for: .file(file)).status.contentAvailability != .missing else {
                    triggers.onToggleTryToRecover()
                    return
                }
                activeFile(file)
                fileState.selectedStartFile = file
#endif
            } label: {
                FileRowLabel(
                    updatedAt: file.updatedAt ?? .distantPast,
                    isInTrash: file.inTrash == true
                ) {
                  Text(file.name ?? ""/* + " - \(file.rank)"*/)
                    .foregroundStyle(
                        fileStatus?.contentAvailability == .missing
                        ? AnyShapeStyle(Color.red)
                        : AnyShapeStyle(HierarchicalShapeStyle.primary)
                    )
                } nameTrailingView: {
                    if fileStatus?.contentAvailability == .missing {
                        Image(systemSymbol: .exclamationmarkTriangle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .modifier(FileRowDragDropModifier(file: file, sameGroupFiles: files))
        .bindFileStatus(for: .file(file), status: $fileStatus)
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
