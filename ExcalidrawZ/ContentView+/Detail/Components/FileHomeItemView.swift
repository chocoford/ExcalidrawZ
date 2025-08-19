//
//  FileHomeItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI

struct FileHomeItemPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () ->  [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

class FileItemPreviewCache: NSCache<NSString, NSImage> {
    static let shared = FileItemPreviewCache()
}

struct FileHomeItemView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState

    @Binding var isSelected: Bool
    var file: FileState.ActiveFile
    var fileID: String
    var filename: String
    var excalidrawFileGetter: (FileState.ActiveFile, NSManagedObjectContext) -> ExcalidrawFile?
    var onOpen: () -> Void
    
    init(
        file: FileState.ActiveFile,
        isSelected: Binding<Bool>,
    ) {
         self.file = file
        self._isSelected = isSelected
        switch file {
            case .file(let file):
                self.fileID = file.objectID.description
                self.filename = file.name ?? String(localizable: .generalUntitled)
            case .localFile(let url):
                self.fileID = url.absoluteString
                self.filename = url.deletingPathExtension().lastPathComponent.isEmpty
                ? String(localizable: .generalUntitled)
                : url.deletingPathExtension().lastPathComponent
            case .temporaryFile(let url):
                self.fileID = url.absoluteString
                self.filename = url.deletingPathExtension().lastPathComponent.isEmpty
                ? String(localizable: .generalUntitled)
                : url.deletingPathExtension().lastPathComponent
            case .collaborationFile(let collaborationFile):
                self.fileID = collaborationFile.objectID.description
                self.filename = collaborationFile.name ?? String(localizable: .generalUntitled)
        }
        self.excalidrawFileGetter = { activeFile, context in
            switch activeFile {
                case .file(let file):
                    return try? ExcalidrawFile(from: file.objectID, context: context)
                case .localFile(let url):
                    return try? ExcalidrawFile(contentsOf: url)
                case .temporaryFile(let url):
                    return try? ExcalidrawFile(contentsOf: url)
                case .collaborationFile(let collaborationFile):
                    return try? ExcalidrawFile(from: collaborationFile.objectID, context: context)
            }
        }
        self.onOpen = {
            
        }
    }
    
    @State private var coverImage: Image? = nil
    
    @State private var width: CGFloat?
    
    static let roundedCornerRadius: CGFloat = 12
    
    let cache = FileItemPreviewCache.shared
    
    var body: some View {
        VStack(spacing: 0) {
            if let coverImage {
                Color.clear
                    .overlay {
                        coverImage
                            .resizable()
                            .scaledToFill()
                            .allowsHitTesting(false)
                    }
                    .clipShape(Rectangle())
                    .frame(height: width == nil ? 180 : width! * 0.5625)
            } else {
                Color.clear
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 40)
                    }
                    .frame(height: width == nil ? 180 : width! * 0.5625)
            }
        }
        .readWidth($width)
        .overlay(alignment: .bottom) {
            HStack {
                Text(filename)
                    .lineLimit(1)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.roundedCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.roundedCornerRadius)
                .stroke(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(SeparatorShapeStyle()))
        }
        .background {
            RoundedRectangle(cornerRadius: Self.roundedCornerRadius)
                .fill(.background)
                .shadow(color: Color.gray.opacity(0.2), radius: 4)
        }
        .background {
            Color.clear
                .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                    [fileID+"SOURCE": value]
                }
        }
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    openFile()
                })
                .simultaneousGesture(TapGesture().onEnded {
                    isSelected = true
                })
                .modifier(FileHomeItemContextMenuModifier(file: file))
        }
        .opacity(fileHomeItemTransitionState.shouldHideItem == fileID ? 0 : 1)
        .onChange(of: file) { newValue in
            self.getElementsImage()
        }
        .onAppear {
            if let image = cache.object(forKey: fileID as NSString) {
                Task.detached {
                    let image = Image(platformImage: image)
                    await MainActor.run {
                        self.coverImage = image
                    }
                }
            } else {
                self.getElementsImage()
            }
        }
    }
    
    private func getElementsImage() {
        if let excalidrawFile = excalidrawFileGetter(file, viewContext) {
            Task {
                while fileState.excalidrawWebCoordinator?.isLoading == true {
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * 1))
                }
                
                if let image = try? await fileState.excalidrawWebCoordinator?.exportElementsToPNG(
                    elements: excalidrawFile.elements,
                    colorScheme: colorScheme
                ) {
                    Task.detached {
                        await MainActor.run {
                            cache.setObject(image, forKey: fileID as NSString)
                        }
                        let image = Image(platformImage: image)
                        await MainActor.run {
                            self.coverImage = image
                        }
                    }
                }
            }
        }
    }
    
    private func openFile() {
        fileState.currentActiveFile = file
        
        switch file {
            case .file(let file):
                
                let getTrashGroup: () -> Group? = {
                    let trashGroupFetchRequest = NSFetchRequest<Group>(entityName: "Group")
                    trashGroupFetchRequest.predicate = NSPredicate(format: "type == 'trash'")
                    return try? viewContext.fetch(trashGroupFetchRequest).first
                }
                
                fileState.currentActiveGroup = file.group == nil
                ? nil
                : file.inTrash
                ? .group(getTrashGroup() ?? file.group!)
                : .group(file.group!)
                
                if let groupID = file.group?.objectID, file.inTrash == false {
                    fileState.expandToGroup(groupID)
                }
            case .localFile(let url):
                do {
                    let fetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                    fetchRequest.predicate = NSPredicate(format: "url == %@", url.deletingLastPathComponent() as NSURL)
                    fetchRequest.fetchLimit = 1
                    let folders = try viewContext.fetch(fetchRequest)
                    if let folder = folders.first {
                        fileState.currentActiveGroup = .localFolder(folder)
                    } else {
                        // Handle case where local folder is not found
                        fileState.currentActiveGroup = nil
                    }
                } catch {}
            case .temporaryFile:
                fileState.currentActiveGroup = .temporary
            case .collaborationFile(let file):
                fileState.currentActiveGroup = file.group != nil ? .group(file.group!) : nil
                if let groupID = file.group?.objectID {
                    fileState.expandToGroup(groupID)
                }
        }
        
  
    }
    
    @ViewBuilder
    static func placeholder() -> some View {
        ViewSizeReader { size in
            let width = size.width > 0 ? size.width : nil
            if #available(macOS 14.0, *) {
                RoundedRectangle(cornerRadius: roundedCornerRadius)
                    .fill(.placeholder)
                    .opacity(0.2)
                    .frame(height: width == nil ? 180 : width! * 0.5625)
            } else {
                RoundedRectangle(cornerRadius: roundedCornerRadius)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: width == nil ? 180 : width! * 0.5625)
            }
        }
    }
}


struct FileHomeItemContextMenuModifier: ViewModifier {
    var file: FileState.ActiveFile
    
    func body(content: Content) -> some View {
        switch file {
            case .file(let file):
                content
                    .modifier(FileContextMenuModifier(file: file))
            case .localFile(let url):
                content
                    .modifier(LocalFileRowContextMenuModifier(file: url))
            case .temporaryFile(let url):
                content
                    .modifier(TemporaryFileContextMenuModifier(file: url))
            case .collaborationFile(let collaborationFile):
                content
                    .modifier(CollaborationFileContextMenuModifier(file: collaborationFile))
        }
            
    }
}
