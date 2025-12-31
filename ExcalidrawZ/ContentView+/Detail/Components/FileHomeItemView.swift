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
    var fileID: String { file.id }
    var filename: String { file.name ?? String(localizable: .generalUntitled) }
    var updatedAt: Date? { file.updatedAt }
    var customLabel: AnyView? = nil

    init(
        file: FileState.ActiveFile,
        canMultiSelect: Bool = true
    ) {
        self.file = file
        self.canMultiSelect = canMultiSelect
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
        FileStatusProvider(file: file) { status in
            content()
                .modifier(MissingFileHomeItemViewModifier(isActive: status?.contentAvailability == .missing))
                .contentShape(Rectangle())
                .modifier(FileHomeItemContextMenuModifier(file: file, isMissing: status?.contentAvailability == .missing))
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        MissingFileMenuProvider(files: [file]) { triggers in
         
            FileHomeItemContentView(
                style: config.style,
                file: file,
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
            .contentShape(Rectangle())
#if os(macOS)
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                if FileStatusService.shared.statusBox(for: file).status.contentAvailability == .missing {
                    triggers.onToggleTryToRecover()
                } else {
                    openFile()
                }
            })
#elseif os(iOS)
            .simultaneousGesture(TapGesture().onEnded {
                if FileStatusService.shared.statusBox(for: file).status.contentAvailability == .missing {
                    triggers.onToggleTryToRecover()
                } else {
                    openFile()
                }
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
            .onHover {
                isHovered = $0
            }
            .modifier(FileHomeItemDragModifier(file: file))
            .opacity(fileHomeItemTransitionState.shouldHideItem == fileID ? 0 : 1)
            .animation(.smooth(duration: 0.2), value: isHovered)
            
        }
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
    @Environment(\.scenePhase) var scenePhase

    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState

    var style: FileHomeItemStyle
    var file: FileState.ActiveFile
    var customLabel: AnyView?
    
    var fileID: String { file.id }
    var filename: String { file.name ?? String(localizable: .generalUntitled) }
    var updatedAt: Date? { file.updatedAt }
    
    init(
        style: FileHomeItemStyle,
        file: FileState.ActiveFile,
        customLabel: AnyView?
    ) {
        self.style = style
        self.file = file
        self.customLabel = customLabel
        self._localUpdatedAt = State(initialValue: updatedAt)
    }
    
    @State private var width: CGFloat?
    @State private var localUpdatedAt: Date?

    

    
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
          
            Color.clear
                .overlay {
                    ExcalidrawFileCover(file: file)
                        .scaledToFill()
                        .allowsHitTesting(false)
                }
                .frame(height: height)
                .apply(coverImageClip)
        }
        .background {
            Color.clear
                .anchorPreference(key: FileHomeItemPreferenceKey.self, value: .bounds) { value in
                    [fileID+"SOURCE": value]
                }
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
                            Text(localUpdatedAt?.formatted() ?? "Never modified")
                                .lineLimit(1)
                                .onChange(of: updatedAt) { newValue in
                                    localUpdatedAt = newValue
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

private struct FileHomeItemContextMenuModifier: ViewModifier {
    var file: FileState.ActiveFile
    var isMissing: Bool
    
    func body(content: Content) -> some View {
        if isMissing {
            switch file {
                case .file:
                    content
                        .modifier(MissingFileContextMenuModifier(files: [file]))
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
            }
        } else {
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
//            .onChange(of: isActive) { newValue in
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
    
    @State private var fileStatus: FileStatus? = nil

    var body: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                switch fileStatus?.iCloudStatus {
                    case .notDownloaded:
                        Image(systemSymbol: .icloudAndArrowDown)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: fileStatus?.iCloudStatus == .notDownloaded)
                    case .downloading(let progress):
                        CircularProgressIndicator(progress: progress ?? 0)
                    case .downloaded:
                        downloadedFallbackView
                            .symbolEffect(.drawOn, options: .speed(2), isActive: fileStatus?.iCloudStatus == .downloaded)
                    case .outdated:
                        Image(systemName: "icloud.dashed")
                    case .loading:
                        ProgressView()
                    case .local:
                        EmptyView()
                    case .uploading:
                        Image(systemSymbol: .icloudAndArrowUp)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: fileStatus?.iCloudStatus == .uploading)
                    case .conflict:
                        Image(systemSymbol: .xmarkIcloud)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: fileStatus?.iCloudStatus == .conflict)
                    case .error(_):
                        Image(systemSymbol: .exclamationmarkTriangle)
                            .symbolEffect(.drawOn, options: .speed(2), isActive: {
                                if case .error = fileStatus?.iCloudStatus {
                                    return true
                                }
                                return false
                            }())
                    default:
                        EmptyView()
                }
            } else {
                switch fileStatus?.iCloudStatus {
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
        .bindFileStatus(for: file, status: $fileStatus)
        .symbolRenderingMode(.multicolor)
        .animation(.smooth, value: fileStatus?.iCloudStatus)
    }
}

#if os(iOS)
/// A View only for showing syncing status
struct FileICloudSyncStatusIndicator: View {
    var file: FileState.ActiveFile
    
    @State private var fileStatus: FileStatus? = nil
    var body: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                ZStack {
                    if fileStatus?.iCloudStatus == .syncing {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90Icloud)
                            .drawOnAppear(options: .speed(2))
                    } else {
                        Image(systemSymbol: .checkmarkIcloud)
                            .drawOnAppear(options: .speed(2))
                            .foregroundStyle(.green)
                    }
                }
            } else {
                if fileStatus?.iCloudStatus == .syncing {
                    if #available(macOS 15.0, iOS 18.0, *) {
                        Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90Icloud)
                    } else {
                        Image(systemSymbol: .arrowTriangle2Circlepath)
                    }
                } else if case .downloaded = fileStatus?.iCloudStatus {
                    Image(systemSymbol: .checkmarkIcloud)
                        .foregroundStyle(.green)
                }
            }
        }
        .bindFileStatus(for: file, status: $fileStatus)
        .symbolRenderingMode(.multicolor)
        .animation(.smooth, value: fileStatus?.iCloudStatus)
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
