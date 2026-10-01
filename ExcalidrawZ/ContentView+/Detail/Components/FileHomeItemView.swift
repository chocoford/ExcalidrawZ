//
//  FileHomeItemView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers

import ChocofordUI

enum FileHomeItemStyle {
    case card
    case file
}

enum FileHomeItemSubtitle {
    case modifiedAt
    case location
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

enum FileHomeItemTransitionPreferenceID {
    static let destination = "DEST"
    static let viewportDestination = "VIEWPORT_DEST"

    static func source(for fileID: String) -> String {
        fileID + "SOURCE"
    }
}

private struct FileHomeItemTransitionSourceEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var fileHomeItemTransitionSourceEnabled: Bool {
        get { self[FileHomeItemTransitionSourceEnabledKey.self] }
        set { self[FileHomeItemTransitionSourceEnabledKey.self] = newValue }
    }
}

struct FileHomeItemView: View {
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    
    var file: FileState.ActiveFile
    var selectionSiblings: [FileState.ActiveFile]?
    var canMultiSelect: Bool
    var fileID: String { file.id }
    var filename: String { file.name ?? String(localizable: .generalUntitled) }
    var updatedAt: Date? { file.updatedAt }
    var customLabel: AnyView? = nil
    var subtitle: FileHomeItemSubtitle

    init(
        file: FileState.ActiveFile,
        selectionSiblings: [FileState.ActiveFile]? = nil,
        canMultiSelect: Bool = true,
        subtitle: FileHomeItemSubtitle = .modifiedAt
    ) {
        self.file = file
        self.selectionSiblings = selectionSiblings
        self.canMultiSelect = canMultiSelect
        self.subtitle = subtitle
    }

    init<Label: View>(
        file: FileState.ActiveFile,
        selectionSiblings: [FileState.ActiveFile]? = nil,
        canMultiSelect: Bool = true,
        subtitle: FileHomeItemSubtitle = .modifiedAt,
        @ViewBuilder customLabel: () -> Label
    ) {
        self.init(
            file: file,
            selectionSiblings: selectionSiblings,
            canMultiSelect: canMultiSelect,
            subtitle: subtitle
        )
        self.customLabel = AnyView(customLabel())
    }
    

    static let roundedCornerRadius: CGFloat = 12

    var config = Config()

    var body: some View {
        FileStatusProvider(file: file) { status in
            content()
                .modifier(MissingFileHomeItemViewModifier(isActive: status?.contentAvailability == .missing))
                .contentShape(Rectangle())
                .modifier(FileHomeItemContextMenuModifier(file: file, isMissing: status?.contentAvailability == .missing))
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        MissingFileMenuProvider(file: file) { triggers in
         
            FileHomeItemContentView(
                style: config.style,
                file: file,
                subtitle: subtitle,
                customLabel: customLabel
            )
#if os(iOS)
            .overlay {
                if editMode?.wrappedValue.isEditing == true, config.style == .card {
                    RoundedRectangle(cornerRadius: Self.roundedCornerRadius)
                        .fill(.gray)
                        .opacity(0.5)
                }
            }
#endif
            .contentShape(Rectangle())
            .modifier(FileHomeItemAppearanceModifier(style: config.style))
            .modifier(
                FileHomeItemOpenModifier(
                    file: file,
                    onRecover: triggers.onToggleTryToRecover
                )
            )
            .modifier(
                FileHomeItemSelectModifier(
                    file: file,
                    selectionSiblings: selectionSiblings,
                    canMultiSelect: canMultiSelect,
                    style: config.style
                )
            )
            .modifier(FileHomeItemDragModifier(file: file))
            .modifier(FileHomeItemTransitionVisibilityModifier(fileID: fileID))
        }
    }

    @ViewBuilder
    static func placeholder() -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            RoundedRectangle(cornerRadius: roundedCornerRadius)
                .fill(.placeholder)
                .opacity(0.2)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: roundedCornerRadius)
                .fill(Color.gray.opacity(0.1))
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
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

// Hover only changes the chrome. Keep its state away from the cover, labels,
// context menus, and selection providers so pointer updates don't rebuild them.
private struct FileHomeItemAppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var style: FileHomeItemStyle

