//
//  FileHomeItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import CoreData

import ChocofordUI

enum FileHomeItemStyle {
    case card
    case file
}

extension Notification.Name {
    static let filePreviewShouldRefresh = Notification.Name("FilePreviewShouldRefresh")
}

struct FileHomeItemPreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () ->  [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

class FileItemPreviewCache: NSCache<NSString, PlatformImage> {
    static let shared = FileItemPreviewCache()

    static func cacheKey(for file: FileState.ActiveFile, colorScheme: ColorScheme) -> NSString {
        file.id + (colorScheme == .light ? "_light" : "_dark") as NSString
    }
    
    func getPreviewCache(forFile file: FileState.ActiveFile, colorScheme: ColorScheme) -> PlatformImage? {
        self.object(forKey: Self.cacheKey(for: file, colorScheme: colorScheme))
    }
    
    func removePreviewCache(forFile file: FileState.ActiveFile, colorScheme: ColorScheme) {
        self.removeObject(forKey: Self.cacheKey(for: file, colorScheme: colorScheme))
    }
}


struct FileHomeItemView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.isEnabled) private var isEnabled
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState
    
    var file: FileState.ActiveFile
    var canMultiSelect: Bool
    var fileID: String
    var filename: String
    var updatedAt: Date?
    var customLabel: AnyView? = nil

    init(
        file: FileState.ActiveFile,
        canMultiSelect: Bool = true
    ) {
        self.file = file
        self.canMultiSelect = canMultiSelect
        switch file {
            case .file(let file):
                self.fileID = file.objectID.description
                self.filename = file.name ?? String(localizable: .generalUntitled)
                self.updatedAt = file.updatedAt
            case .localFile(let url):
                self.fileID = url.absoluteString
                self.filename = url.deletingPathExtension().lastPathComponent.isEmpty
                ? String(localizable: .generalUntitled)
                : url.deletingPathExtension().lastPathComponent
                self.updatedAt = file.updatedAt

            case .temporaryFile(let url):
                self.fileID = url.absoluteString
                self.filename = url.deletingPathExtension().lastPathComponent.isEmpty
                ? String(localizable: .generalUntitled)
                : url.deletingPathExtension().lastPathComponent
                self.updatedAt = (try? FileManager().attributesOfItem(atPath: url.filePath)[FileAttributeKey.modificationDate]) as? Date
            case .collaborationFile(let collaborationFile):
                self.fileID = collaborationFile.objectID.description
                self.filename = collaborationFile.name ?? String(localizable: .generalUntitled)
                self.updatedAt = file.updatedAt
        }
    }

    init<Label: View>(
        file: FileState.ActiveFile,
        canMultiSelect: Bool = true,
        @ViewBuilder customLabel: () -> Label
    ) {
        self.init(file: file, canMultiSelect: canMultiSelect)
        self.customLabel = AnyView(customLabel())
    }
    

    @State private var isHovered = false

    static let roundedCornerRadius: CGFloat = 12

    var config = Config()

    var body: some View {
        FileHomeItemContentView(
            style: config.style,
            file: file,
            fileID: fileID,
            filename: filename,
            updatedAt: updatedAt,
            customLabel: customLabel
        )
#if os(iOS)
        .opacity(editMode?.wrappedValue.isEditing == true ? 0.7 : 1.0)
#endif
        .background {
            if config.style == .card {
                if #available(macOS 26.0, iOS 26.0, *) {
                    RoundedRectangle(cornerRadius: Self.roundedCornerRadius)
                        .fill(
                            colorScheme == .light
                            ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                            : AnyShapeStyle(Color.clear)
                        )
                        .glassEffect(.clear, in: .rect(cornerRadius: 12))
                        .shadow(
                            color: colorScheme == .light
                            ? Color.gray.opacity(0.33)
                            : Color.black.opacity(0.33),
                            radius: isHovered
                            ? colorScheme == .light ? 2 : 6
                            : 0
                        )
                } else {
                    RoundedRectangle(cornerRadius: Self.roundedCornerRadius)
                        .fill(.background)
                        .shadow(
                            color: colorScheme == .light
                            ? Color.gray.opacity(0.33)
                            : Color.black.opacity(0.33),
                            radius: isHovered
                            ? colorScheme == .light ? 2 : 6
                            : 0
                        )
                }
            }
        }
