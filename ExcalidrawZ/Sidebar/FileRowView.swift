//
//  FileRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/29.
//

import SwiftUI
import SwiftyAlert
import CoreData
import UniformTypeIdentifiers

import ChocofordUI

struct FileRowView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var lockedContentState: LockedContentStateStore
    
    @ObservedObject var file: File
    var files: FetchedResults<File>
    var fileState: FileState
    
    init(file: File, sameGroupFiles files: FetchedResults<File>, fileState: FileState) {
        self.file = file
        self.files = files
        self.fileState = fileState
    }
    
    init(
        file: File,
        files: FetchedResults<File>,
        fileState: FileState
    ) {
        self.file = file
        self.files = files
        self.fileState = fileState
    }
    
    @State private var showPermanentlyDeleteAlert: Bool = false
    @State private var fileStatus: FileStatus?
    @StateObject private var selectionState = SidebarFileRowSelectionState()
    @FocusState private var isFocused: Bool

    private var currentFileStatus: FileStatus {
        fileStatus ?? FileStatusService.shared.statusBox(for: .file(file)).status
    }
    
    var body: some View {
        if currentFileStatus.contentAvailability == .missing {
            MissingFileMenuProvider(file: .file(file)) { triggers in
                content(onToggleTryToRecover: triggers.onToggleTryToRecover)
                    .contextMenu {
                        MissingFileMenuItems(
                            file: .file(file)
                        ) {
                            triggers.onToggleTryToRecover()
                        } onToggleDelete: {
                            triggers.onToggleDelete()
                        }
                        .labelStyle(.titleAndIcon)
                    }
            }
        } else {
            content()
                .modifier(FileContextMenuWithFileStateModifier(file: file, fileState: fileState))
        }
    }
    
    @ViewBuilder
    private func content(onToggleTryToRecover: (() -> Void)? = nil) -> some View {
        FileRowButton(
            isSelected: selectionState.isSelected,
            isMultiSelected: selectionState.isMultiSelected
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
                    onToggleTryToRecover?()
                    return
                }
                activeFile(file)
                fileState.selectedStartFile = file
            }
#else
            guard FileStatusService.shared.statusBox(for: .file(file)).status.contentAvailability != .missing else {
                onToggleTryToRecover?()
                return
            }
            activeFile(file)
            fileState.selectedStartFile = file
#endif
        } label: {
            FileRowLabel(
                updatedAt: file.updatedAt ?? .distantPast,
                isInTrash: file.inTrash == true,
                lockState: lockedContentState.previewLockState(for: .file(file)) ?? .plaintext
            ) {
                Text(file.name ?? ""/* + " - \(file.rank)"*/)
                    .foregroundStyle(
                        currentFileStatus.contentAvailability == .missing
                        ? AnyShapeStyle(Color.red)
                        : AnyShapeStyle(HierarchicalShapeStyle.primary)
                    )
            } nameTrailingView: {
                if currentFileStatus.contentAvailability == .missing {
                    Image(systemSymbol: .exclamationmarkTriangle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .modifier(FileRowDragDropModifier(file: file, sameGroupFiles: files))
        .bindFileStatus(for: .file(file), status: $fileStatus)
        .onAppear {
            selectionState.bind(file: file, fileState: fileState)
        }
        .task(id: file.objectID.uriRepresentation()) {
            guard lockedContentState.previewLockState(for: .file(file)) == nil else { return }
            await lockedContentState.refresh(file: .file(file))
        }
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
                    fileState.setActiveGroupIfNeeded(.group(trashGroup))
                }
            } else if let group = file.group {
                fileState.setActiveGroupIfNeeded(.group(group))
            }
        }
    }
}

func withOpenFileDelay(_ action: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        action()
    }
}