    func body(content: Content) -> some View {
        if style == .card {
            content
                .background {
                    background
                        .allowsHitTesting(false)
                }
                .onHover { hovered in
                    guard isHovered != hovered else { return }
                    isHovered = hovered
                }
                .animation(.smooth(duration: 0.2), value: isHovered)
        } else {
            content
        }
    }

    @ViewBuilder
    private var background: some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius)
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
            RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius)
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

private struct FileHomeItemOpenModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
#if os(iOS)
    @Environment(\.editMode) private var editMode
#endif
    @EnvironmentObject private var fileState: FileState

    var file: FileState.ActiveFile
    var onRecover: () -> Void

    func body(content: Content) -> some View {
#if os(macOS)
        content.simultaneousGesture(TapGesture(count: 2).onEnded {
            openOrRecoverFile()
        })
#elseif os(iOS)
        content.simultaneousGesture(
            TapGesture().onEnded {
                openOrRecoverFile()
            },
            isEnabled: editMode?.wrappedValue.isEditing != true
        )
#endif
    }

    private func openOrRecoverFile() {
        if FileStatusService.shared.statusBox(for: file).status.contentAvailability == .missing {
            if case .collaborationFile = file {
                openFile()
            } else {
                onRecover()
            }
        } else {
            openFile()
        }
    }

    private func openFile() {
        guard isEnabled else { return }
        fileState.setActiveFile(file)
    }
}

private struct FileHomeItemTransitionVisibilityModifier: ViewModifier {
    @EnvironmentObject private var transitionState: FileHomeItemTransitionItemState

    var fileID: String

    func body(content: Content) -> some View {
        content.opacity(transitionState.shouldHideItem == fileID ? 0 : 1)
    }
}

private struct FileHomeItemTransitionSource: View {
    @Environment(\.fileHomeItemTransitionSourceEnabled) private var isEnabled
    @EnvironmentObject private var transitionState: FileHomeItemTransitionItemState

    var fileID: String

    var body: some View {
        if isEnabled && transitionState.sourceFileID == fileID {
            Color.clear
                .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                    [FileHomeItemTransitionPreferenceID.source(for: fileID): value]
                }
                .allowsHitTesting(false)
        }
    }
}

private struct FileHomeItemContentView: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
#if os(iOS)
    @Environment(\.editMode) var editMode
