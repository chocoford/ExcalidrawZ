//
//  FileHomeView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import ChocofordUI
import SmoothGradient

struct GroupFileHomeView: View {
    var group: Group

    @FetchRequest
    private var files: FetchedResults<File>
    
    init(group: Group, sortField: ExcalidrawFileSortField) {
        self.group = group
        
        self._files = FetchRequest<File>(
            sortDescriptors: ExcalidrawFileSortProvider.fileSortDescriptors(for: sortField),
            predicate: group.groupType == .trash
            ? File.trashedPredicate
            : NSPredicate(format: "inTrash == false AND group == %@", group)
        )
    }
    
    
    var body: some View {
        FileHomeView(group: group, files: Array(files))
    }
}

struct LocalFolderFileHomeView: View {
    
    var folder: LocalFolder
    var sortField: ExcalidrawFileSortField
    
    init(folder: LocalFolder, sortField: ExcalidrawFileSortField) {
        self.folder = folder
        self.sortField = sortField
    }
    
    var body: some View {
        LocalFilesProvider(folder: folder, sortField: sortField) { files, updateFlags in
            FileHomeView(folder: folder, files: files)
        }
    }
}

struct FileHomeContainer: View {
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var fileHomeItemTransitionState: FileHomeItemTransitionState
    
    var content: AnyView
    
    init<Content: View>(
        @ViewBuilder content: () -> Content
    ) {
        self.content = AnyView(content())
    }
    
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var activeFileScrollTask: Task<Void, Never>?

    private let activeFilePreparationDelay: Duration = .milliseconds(50)
    
    var config = Config()
    
    var body: some View {
        ScrollViewReader { proxy in
            scrollView
                .watch(value: fileState.currentActiveFile, initial: true) { _, activeFile in
                    prepareActiveFileForCloseTransition(activeFile, using: proxy)
                }
                .watch(
                    value: fileHomeItemTransitionState.canShowItemContainerView,
                    initial: true
                ) { _, isVisible in
                    guard !isVisible else { return }
                    prepareActiveFileForCloseTransition(
                        fileState.currentActiveFile,
                        using: proxy
                    )
                }
                .onDisappear {
                    activeFileScrollTask?.cancel()
                }
        }
    }

    private var scrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                content
                    .readHeight($contentHeight)

