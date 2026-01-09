//
//  ExcalidrawFileBrowser.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/14/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct ExcalidrawFileBrowser: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var fileState = FileState()
    
    enum ActionPayload {
        case file(File)
        case localFile(URL)
    }
    var action: (ActionPayload) async -> Void
    
    init(selectAction: @escaping (_ selection: ActionPayload) async -> Void) {
        self.action = selectAction
    }
    
    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: horizontalSizeClass == .compact ? nil : 200)
            Divider()
            
            content()
                .frame(width: horizontalSizeClass == .compact ? nil : 460)
        }
#if os(macOS)
        .frame(height: 400)
#elseif os(iOS)
        .ignoresSafeArea()
#endif
        .environmentObject(fileState)
        .onAppear {
            Task {
                try? await fileState.setToDefaultGroup()
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func sidebar() -> some View {
        ExcalidrawGroupBrowser()
        .background {
            if #available(macOS 14.0, iOS 17.0, *) {
                Rectangle().fill(.windowBackground)
            } else {
                Rectangle().fill(Color.windowBackgroundColor)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 100))], spacing: 0) {
                    if case .group(let group) = fileState.currentActiveGroup {
                        ExcalidrawFileBrowserContentView(group: group) {
                            if case .file(let file) = fileState.currentActiveFile {
                                await self.action(.file(file))
                                dismiss()
                            }
                        }
                    } else if case .localFolder(let folder) = fileState.currentActiveGroup {
                        ExcalidrawLocalFileBrowserContentView(folder: folder) {
                            if case .localFile(let file) = fileState.currentActiveFile {
                                await self.action(.localFile(file))
                                dismiss()
                            }
                        }
                    }
                }
                .padding()
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            fileState.setActiveFile(nil)
                        }
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button(role: .cancel) {
                     dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                        .padding(.horizontal)
                }
                .modernButtonStyle(style: .glass, shape: .modern)
                
                AsyncButton { @MainActor in
                    if case .file(let file) = fileState.currentActiveFile {
                        await action(.file(file))
                    } else if case .localFile(let localFile) = fileState.currentActiveFile {
                        await action(.localFile(localFile))
                    }
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCreate))
                        .padding(.horizontal)
                }
                .modernButtonStyle(style: .glassProminent, shape: .modern)
                .disabled(fileState.currentActiveFile == nil)
            }
            .padding()
        }
    }
}

struct ExcalidrawFileBrowserContentView: View {
    @EnvironmentObject private var fileState: FileState
    
    @FetchRequest
    private var files: FetchedResults<File>
    var onDoubleClick: (() async -> Void)?

    init(group: Group, onDoubleClick: (() async -> Void)? = nil) {
        let fileFetchRequest = NSFetchRequest<File>(entityName: "File")
        fileFetchRequest.predicate = NSPredicate(format: "group = %@ AND inTrash = false", group)
        fileFetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \File.updatedAt, ascending: false)
        ]
        self._files = FetchRequest(fetchRequest: fileFetchRequest, animation: .default)
        self.onDoubleClick = onDoubleClick
    }
    
    @State private var fileIcon: Image?
    @State private var isPerformingAction = false

    var body: some View {
        ForEach(files) { file in
            ExcalidrawFileItemView(
                isSelected: Binding {
                    if case .file(let f) = fileState.currentActiveFile {
                        return f == file
                    }
                    return false
                } set: { val in
                    if val {
                        fileState.setActiveFile(.file(file))
                    }
                },
                filename: file.name ?? String(localizable: .generalUnknown)
            ) {
#if canImport(AppKit)
                NSWorkspace.shared.icon(for: .excalidrawFile)
#elseif canImport(UIKit)
                UIImage.icon(for: .excalidrawFile) ?? UIImage.icon(forPathExtension: "json")
#endif
            } onDoubleClick: {
                if isPerformingAction {
                    return
                }
                isPerformingAction = true
                await onDoubleClick?()
                isPerformingAction = false
            }
            .disabled(isPerformingAction)
        }
    }
}


struct ExcalidrawLocalFileBrowserContentView: View {
    @EnvironmentObject private var fileState: FileState
    
    var folder: LocalFolder
    var onDoubleClick: (() async -> Void)?
    
    init(folder: LocalFolder, onDoubleClick: (() async -> Void)? = nil) {
        self.folder = folder
        self.onDoubleClick = onDoubleClick
    }
    
    @State private var contents: [URL] = []
    @State private var isPerformingAction = false
    