//        .overlay {
//            Color.clear
        .contentShape(Rectangle())
#if os(macOS)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            openFile()
        })
#elseif os(iOS)
        .simultaneousGesture(TapGesture().onEnded {
            openFile()
        }, isEnabled: editMode?.wrappedValue.isEditing != true)
#endif
        .modifier(
            FileHomeItemSelectModifier(
                file: file,
                sortField: fileState.sortField,
                canMultiSelect: canMultiSelect,
                style: config.style
            )
        )
        .modifier(FileHomeItemContextMenuModifier(file: file))
        .onHover {
            isHovered = $0
        }
//        }
        .modifier(FileHomeItemDragModifier(file: file))
        .opacity(fileHomeItemTransitionState.shouldHideItem == fileID ? 0 : 1)
        .animation(.smooth(duration: 0.2), value: isHovered)
    }


    private func openFile() {
        guard isEnabled else { return }
        fileState.setActiveFile(file)
        
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
                fileState.currentActiveGroup = .collaboration
                if !fileState.collaboratingFiles.contains(file) {
                    fileState.collaboratingFiles.append(file)
                }
        }
    }

    @ViewBuilder
    static func placeholder() -> some View {
        ViewSizeReader { size in
            let width = size.width > 0 ? size.width : nil
            if #available(macOS 14.0, iOS 17.0, *) {
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

    
    class Config {
        var style: FileHomeItemStyle = .card
    }
    
    @MainActor
    public func fileHomeItemStyle(_ style: FileHomeItemStyle) -> FileHomeItemView {
        self.config.style = style
        return self
    }
}

private struct FileHomeItemContentView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.colorScheme) var colorScheme

    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState

    var style: FileHomeItemStyle
    var file: FileState.ActiveFile
    var fileID: String
    var filename: String
    var updatedAt: Date?
    var customLabel: AnyView?
    
    init(
        style: FileHomeItemStyle,
        file: FileState.ActiveFile,
        fileID: String,
        filename: String,
        updatedAt: Date?,
        customLabel: AnyView?
    ) {
        self.style = style
        self.file = file
        self.fileID = fileID
        self.filename = filename
        self.updatedAt = updatedAt
        self.customLabel = customLabel
    }
    
    @State private var coverImage: Image? = nil
    @State private var error: Error?
    @State private var width: CGFloat?

    let cache = FileItemPreviewCache.shared
    
    var cacheKey: String {
        colorScheme == .light ? fileID + "_light" : fileID + "_dark"
    }
    
    @available(macOS 13.0, *)
    var layout: AnyLayout {
        if style == .card {
            return AnyLayout(VStackLayout(alignment: .center, spacing: 0))
        }
        switch layoutState.compactBrowserLayout {
            case .grid:
                return AnyLayout(VStackLayout(alignment: .center, spacing: 0))
            case .list:
                return AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        }
    }
    
    var body: some View {
        SwiftUI.Group {
            if #available(macOS 13.0, *) {
                layout {
                    content()
                }
                .clipShape(
                    style == .file
                    ? AnyShape(Rectangle())
                    : AnyShape(RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius))
                )
            } else {
                VStack(spacing :0) {
                    content()
                }
                .clipShape(RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius))
            }
        }
        .readWidth($width)
        .onReceive(
            NotificationCenter.default.publisher(for: .filePreviewShouldRefresh)
        ) { notification in
            guard let fileID = notification.object as? String,
                  self.file.id == fileID else { return }
            
            print("Refreshing preview for file: \(fileID)")
            
            self.getElementsImage()
        }
        .onChange(of: file) { newValue in
            self.getElementsImage()
        }
        .watchImmediately(of: colorScheme) { _ in
            if let image = cache.getPreviewCache(forFile: file, colorScheme: colorScheme) {
                Task.detached {
                    let image = Image(platformImage: image)
                    await MainActor.run {
                        self.coverImage = image
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.getElementsImage()
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        // Cover
        ZStack {
            var height: CGFloat {
                style == .file && layoutState.compactBrowserLayout == .list
                ? 60
                : width == nil
                ? 180
                : width! * (style == .file ? 0.75 : 0.46)
            }
            
            if let coverImage {
                Color.clear
                    .overlay {
                        coverImage
                            .resizable()
                            .scaledToFill()
                            .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius))
                    .frame(height: height)
            } else if error != nil {
                Color.clear
                    .overlay {
                        Image(systemSymbol: .exclamationmarkTriangle)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: height)
            } else {
                Color.clear
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            // .padding(.bottom, 40)
                    }
                    .frame(height: height)
            }
        }
        .background {
            Color.clear
                .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                    [fileID+"SOURCE": value]
                }
        }
        .observeFileStatus(for: file) { status in
#if os(macOS)
            if status == .outdated {
                self.getElementsImage()
            }
#endif
        }
        .overlay(alignment: .bottomTrailing) {
            // Download progress indicator
            FileDownloadProgressView(fileID: fileID)
                .padding(8)
        }
        .overlay {
            if style == .file {
                RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius)
                    .stroke(.secondary, lineWidth: 0.5)
            }
        }
        .padding(.horizontal, style == .file && layoutState.compactBrowserLayout == .list ? 10 : 0)
        .frame(width: style == .file && layoutState.compactBrowserLayout == .list ? 80 : nil)

        // Label
        ZStack {
            if let customLabel {
                customLabel
            } else {
                HStack {
                    if style == .file, layoutState.compactBrowserLayout == .grid {
                        Spacer(minLength: 0)
                    }
                    VStack(
                        alignment: style == .file && layoutState.compactBrowserLayout != .list
                        ? .center
                        : .leading
                    ) {
                        HStack {
                            Text(filename)
                                .lineLimit(1)
                                
                            if style == .file {
                                FileICloudStatusIndicator(file: file)
                                    .controlSize(.mini)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(
                            containerHorizontalSizeClass == .regular
                            ? .headline.weight(.semibold)
                            : style == .file && layoutState.compactBrowserLayout == .list
                            ? .body.weight(.regular)
                            : .caption.weight(.semibold)
                        )
                        
                        HStack {
                            Text(updatedAt?.formatted() ?? "Never modified")
                                .lineLimit(1)
                            
                            Spacer(minLength: 0)
                            
                        }
                        .font(
                            containerHorizontalSizeClass == .regular
                            ? .footnote
                            : style == .file && layoutState.compactBrowserLayout == .list
                            ? .footnote
                            : .caption2
                        )
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                if style == .card {
                    switch file {
                        case .file:
                            EmptyView()
                            // ExcalidrawIconView().frame(height: 8)
                        case .localFile:
                            FileICloudStatusIndicator(file: file) {
                                Image(systemSymbol: .externaldrive)
                            }
                            .controlSize(.mini)
                        case .temporaryFile:
                            Image(systemSymbol: .clock)
                        case .collaborationFile:
                            Image(systemSymbol: .person3Fill)
                    }
                }
            }
        }
        .padding(.horizontal, containerHorizontalSizeClass == .regular ? 8 : 6)
        .padding(.vertical, containerHorizontalSizeClass == .regular ? 8 : 6)
        .background {
            if style == .card {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
    
    
    
    private func getElementsImage() {
        Task {
            do {
                // Load ExcalidrawFile asynchronously
                let excalidrawFile: ExcalidrawFile

                switch file {
                    case .file(let file):
                        let content = try await file.loadContent()
                        excalidrawFile = try ExcalidrawFile(data: content, id: file.id)
                    case .localFile(let url):
                        try await FileAccessor.shared.downloadFile(url)
                        excalidrawFile = try ExcalidrawFile(contentsOf: url)
                    case .temporaryFile(let url):
                        excalidrawFile = try ExcalidrawFile(contentsOf: url)
                    case .collaborationFile(let collaborationFile):
                        let content = try await collaborationFile.loadContent()
                        excalidrawFile = try ExcalidrawFile(data: content, id: collaborationFile.id)
                }

                // Wait for coordinator to be ready
                while fileState.excalidrawWebCoordinator?.isLoading == true {
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * 1))
                }

                // Generate preview image
                if let image = try? await fileState.excalidrawWebCoordinator?.exportElementsToPNG(
                    elements: excalidrawFile.elements,
                    files: excalidrawFile.files.isEmpty ? nil : excalidrawFile.files,
                    colorScheme: colorScheme
                ) {
                    Task.detached {
                        await MainActor.run {
                            cache.setObject(image, forKey: cacheKey as NSString)
                        }
                        let image = Image(platformImage: image)
                        await MainActor.run {
                            self.coverImage = image
                            self.error = nil
                        }
                    }
                }
            } catch {
                print("Failed to load excalidraw file for preview:", error)
                self.error = error
            }
        }
    }
}

private struct FileHomeItemContextMenuModifier: ViewModifier {
    var file: FileState.ActiveFile
    
    func body(content: Content) -> some View {
        switch file {
            case .file(let file):
                content
                    .modifier(FileContextMenuModifier(files: [file]))
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

private struct FileHomeItemDragModifier: ViewModifier {
    var file: FileState.ActiveFile
    
    func body(content: Content) -> some View {
        switch file {
            case .file(let file):
                content
                    .modifier(FileRowDragModifier(file: file))
            case .localFile(let url):
                content
                    .modifier(LocalFileDragModifier(file: url))
            case .temporaryFile(let url):
                content
                    .modifier(LocalFileDragModifier(file: url))
            case .collaborationFile(let collaborationFile):
                content
                    .modifier(FileRowDragModifier(file: collaborationFile))
                
        }
    }
}


private struct DatabaseFileHomeDropContianer<F: ExcalidrawFileRepresentable>: View {
    var file: F
    
    @FetchRequest
    private var files: FetchedResults<F>
    
    var content: (_ files: FetchedResults<F>) -> AnyView
    
    
    init<Content: View>(
        file: F,
        @ViewBuilder content: @escaping (_ files: FetchedResults<F>) -> Content
    ) where F == File {
        self.file = file
        self._files = FetchRequest<File>(
            sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
            predicate: NSPredicate(format: "group == %@", file.group ?? Group()),
            animation: .smooth
        )
        self.content = { AnyView(content($0)) }
    }
    
    init<Content: View>(
        file: F,
        @ViewBuilder content: @escaping (_ files: FetchedResults<F>) -> Content
    ) where F == CollaborationFile {
        self.file = file
        self._files = FetchRequest<CollaborationFile>(
            sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)],
            animation: .smooth
        )
        self.content = { AnyView(content($0)) }
    }
    
    var body: some View {
        content(files)
    }
}


struct FileICloudStatusIndicator: View {
    var file: FileState.ActiveFile
    
    var downloadedFallbackView: AnyView?
    
    init<Content: View>(
        file: FileState.ActiveFile,
        @ViewBuilder downloadedFallbackView: () -> Content
    ) {
        self.file = file
        self.downloadedFallbackView = AnyView(downloadedFallbackView())
    }
    
    init(
        file: FileState.ActiveFile,
    ) {
        self.file = file
    }
    
    @State private var iCloudFileStatus: FileStatus? = nil
    
    var body: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                switch iCloudFileStatus {
                    case .notDownloaded:
                        Image(systemSymbol: .icloudAndArrowDown)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: iCloudFileStatus == .notDownloaded)
                    case .downloading(let progress):
                        CircularProgressIndicator(progress: progress ?? 0)
                    case .downloaded:
                        downloadedFallbackView
                            .symbolEffect(.drawOn, options: .speed(2), isActive: iCloudFileStatus == .downloaded)
                    case .outdated:
                        Image(systemName: "icloud.dashed")
                    case .loading:
                        ProgressView()
                    case .local:
                        EmptyView()
                    case .uploading:
                        Image(systemSymbol: .icloudAndArrowUp)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: iCloudFileStatus == .uploading)
                    case .conflict:
                        Image(systemSymbol: .xmarkIcloud)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: iCloudFileStatus == .conflict)
                    case .error(_):
                        Image(systemSymbol: .exclamationmarkTriangle)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: {
                                if case .error = iCloudFileStatus {
                                    return true
                                }
                                return false
                            }())
                    default:
                        EmptyView()
                }
            } else {
                switch iCloudFileStatus {
                    case .notDownloaded:
                        Image(systemSymbol: .icloudAndArrowDown)
                    case .downloading(let progress):
                        CircularProgressIndicator(progress: progress ?? 0)
                    case .downloaded:
                        downloadedFallbackView
                    case .outdated:
                        Image(systemName: "icloud.dashed")
                    case .loading:
                        ProgressView()
                    case .local:
                        EmptyView()
                    case .uploading:
                        Image(systemSymbol: .icloudAndArrowUp)
                    case .conflict:
                        Image(systemSymbol: .xmarkIcloud)
                    case .error(_):
                        Image(systemSymbol: .exclamationmarkTriangle)
                    default:
                        EmptyView()
                }
            }
        }
        .bindFileStatus(for: file, status: $iCloudFileStatus)
        .symbolRenderingMode(.multicolor)
        .animation(.smooth, value: iCloudFileStatus)
    }
}

