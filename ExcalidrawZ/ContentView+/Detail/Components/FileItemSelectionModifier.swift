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

    var cloudStorageReference: CloudStorageDocumentReference? {
        if case .cloudStorageFile(let reference) = self { reference } else { nil }
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

    var cloudStorageFileSiblings: [CloudStorageDocumentReference] {
        let siblings: [CloudStorageDocumentReference] = selectionSiblings?.compactMap {
            if case .cloudStorageFile(let reference) = $0 { reference } else { nil }
        } ?? []
        if !siblings.isEmpty { return siblings }
        if let reference = file.cloudStorageReference { return [reference] }
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
            case .cloudStorageFile(let reference):
                return fileState.selectedCloudStorageFiles.contains(reference)
        }
    }
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    performSelect()
                }
            )
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

    private func performSelect() {
        switch file {
            case .file(let file):
                performFileSelect(file)
            case .localFile(let url):
                performLocalFileSelect(url)
            case .temporaryFile(let url):
                performTemporaryFileSelect(url)
            case .collaborationFile:
                break
            case .cloudStorageFile(let reference):
                performCloudStorageFileSelect(reference)
        }
    }

    private func performFileSelect(_ file: File) {
#if os(macOS)
        if NSEvent.modifierFlags.contains(.shift), canMultiSelect {
            if fileState.selectedFiles.isEmpty {
                fileState.selectedFiles.insert(file)
            } else {
                let siblings = fileSiblings
                guard let startFile = fileState.selectedStartFile,
                      let startIdx = siblings.firstIndex(of: startFile),
                      let endIdx = siblings.firstIndex(of: file) else {
                    return
                }
                let range = startIdx <= endIdx ? startIdx...endIdx : endIdx...startIdx
                fileState.selectedFiles = Set(siblings[range])
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

    private func performLocalFileSelect(_ url: URL) {
#if os(macOS)
        if NSEvent.modifierFlags.contains(.shift), canMultiSelect {
            if fileState.selectedLocalFiles.isEmpty {
                fileState.selectedLocalFiles.insert(url)
            } else {
                let siblings = localFileSiblings
                guard let startFile = fileState.selectedStartLocalFile,
                      let startIdx = siblings.firstIndex(of: startFile),
                      let endIdx = siblings.firstIndex(of: url) else {
                    return
                }
                let range = startIdx <= endIdx ? startIdx...endIdx : endIdx...startIdx
                fileState.selectedLocalFiles = Set(siblings[range])
                if fileState.selectedStartLocalFile == nil {
                    fileState.selectedStartLocalFile = url
                }
            }
        } else if NSEvent.modifierFlags.contains(.command), canMultiSelect {
            fileState.selectedLocalFiles.insertOrRemove(url)
            fileState.selectedStartLocalFile = url
        } else {
            if !canMultiSelect {
                fileState.resetSelections()
            }
            fileState.selectedLocalFiles = [url]
            fileState.selectedStartLocalFile = url
        }
#else
        if editMode?.wrappedValue.isEditing == true {
            fileState.selectedLocalFiles = [url]
            fileState.selectedStartLocalFile = url
        }
#endif
    }

    private func performTemporaryFileSelect(_ url: URL) {
#if os(macOS)
        if NSEvent.modifierFlags.contains(.shift), canMultiSelect {
            if fileState.selectedTemporaryFiles.isEmpty {
                fileState.selectedTemporaryFiles.insert(url)
            } else {
                let siblings = temporaryFileSiblings
                guard let startFile = fileState.selectedStartTemporaryFile,
                      let startIdx = siblings.firstIndex(of: startFile),
                      let endIdx = siblings.firstIndex(of: url) else {
                    return
                }
                let range = startIdx <= endIdx ? startIdx...endIdx : endIdx...startIdx
                fileState.selectedTemporaryFiles = Set(siblings[range])
                if fileState.selectedStartTemporaryFile == nil {
                    fileState.selectedStartTemporaryFile = url
                }
            }
        } else if NSEvent.modifierFlags.contains(.command), canMultiSelect {
            fileState.selectedTemporaryFiles.insertOrRemove(url)
            fileState.selectedStartTemporaryFile = url
        } else {
            if !canMultiSelect {
                fileState.resetSelections()
            }
            fileState.selectedTemporaryFiles = [url]
            fileState.selectedStartTemporaryFile = url
        }
#else
        if editMode?.wrappedValue.isEditing == true {
            fileState.selectedTemporaryFiles = [url]
            fileState.selectedStartTemporaryFile = url
        }
#endif
    }

    private func performCloudStorageFileSelect(_ reference: CloudStorageDocumentReference) {
#if os(macOS)
        if NSEvent.modifierFlags.contains(.shift), canMultiSelect {
            if fileState.selectedCloudStorageFiles.isEmpty {
                fileState.selectedCloudStorageFiles.insert(reference)
            } else {
                let siblings = cloudStorageFileSiblings
                guard let startFile = fileState.selectedStartCloudStorageFile,
                      let startIdx = siblings.firstIndex(of: startFile),
                      let endIdx = siblings.firstIndex(of: reference) else {
                    return
                }
                let range = startIdx <= endIdx ? startIdx...endIdx : endIdx...startIdx
                fileState.selectedCloudStorageFiles = Set(siblings[range])
            }
            if fileState.selectedStartCloudStorageFile == nil {
                fileState.selectedStartCloudStorageFile = reference
            }
        } else if NSEvent.modifierFlags.contains(.command), canMultiSelect {
            fileState.selectedCloudStorageFiles.insertOrRemove(reference)
            fileState.selectedStartCloudStorageFile = reference
        } else {
            if !canMultiSelect {
                fileState.resetSelections()
            }
            fileState.selectedCloudStorageFiles = [reference]
            fileState.selectedStartCloudStorageFile = reference
        }
#else
        if editMode?.wrappedValue.isEditing == true {
            fileState.selectedCloudStorageFiles.insertOrRemove(reference)
            fileState.selectedStartCloudStorageFile = reference
        }
#endif
    }
}