#endif

    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var lockedContentState: LockedContentStateStore

    var style: FileHomeItemStyle
    var file: FileState.ActiveFile
    var subtitle: FileHomeItemSubtitle
    var customLabel: AnyView?
    
    var fileID: String { file.id }
    var filename: String { file.name ?? String(localizable: .generalUntitled) }
    private var updatedAt: Date? {
        switch file {
            case .localFile, .temporaryFile:
                // URL metadata is loaded by the task, never while evaluating the view.
                return nil
            default:
                return file.updatedAt
        }
    }
    var fileType: UTType { file.fileType }
    
    init(
        style: FileHomeItemStyle,
        file: FileState.ActiveFile,
        subtitle: FileHomeItemSubtitle,
        customLabel: AnyView?
    ) {
        self.style = style
        self.file = file
        self.subtitle = subtitle
        self.customLabel = customLabel
        self._localUpdatedAt = State(initialValue: updatedAt)
    }
    
    @State private var localUpdatedAt: Date?
    
    @available(macOS 13.0, *)
    var layout: AnyLayout {
        switch layoutState.compactBrowserLayout {
            case .grid:
                return AnyLayout(VStackLayout(alignment: .center, spacing: 0))
            case .list:
                return AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        }
    }
    
    var body: some View {
        SwiftUI.Group {
            if style == .card {
                VStack(alignment: .center, spacing: 0) {
                    content()
                }
                .clipShape(RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius))
            } else if #available(macOS 13.0, *) {
                layout {
                     content()
                }
                .clipShape(Rectangle())
            } else {
                VStack(spacing :0) {
                    content()
                }
                .clipShape(RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius))
            }
        }
        .task(id: fileID) {
            await refreshLocalModificationDate()
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        // Cover
        ZStack {
            coverSizingSurface
                .modifier(
                    FileHomeItemLockPreviewModifier(
                        file: file,
                        iconSize: lockOverlayIconSize
                    )
                )
                .apply(coverImageClip)
        }
        .background {
            FileHomeItemTransitionSource(fileID: fileID)
        }
        .overlay {
            if style == .file {
                RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius)
                    .stroke(.secondary, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, style == .file && layoutState.compactBrowserLayout == .list ? 10 : 0)
        .frame(width: style == .file && layoutState.compactBrowserLayout == .list ? 80 : nil)
#if os(iOS)
        .overlay {
            if editMode?.wrappedValue.isEditing == true, style == .file {
                RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius)
                    .fill(.gray)
                    .opacity(0.5)
            }
        }
#endif
        
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
                            if fileType == .excalidrawPNG || fileType == .excalidrawSVG {
                                Image(systemSymbol: .photo)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if style == .file {
                                Color.clear
                                    .frame(width: 16, height: 0)
                                    .overlay {
                                        FileICloudStatusIndicator(file: file)
                                            .controlSize(.mini)
                                            .foregroundStyle(.secondary)
                                    }
                            }

                            if lockedContentState.previewLockState(for: file) == .temporarilyUnlocked {
                                Spacer()
                                Image(systemName: LockedContentSymbols.keyShield)
                                    .transition(.scale(scale: 0.92).combined(with: .opacity))
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
                            switch subtitle {
                                case .modifiedAt:
                                    Text(localUpdatedAt?.formatted() ?? String(localizable: .generalFileNeverModified))
                                        .lineLimit(1)
                                        .watch(value: updatedAt) { newValue in
                                            switch file {
                                                case .localFile, .temporaryFile:
                                                    break
                                                default:
                                                    localUpdatedAt = newValue
                                            }
                                        }
                                case .location:
                                    Text(file.displayLocation)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                            }
                            
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
                                case .cloudStorageFile(let reference):
                                    CloudStorageDocumentSyncIndicator(reference: reference)
                            }
                        }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.22), value: lockedContentState.previewLockState(for: file))
        .padding(.horizontal, containerHorizontalSizeClass == .regular ? 8 : 6)
        .padding(.vertical, containerHorizontalSizeClass == .regular ? 8 : 6)
        // Costing too much performance
//        .background {
//            if style == .card {
//                Rectangle().fill(.ultraThinMaterial)
//            }
//        }
    }

    private func refreshLocalModificationDate() async {
        let date: Date?
        switch file {
            case .localFile(let url):
                date = try? await LocalFolder.modificationDate(forLocalFileAt: url)
            case .temporaryFile(let url):
                date = await Task.detached(priority: .utility) {
                    try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate
                }.value
            default:
                return
        }
        guard !Task.isCancelled else { return }
        localUpdatedAt = date
    }

    @ViewBuilder
    private var coverSizingSurface: some View {
        if style == .file && layoutState.compactBrowserLayout == .list {
            Color.clear
                .frame(height: 60)
        } else {
            Color.clear
                .aspectRatio(style == .file ? 4.0 / 3.0 : 1.0 / 0.46, contentMode: .fit)
        }
    }

    private var lockOverlayIconSize: CGFloat {
        style == .file && layoutState.compactBrowserLayout == .list ? 22 : 34
    }

    @ViewBuilder
    private func coverImageClip<Content: View>(
        content: Content
    ) -> some View {
        if #available(macOS 13.0, *) {
            content
                .clipShape(
                    style == .file
                    ? AnyShape(RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius))
                    : AnyShape(Rectangle())
                )
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: FileHomeItemView.roundedCornerRadius))
        }
    }
}

