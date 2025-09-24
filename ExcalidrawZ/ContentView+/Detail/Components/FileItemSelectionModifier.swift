//
//  FileItemSelectionModifier.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/19/25.
//

import SwiftUI

struct FileHomeItemSelectModifier: ViewModifier {
    @EnvironmentObject var fileState: FileState
    
    var file: FileState.ActiveFile
    var sortField: ExcalidrawFileSortField
    var canMultiSelect: Bool
    
    @StateObject private var localFolderState = LocalFolderState()
    
    var isSelected: Bool {
        switch file {
            case .file(let file):
                return fileState.selectedFiles.contains(file)
            case .localFile(let url):
                return fileState.selectedLocalFiles.contains(url)
            case .temporaryFile(let url):
                return fileState.selectedTemporaryFiles.contains(url)
            case .collaborationFile:
                return false
        }
    }
    
    func body(content: Content) -> some View {
        ZStack {
            switch file {
                case .file(let file):
                    content
                        .modifier(
                            FileSelectionModifier(
                                file: file,
                                sortField: sortField,
                                canMultiSelect: canMultiSelect
                            )
                        )
                case .localFile(let url):
                    LocalFilesProvider.withSibling(
                        file: url,
                        sortField: .updatedAt
                    ) { files, updateFlags in
                        content
                            .modifier(
                                LocalFileSelectionModifier(
                                    file: url,
                                    files: files,
                                    canMultiSelect: canMultiSelect
                                )
                            )
                    }
                    .environmentObject(localFolderState)
                case .temporaryFile(let url):
                    content
                        .modifier(
                            TemporaryFileSelectionModifier(
                                file: url,
                                canMultiSelect: canMultiSelect
                            )
                        )
                case .collaborationFile:
                    content
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius)
                .stroke(
                    isSelected
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(SeparatorShapeStyle())
                )
        }
    }
}

struct FileSelectionModifier: ViewModifier {
    @EnvironmentObject var fileState: FileState
    
    var file: File
    var canMultiSelect: Bool
    @FetchRequest var files: FetchedResults<File>
    
    init(file: File, sortField: ExcalidrawFileSortField, canMultiSelect: Bool) {
        self.file = file
        let group = file.group
        /// Put the important things first.
        let sortDescriptors: [SortDescriptor<File>] = {
            switch sortField {
                case .updatedAt:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse)
                    ]
                case .name:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                        SortDescriptor(\.name, order: .reverse),
                    ]
                case .rank:
                    [
                        SortDescriptor(\.rank, order: .forward),
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                    ]
            }
        }()
        self._files = FetchRequest<File>(
            sortDescriptors: sortDescriptors,
            predicate: group?.groupType == .trash
            ? NSPredicate(format: "inTrash == true")
            : group != nil
            ? NSPredicate(format: "inTrash == false AND group == %@", group!)
            : NSPredicate(format: "inTrash == false"),
            animation: .default
        )
        self.canMultiSelect = canMultiSelect
    }
 
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    performSelect()
                }
            )
    }

    private func performSelect() {
#if os(macOS)
        if NSEvent.modifierFlags.contains(.shift), canMultiSelect {
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
                if fileState.selectedStartFile == nil {
                    fileState.selectedStartFile = file
                }
            }
        } else if NSEvent.modifierFlags.contains(.command), canMultiSelect {
            fileState.selectedFiles.insertOrRemove(file)
            fileState.selectedStartFile = file
        } else {
            if !canMultiSelect {
                fileState.resetSelections()
            }
            fileState.selectedFiles = [file]
            fileState.selectedStartFile = file
        }
#else
        fileState.selectedFiles = [file]
        fileState.selectedStartFile = file
#endif
    }
}

struct LocalFileSelectionModifier: ViewModifier {
    @EnvironmentObject var fileState: FileState
    
    var file: URL
    var files: [URL]
    var canMultiSelect: Bool
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    performSelect()
                }
            )
    }
    
    private func performSelect() {
#if os(macOS)
        if NSEvent.modifierFlags.contains(.shift), canMultiSelect {
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
                if fileState.selectedStartLocalFile == nil {
                    fileState.selectedStartLocalFile = file
                }
            }
        } else if NSEvent.modifierFlags.contains(.command), canMultiSelect {
            fileState.selectedLocalFiles.insertOrRemove(file)
            fileState.selectedStartLocalFile = file
        } else {
            if !canMultiSelect {
                fileState.resetSelections()
            }
            fileState.selectedLocalFiles = [file]
            fileState.selectedStartLocalFile = file
        }
#else
        fileState.selectedLocalFiles = [file]
        fileState.selectedStartLocalFile = file
#endif
    }
    
}

struct TemporaryFileSelectionModifier: ViewModifier {
    @EnvironmentObject var fileState: FileState
    
    var file: URL
    var canMultiSelect: Bool
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    performSelect()
                }
            )
    }
    
    private func performSelect() {
#if os(macOS)
            if NSEvent.modifierFlags.contains(.shift), canMultiSelect {
                let files = fileState.temporaryFiles
                if fileState.selectedTemporaryFiles.isEmpty {
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
                    if fileState.selectedStartTemporaryFile == nil {
                        fileState.selectedStartTemporaryFile = file
                    }
                }
            } else if NSEvent.modifierFlags.contains(.command), canMultiSelect {
                fileState.selectedTemporaryFiles.insertOrRemove(file)
                fileState.selectedStartTemporaryFile = file
            } else {
                if !canMultiSelect {
                    fileState.resetSelections()
                }
                fileState.selectedTemporaryFiles = [file]
                fileState.selectedStartTemporaryFile = file
            }
#else
        fileState.selectedTemporaryFiles = [file]
        fileState.selectedStartTemporaryFile = file
#endif
    }
    
}
