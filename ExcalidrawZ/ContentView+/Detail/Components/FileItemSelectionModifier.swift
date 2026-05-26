//
//  FileItemSelectionModifier.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/19/25.
//

import SwiftUI

private extension FileState.ActiveFile {
    var fileValue: File? {
        if case .file(let file) = self { file } else { nil }
    }

    var localFileURL: URL? {
        if case .localFile(let url) = self { url } else { nil }
    }

    var temporaryFileURL: URL? {
        if case .temporaryFile(let url) = self { url } else { nil }
    }
}

struct FileHomeItemSelectModifier: ViewModifier {
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @EnvironmentObject var fileState: FileState
    
    var file: FileState.ActiveFile
    var selectionSiblings: [FileState.ActiveFile]?
    var canMultiSelect: Bool
    var style: FileHomeItemStyle
    
    init(
        file: FileState.ActiveFile,
        selectionSiblings: [FileState.ActiveFile]?,
        canMultiSelect: Bool,
        style: FileHomeItemStyle
    ) {
        self.file = file
        self.selectionSiblings = selectionSiblings
        self.canMultiSelect = canMultiSelect
        self.style = style
    }

    var fileSiblings: [File] {
        let siblings: [File] = selectionSiblings?.compactMap {
            if case .file(let file) = $0 { file } else { nil }
        } ?? []
        if !siblings.isEmpty { return siblings }
        if let file = file.fileValue { return [file] }
        return []
    }

    var localFileSiblings: [URL] {
        let siblings: [URL] = selectionSiblings?.compactMap {
            if case .localFile(let url) = $0 { url } else { nil }
        } ?? []
        if !siblings.isEmpty { return siblings }
        if let url = file.localFileURL { return [url] }
        return []
    }

    var temporaryFileSiblings: [URL] {
        let siblings: [URL] = selectionSiblings?.compactMap {
            if case .temporaryFile(let url) = $0 { url } else { nil }
        } ?? []
        if !siblings.isEmpty { return siblings }
        if let url = file.temporaryFileURL { return [url] }
        return []
    }
    
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
                                files: fileSiblings,
                                canMultiSelect: canMultiSelect
                            )
                        )
                case .localFile(let url):
                    content
                        .modifier(
                            LocalFileSelectionModifier(
                                file: url,
                                files: localFileSiblings,
                                canMultiSelect: canMultiSelect
                            )
                        )
                case .temporaryFile(let url):
                    content
                        .modifier(
                            TemporaryFileSelectionModifier(
                                file: url,
                                files: temporaryFileSiblings,
                                canMultiSelect: canMultiSelect
                            )
                        )
                case .collaborationFile:
                    content
            }
        }
#if os(iOS)
        .overlay {
            if editMode?.wrappedValue.isEditing == true {
                Circle()
                    .stroke(.white)
                    .frame(width: 20, height: 20)
                    .background {
                        if #available(iOS 26.0, macOS 26.0, *) {
                            Image(systemSymbol: .checkmarkCircleFill)
                                .resizable()
                                .scaledToFit()
                                .symbolRenderingMode(.multicolor)
                                .symbolEffect(.drawOn, options: .speed(2), isActive: !isSelected)
                        } else {
                            Image(systemSymbol: .checkmarkCircleFill)
                                .resizable()
                                .scaledToFit()
                                .opacity(isSelected ? 1 : 0)
                                .animation(.default, value: isSelected)
                        }
                    }
            }
        }
#endif
        .overlay {
            let cardNotSelectedStyle = if #available(macOS 12.0, iOS 17.0, *) {
                AnyShapeStyle(SeparatorShapeStyle())
            } else {
                AnyShapeStyle(HierarchicalShapeStyle.secondary)
            }
            if style == .card {
                RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius)
                    .stroke(
                        isSelected
                        ? AnyShapeStyle(Color.accentColor)
                        : cardNotSelectedStyle,
                        lineWidth: 0.5
                    )
            }
        }
    }
}

struct FileSelectionModifier: ViewModifier {
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @EnvironmentObject var fileState: FileState
    
    var file: File
    var files: [File]
    var canMultiSelect: Bool
    
    init(file: File, files: [File], canMultiSelect: Bool) {
        self.file = file
        self.files = files
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
        if editMode?.wrappedValue.isEditing == true {
            fileState.selectedFiles.insertOrRemove(file)
            fileState.selectedStartFile = file
        }
#endif
    }
}

struct LocalFileSelectionModifier: ViewModifier {
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
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
        if editMode?.wrappedValue.isEditing == true {
            fileState.selectedLocalFiles = [file]
            fileState.selectedStartLocalFile = file
        }
#endif
    }
    
}

struct TemporaryFileSelectionModifier: ViewModifier {
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @EnvironmentObject var fileState: FileState
    
    var file: URL
    var files: [URL]?
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
                let files = files ?? fileState.temporaryFiles
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
        if editMode?.wrappedValue.isEditing == true {   
            fileState.selectedTemporaryFiles = [file]
            fileState.selectedStartTemporaryFile = file
        }
#endif
    }
    
}