#if os(iOS)
/// A View only for showing syncing status
struct FileICloudSyncStatusIndicator: View {
    var file: FileState.ActiveFile
    
    @State private var iCloudFileStatus: FileStatus? = nil
    var body: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                ZStack {
                    if iCloudFileStatus == .syncing {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90Icloud)
                            .drawOnAppear(options: .speed(2))
                    } else {
                        Image(systemSymbol: .checkmarkIcloud)
                            .drawOnAppear(options: .speed(2))
                            .foregroundStyle(.green)
                    }
                }
            } else {
                if iCloudFileStatus == .syncing {
                    if #available(macOS 15.0, iOS 18.0, *) {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90Icloud)
                    } else {
                        Image(systemSymbol: .arrowTriangle2Circlepath)
                    }
                } else if case .downloaded = iCloudFileStatus {
                    Image(systemSymbol: .checkmarkIcloud)
                        .foregroundStyle(.green)
                }
            }
        }
        .bindFileStatus(for: file, status: $iCloudFileStatus)
        .symbolRenderingMode(.multicolor)
        .animation(.smooth, value: iCloudFileStatus)
    }
}
#endif

@available(macOS 26.0, iOS 26.0, *)
struct DrawOnAppearModifier: ViewModifier {
    
     var options: SymbolEffectOptions = .default
    
    @State private var isActive = false
    
    func body(content: Content) -> some View {
        content
            .symbolEffect(.drawOn, options: options, isActive: !isActive)
            .animation(.smooth, value: isActive)
            .onAppear {
                isActive = true
            }
    }
}

extension View {
    @available(macOS 26.0, iOS 26.0, *)
    @ViewBuilder
    func drawOnAppear(options: SymbolEffectOptions = .default) -> some View {
        modifier(DrawOnAppearModifier(options: options))
    }
}

private struct PreviewView: View {
    @State private var isOn = false
    
    var body: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            VStack {
                ZStack {
                    if isOn {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90Icloud)
                            .drawOnAppear(options: .speed(2))
                    } else {
                        Image(systemSymbol: .checkmarkIcloud)
                            .drawOnAppear(options: .speed(2))
                    }
                }.border(.red)
                
                Button {
                    isOn.toggle()
                } label: {
                    Text("Toggle")
                }
            }
        }
    }
}

#Preview {
    PreviewView()
}