                Color.clear
                    .frame(height: max(0, scrollViewHeight - contentHeight))
                    .overlay(alignment: .top) {
                        if config.isPlaceholderPresented {
                            LazyVGrid(
                                columns: [
                                    .init(
                                        .adaptive(
                                            minimum: config.itemWidth,
                                            maximum: config.itemWidth * 2 - 0.1
                                        ),
                                        spacing: 20
                                    )
                                ],
                                spacing: 20
                            ) {
                                ForEach(0..<30) { _ in
                                    FileHomeItemView.placeholder()
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    }
                    .mask {
                        if config.isPlaceholderPresented {
                            if #available(macOS 14.0, iOS 17.0, *) {
                                Rectangle()
                                    .fill(
                                        SmoothLinearGradient(
                                            from: Color.white,
                                            to: Color.white.opacity(0.0),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            } else {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.white, .white.opacity(0.0)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .overlay {
                        if config.isPlaceholderPresented {
                            if #available(macOS 14.0, iOS 17.0, *) {
                                Text(localizable: .homeNoFilesPlaceholder)
                                    .foregroundStyle(.placeholder)
                            } else {
                                Text(localizable: .homeNoFilesPlaceholder)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
            .padding(.bottom, 30)
            .background {
                config.contentBackground
            }
        }
        .readHeight($scrollViewHeight)
    }

    private func prepareActiveFileForCloseTransition(
        _ activeFile: FileState.ActiveFile?,
        using proxy: ScrollViewProxy
    ) {
        activeFileScrollTask?.cancel()
        guard let activeFile,
              !fileHomeItemTransitionState.canShowItemContainerView else {
            return
        }

        let targetID = activeFile.id
        activeFileScrollTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: activeFilePreparationDelay)
            guard !Task.isCancelled,
                  fileState.currentActiveFile?.id == targetID,
                  !fileHomeItemTransitionState.canShowItemContainerView else {
                return
            }

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                // No anchor means SwiftUI performs only the scrolling needed
                // to reveal the item; already-visible cards stay in place.
                proxy.scrollTo(targetID)
            }
        }
    }
    
    
    class Config {
        var contentBackground: AnyView?
        var isPlaceholderPresented: Bool = false
        var itemWidth: CGFloat = 240
    }
    
    @MainActor
    func contentBackground<Background: View>(
        @ViewBuilder background: () -> Background
    ) -> Self {
        config.contentBackground = AnyView(background())
        return self
    }
    
    @MainActor
    func showPlaceholder(_ isPresented: Bool, itemWidth: CGFloat) -> Self {
        config.isPlaceholderPresented = isPresented
        config.itemWidth = itemWidth
        return self
    }

}


struct FileHomeView<HomeGroup: ExcalidrawGroup>: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var dragState: ItemDragState

    var group: HomeGroup
    var parentGroups: [HomeGroup]
    var files: [FileState.ActiveFile]
    
    enum GroupType {
        case group
        case localFolder
    }
    var groupType: GroupType
    var futureActiveGroup: (HomeGroup) -> FileState.ActiveGroup
    
    @FetchRequest
    private var childGroups: FetchedResults<HomeGroup>
    
    init(group: Group, files: [File]) where HomeGroup == Group {
        self.group = group
        self.parentGroups = {
            var parents: [Group] = []
            var currentGroup: Group? = group
            while let parent = currentGroup?.parent {
                parents.append(parent)
                currentGroup = parent
            }
            return parents.reversed()
        }()
        self.files = files.map {.file($0)}

        self._childGroups = FetchRequest<Group>(
            sortDescriptors: [NSSortDescriptor(keyPath: \Group.name, ascending: true)],
            predicate: group.groupType == .trash
            ? NSPredicate(value: false)
            : NSPredicate(format: "parent == %@", group)
        )

        self.groupType = .group
        self.futureActiveGroup = { .group($0) }
    }
    
    init(folder: LocalFolder, files: [URL]) where HomeGroup == LocalFolder {
        self.group = folder
        self.parentGroups = {
            var parents: [LocalFolder] = []
            var currentGroup: LocalFolder? = folder
            while let parent = currentGroup?.parent {
                parents.append(parent)
                currentGroup = parent
            }
            return parents.reversed()
        }()
        self.files = files.map{ .localFile($0) }

        self._childGroups = FetchRequest<LocalFolder>(
            sortDescriptors: [NSSortDescriptor(keyPath: \LocalFolder.filePath, ascending: true)],
            predicate: NSPredicate(format: "parent == %@", group)
        )
        self.groupType = .localFolder
        self.futureActiveGroup = { .localFolder($0) }
    }
    
    @State private var selection: String?
    
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    
    @State private var isCreateGroupDialogPresented: Bool = false
    
#if os(iOS)
    @State private var editMode: EditMode = .inactive
#endif
    
    var body: some View {
        ZStack {
            if #available(macOS 13.0, iOS 15.0, *) {
                content()
                    .scrollContentBackground(.hidden)
            } else {
                content()
            }
        }
        .background {
            // Not working
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}
        }
    }
    
    let fileItemWidth: CGFloat = 240
    let folderItemWidth: CGFloat = 220
    
    @ViewBuilder
    private func content() -> some View {
        FileHomeContainer {
            containerContent()
                .readHeight($contentHeight)
        }
        .showPlaceholder(files.isEmpty, itemWidth: fileItemWidth)
        .contentBackground {
            Color.clear // .opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = nil
                    fileState.resetSelections()
                }
                .modifier(
                    HomeFolderItemDropModifier(group: group)
                )
        }
        .readHeight($scrollViewHeight)
#if os(iOS)
        .overlay(alignment: .bottom) {
            if #available(iOS 18.0, *), editMode.isEditing == true {
                FileMenuProvider(file: nil, fileState: fileState) { triggers in
                    HStack(spacing: 20) {
                        FileMenuItems(
                            file: nil,
                            fileState: fileState
                        ) {
                            triggers.onToggleRename()
                        } onTogglePermanentlyDelete: {
                            triggers.onTogglePermanentlyDelete()
                        }
                        .labelStyle(.iconOnly)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(height: 56)
                    .background {
                        if #available(iOS 26.0, *) {
                            Capsule()
                                .fill(.background)
                                .glassEffect(in: Capsule())
                        } else {
                            Capsule()
                                .fill(.background)
                                .shadow(radius: 4)
                        }
                    }
                }
                .disabled(!fileState.selectedGroups.isEmpty)
                .transition(.move(edge: .bottom))
            }
        }
        .environment(\.editMode, $editMode)
#endif
    }
    
    @ViewBuilder
    private func header() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(parentGroups) { group in
                    Button {
                        fileState.setActiveFile(nil)
                        fileState.currentActiveGroup = futureActiveGroup(group)
                    } label: {
                        Text(group.name ?? String(localizable: .generalUntitled))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.text(size: .small))
                    // .hoverCursor(.link)

                    if group != parentGroups.last {
                        Image(systemSymbol: .chevronRight)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .font(.caption)
            
            HStack {
                Text(group.name ?? String(localizable: .generalUntitled))
                    .font(.title)
                
                Spacer()
                
                // Toolbar
                HStack {
#if os(iOS)
                    if editMode == .active {
                        Button {
                            withAnimation(.smooth) {
                                editMode = .inactive
                            }
                            fileState.resetSelections()
                        } label: {
                            Image(systemSymbol: .checkmark)
                        }
                        .modernButtonStyle(style: .glassProminent, shape: .circle)
                    } else {
                        actionsMenu()
                    }
#else
                    if #available(macOS 14.0, iOS 17.0, *) {
                        actionsMenu()
                            .buttonStyle(.accessoryBar)
                    } else {
                        actionsMenu()
                    }
#endif
                }
            }
            .padding(.horizontal, 10)
        }
    }
    
    @ViewBuilder
    private func containerContent() -> some View {
        VStack(spacing: 30) {
            header()
                .padding(.horizontal, 20)
            quickActions()
                .padding(.horizontal, 30)
            groupsAndFiles()
                .padding(.horizontal, 30)
        }
        .padding(.top, parentGroups.isEmpty ? 36 : 15)
    }
    
    @ViewBuilder
    private func actionsMenu() -> some View {
        SwiftUI.Group {
            if let group = group as? Group {
                GroupMenuProvider(group: group) { triggers in
                    Menu {
#if os(iOS)
                        if editMode == .inactive {
                            Button {
                                withAnimation(.smooth) {
                                    editMode = .active
                                }
                            } label: {
                                Label(.localizable(.librariesButtonSelect), systemSymbol: .checkmarkCircle)
                            }
                        }
#endif
                        
                        GroupMenuItems(
                            group: group,
                            canExpand: false
                        ) {
                            triggers.onToggleRename()
                        } onToogleCreateSubfolder: {
                            triggers.onToogleCreateSubfolder()
                        } onToggleDelete: {
                            triggers.onToggleDelete()
                        }
                    } label: {
#if os(iOS)
                        Label(
                            .localizable(.generalButtonMore),
                            systemSymbol: .ellipsis
                        )
                        .padding(6)
#else
                        Image(systemSymbol: .ellipsisCircle)
#endif
                    }
                }
            } else if let folder = group as? LocalFolder {
                LocalFolderMenuProvider(folder: folder) { triggers in
                    Menu {
#if os(iOS)
                        if editMode == .inactive {
                            Button {
                                editMode = .active
                            } label: {
                                Label(.localizable(.librariesButtonSelect), systemSymbol: .checkmarkCircle)
                            }
                        }
#endif
                        
                        LocalFolderMenuItems(
                            folder: folder,
                            canExpand: false
                        ) {
                            triggers.onToogleCreateSubfolder()
                        } onToggleRemoveObservation: {
                            triggers.onToggleRemoveObservation()
                        }
                    } label: {
#if os(iOS)
                        Label(
                            .localizable(.generalButtonMore),
                            systemSymbol: .ellipsis
                        )
                        .padding(6)
#else
                        Image(systemSymbol: .ellipsisCircle)
#endif
                    }
                }
            }
        }
#if os(iOS)
        .modernButtonStyle(style: .glass, shape: .circle)
        .labelStyle(.iconOnly)
        .frame(minWidth: 12, minHeight: 12)
#elseif os(macOS)
        .fixedSize()
#endif
        .menuIndicator(.hidden)
    }
    
    
    @ViewBuilder
    private func quickActions() -> some View {
        
        if let group = self.group as? Group, group.groupType == .trash {
            // Trash group actions
            HStack(spacing: 10) {
                Spacer()
            }
            .controlSize(.large)
        } else {
            // Quick Actions
            HStack(spacing: 10) {
                NewFileButton(usesFileHomeOpenTransition: true)
                
                NewGroupButton(parentID: group.objectID)
                
                Spacer()
            }
#if os(iOS)
            .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
#else
            .modifier(FileHomeQuickActionButtonStyleModifier())
#endif
        }
    }
    
    @ViewBuilder
    private func groupsAndFiles() -> some View {
        if let group = self.group as? Group, group.groupType == .trash {} else {
            // Groups
            LazyVGrid(
                columns: [
                    .init(
                        .adaptive(minimum: folderItemWidth, maximum: folderItemWidth * 2 - 0.1),
                        spacing: 20
                    )
                ],
                spacing: 20
            ) {
                ForEach(childGroups) { group in
                    HomeFolderItemView(
                        isSelected: selection == group.objectID.description,
                        isHighlighted: {
                            if let group = group as? Group {
                                return dragState.currentDropGroupTarget == .below(.group(group.objectID)) || dragState.currentDropGroupTarget == .exact(.group(group.objectID))
                            } else if let folder = group as? LocalFolder {
                                return dragState.currentDropGroupTarget == .below(.localFolder(folder.objectID)) || dragState.currentDropGroupTarget == .exact(.localFolder(folder.objectID))
                            } else {
                                return false
                            }
                        }(),
                        name: group.name ?? String(localizable: .generalUntitled),
                        itemsCount: group.filesCount + group.subgroupsCount,
                        localFolder: group as? LocalFolder
                    )
                    .modifier(FileHomeGroupContextMenuModifier(group: group))
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        fileState.currentActiveGroup = futureActiveGroup(group)
                        fileState.expandToGroup(group.objectID)
                    })
                    .simultaneousGesture(TapGesture().onEnded {
                        selection = group.objectID.description
                        fileState.resetSelections()
                    })
                    .modifier(HomeFolderItemDropModifier(group: group))
                }
            }
            .watch(value: fileState.selectedFiles.isEmpty) { isEmpty in
                if !isEmpty { selection = nil }
            }
            .watch(value: fileState.selectedLocalFiles.isEmpty) { isEmpty in
                if !isEmpty { selection = nil }
            }
            .watch(value: fileState.selectedTemporaryFiles.isEmpty) { isEmpty in
                if !isEmpty { selection = nil }
            }
            