@MainActor
private extension FileState.ActiveFile {
    var displayLocation: String {
        switch self {
            case .file(let file):
                let groupNames = Self.groupPath(for: file.group)
                return groupNames.isEmpty ? "/" : groupNames.joined(separator: " / ")
            case .localFile(let url):
                return Self.linkedFolderPath(for: url)
            case .temporaryFile(let url):
#if os(iOS)
                return url.deletingLastPathComponent().lastPathComponent
#else
                return Self.abbreviatedPath(url.deletingLastPathComponent())
#endif
            case .collaborationFile:
                return String(localizable: .collaborationHomeTitle)
            case .cloudStorageFile(let reference):
                let documentStore = CloudStorageDocumentStore.shared
                guard let parentFolder = documentStore.parentFolder(for: reference) else {
                    return CloudStorageConnectionStore.shared.locations.first(where: {
                        $0.id == reference.locationID
                    })?.displayName ?? String(localizable: .generalUnknown)
                }
                let folderNames = documentStore.folderPath(for: parentFolder).map(\.name)
                return folderNames.joined(separator: " / ")
        }
    }

    static func groupPath(for group: Group?) -> [String] {
        var names: [String] = []
        var currentGroup = group
        var visited = Set<NSManagedObjectID>()

        while let group = currentGroup, !visited.contains(group.objectID) {
            visited.insert(group.objectID)
            if let name = group.name, !name.isEmpty {
                names.append(name)
            }
            currentGroup = group.parent
        }
        return names.reversed()
    }

    static func linkedFolderPath(for fileURL: URL) -> String {
        let directoryURL = fileURL.deletingLastPathComponent().standardizedFileURL
        let context = PersistenceController.shared.container.viewContext
        guard let folder = try? LocalFolder.rootFolder(containing: directoryURL, in: context),
              let rootURL = folder.filePath.map({
                  URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
              }) else {
            return directoryURL.lastPathComponent
        }

        let relativeComponents = directoryURL.pathComponents.dropFirst(rootURL.pathComponents.count)
        return ([rootURL.lastPathComponent] + Array(relativeComponents)).joined(separator: " / ")
    }

    static func abbreviatedPath(_ directoryURL: URL) -> String {
        let path = directoryURL.path(percentEncoded: false)
#if os(macOS)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        if path == homePath {
            return "~"
        }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
#endif
        return path
    }
}

private struct FileHomeItemContextMenuModifier: ViewModifier {
    var file: FileState.ActiveFile
    var isMissing: Bool
    
    func body(content: Content) -> some View {
        if isMissing {
            switch file {
                case .file:
                    content
                        .modifier(MissingFileContextMenuModifier(file: file))
                case .localFile:
                    // Localfile never missing
                    content
                case .temporaryFile:
                    // TemporaryFile never missing
                    content
                case .collaborationFile(let room):
                    // Missing CollaborationFile no matter
                    content
                        .modifier(CollaborationFileContextMenuModifier(file: room))
                case .cloudStorageFile:
                    content
            }
        } else {
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
                case .cloudStorageFile(let reference):
                    content
                        .modifier(CloudStorageFileActionsModifier(reference: reference))
            }
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
            case .cloudStorageFile:
                content
                
        }
    }
}

private struct MissingFileHomeItemViewModifier: ViewModifier {
    // 状态控制
    var isActive: Bool
    // 内部动画状态
    @State private var isBreathing = false
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0.5 + (isBreathing ? 0.25 : 0.0) : 1)
//            .onAppear {
//                isVisible = true
//                // 只在视图激活时启动动画
//                if isActive {
//                    startBreathingAnimation()
//                }
//            }
//            .onDisappear {
//                isVisible = false
//            }
//            .watch(value: isActive) { newValue in
//                if newValue && isVisible {
//                    startBreathingAnimation()
//                }
//            }
    }

    private func startBreathingAnimation() {
        withAnimation(.easeInOut(duration: Double.random(in: 2.0...4.5)).repeatForever(autoreverses: true)) {
            isBreathing.toggle()
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