    @StateObject private var localFolderState = LocalFolderState()
    var body: some View {
        LocalFilesProvider(folder: folder, sortField: .name) { files, updateFlags in
            ForEach(files, id: \.self) { url in
                ExcalidrawFileItemView(
                    isSelected: Binding {
                        if case .localFile(let localFile) = fileState.currentActiveFile {
                            return localFile == url
                        }
                        return false
                    } set: { val in
                        if val {
                            fileState.setActiveFile(.localFile(url))
                        }
                    },
                    filename: url.lastPathComponent
                ) {
#if canImport(AppKit)
                    NSWorkspace.shared.icon(forFile: url.filePath)
#elseif canImport(UIKit)
                    UIImage.icon(forFileURL: url)
#endif
                } onDoubleClick: {
                    if isPerformingAction {
                        return
                    }
                    isPerformingAction = true
                    await onDoubleClick?()
                    isPerformingAction = false
                }
                .disabled(isPerformingAction)
            }
        }
        .environmentObject(localFolderState)
    }
    
    
}

struct ExcalidrawFileItemView: View {
    @Environment(\.isEnabled) private var isEnabled
    
    @Binding var isSelected: Bool

#if canImport(AppKit)
    typealias PlatformImage = NSImage
#elseif canImport(UIKit)
    typealias PlatformImage = UIImage
#endif
    
    var filename: String
    var fileIconGenerator: () -> PlatformImage
    var onDoubleClick: (() async -> Void)?
    
    init(
        isSelected: Binding<Bool>,
        filename: String,
        fileIconGenerator: @escaping () -> PlatformImage,
        onDoubleClick: (() async -> Void)? = nil
    ) {
        self._isSelected = isSelected
        self.filename = filename
        self.fileIconGenerator = fileIconGenerator
        self.onDoubleClick = onDoubleClick
    }
    
    @State private var fileIcon: Image?
    
    var body: some View {
        VStack(spacing: 6) {
            (fileIcon ?? Image(systemSymbol: .doc))
                .resizable()
                .scaledToFit()
                .padding(4)
                .frame(height: 60)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                }
            
            Text(filename)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .font(.callout)
                .padding(2)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? AnyShapeStyle(Color.accent) : AnyShapeStyle(Color.clear))
                }
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 40, alignment: .top)
        }
        .grayscale(isEnabled ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard isEnabled else { return }
            isSelected = true
            Task {
                await onDoubleClick?()
            }
        }
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                guard isEnabled else { return }
                isSelected = true
            }
        )
        .opacity(fileIcon != nil ? 1 : 0)
        .onAppear {
            Task.detached {
                let image = await Image(platformImage: fileIconGenerator())
                await MainActor.run {
                    self.fileIcon = image
                }
            }
        }
    }
}

#if canImport(UIKit)
extension UIImage {
    public enum FileIconSize {
        case smallest
        case largest
    }
    
    public class func icon(forFileURL fileURL: URL, preferredSize: FileIconSize = .smallest) -> UIImage {
        let myInteractionController = UIDocumentInteractionController(url: fileURL)
        let allIcons = myInteractionController.icons
        
        // allIcons is guaranteed to have at least one image
        switch preferredSize {
            case .smallest: return allIcons.first!
            case .largest: return allIcons.last!
        }
    }
    
    public class func icon(forFileNamed fileName: String, preferredSize: FileIconSize = .smallest) -> UIImage {
        return icon(forFileURL: URL(fileURLWithPath: fileName), preferredSize: preferredSize)
    }
    
    public class func icon(forPathExtension pathExtension: String, preferredSize: FileIconSize = .smallest) -> UIImage {
        let baseName = "Generic"
        let fileName = (baseName as NSString).appendingPathExtension(pathExtension) ?? baseName
        return icon(forFileNamed: fileName, preferredSize: preferredSize)
    }
}

import MobileCoreServices
import UniformTypeIdentifiers

extension FileManager {
    public func fileExtension(forUTI utiString: String) -> String? {
        guard let cfFileExtension = UTType(utiString)?.preferredFilenameExtension else {
            return nil
        }

        return cfFileExtension as String
    }
}

extension UIImage {
    public class func icon(forUTI utiString: String, preferredSize: FileIconSize = .smallest) -> UIImage? {
        guard let fileExtension = FileManager.default.fileExtension(forUTI: utiString) else {
            return nil
        }
        return icon(forPathExtension: fileExtension, preferredSize: preferredSize)
    }
    public class func icon(for type: UTType, preferredSize: FileIconSize = .smallest) -> UIImage? {
        guard let fileExtension = FileManager.default.fileExtension(forUTI: type.identifier) else {
            return nil
        }
        return icon(forPathExtension: fileExtension, preferredSize: preferredSize)
    }
}
#endif

#Preview {
    ExcalidrawFileBrowser { selection in
        
    }
}