#if os(macOS)
            .animation(.smooth, value: Array(childGroups))
#endif
        }
        FileHomeFilesGrid(files: files, itemWidth: fileItemWidth)
    }
}

struct FileHomeFilesGrid: View {
    let files: [FileState.ActiveFile]
    let itemWidth: CGFloat
    /// Invalidates the grid value when a source changes presentation metadata
    /// without changing any stable file identities.
    let contentRevision: Int

    init(
        files: [FileState.ActiveFile],
        itemWidth: CGFloat,
        contentRevision: Int = 0
    ) {
        self.files = files
        self.itemWidth = itemWidth
        self.contentRevision = contentRevision
    }

    var body: some View {
        LazyVGrid(
            columns: [
                .init(
                    .adaptive(
                        minimum: itemWidth,
                        maximum: itemWidth * 2 - 0.1
                    ),
                    spacing: 20
                )
            ],
            spacing: 20
        ) {
            ForEach(files) { file in
                FileHomeItemView(
                    file: file,
                    selectionSiblings: files
                )
                .id(file.fileHomeItemContentID)
            }
        }
        .animation(.smooth(duration: 0.22), value: files.map(\.id))
    }
}

private extension FileState.ActiveFile {
    /// Remote metadata can change without changing a cloud document's stable
    /// identity. Include its presentation snapshot in the row identity so
    /// SwiftUI refreshes that row without treating the editor as a new file.
    var fileHomeItemContentID: String {
        switch self {
            case .cloudStorageFile(let reference):
                let modifiedAt = reference.lastKnownModifiedAt?
                    .timeIntervalSinceReferenceDate ?? 0
                return "\(id):\(reference.lastKnownName):\(modifiedAt)"
            default:
                return id
        }
    }
}

struct FileHomeQuickActionButtonStyleModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
        } else {
            content
                .modernButtonStyle(shape: .capsule)
        }
    }
}


struct EmptyFilesPlaceholderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}


struct FileHomeGroupContextMenuModifier<HomeGroup>: ViewModifier {
    var group: HomeGroup
    
    func body(content: Content) -> some View {
        if let group = group as? Group {
            content
                .modifier(
                    GroupContextMenuViewModifier(
                        group: group,
                        canExpand: false
                    )
                )
        } else if let group = group as? LocalFolder {
            content
                .modifier(
                    LocalFolderContextMenuModifier(
                        folder: group,
                        canExpand: false
                    )
            )
        } else {
            content
        }
    }
    
}


//struct ScrollViewSpacerModifier: ViewModifier {
//    func body(content: Content) -> some View {
//        content
//    }
//}
