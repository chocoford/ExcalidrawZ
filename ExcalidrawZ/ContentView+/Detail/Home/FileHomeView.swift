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
    
    init(group: Group) {
        self.group = group
        self._files = FetchRequest<File>(
            sortDescriptors: [
                NSSortDescriptor(keyPath: \File.createdAt, ascending: false),
                NSSortDescriptor(keyPath: \File.updatedAt, ascending: false),
                NSSortDescriptor(keyPath: \File.visitedAt, ascending: false),
            ],
            predicate: group.groupType == .trash
            ? NSPredicate(format: "inTrash == true")
            : NSPredicate(format: "inTrash == false AND group == %@", group),
            animation: .default
        )
    }
    
    
    var body: some View {
        FileHomeView(group: group, files: Array(files))
    }
}

struct LocalFolderFileHomeView: View {
    
    var folder: LocalFolder
    
    init(folder: LocalFolder) {
        self.folder = folder
    }
    
    var body: some View {
        LocalFilesProvider(folder: folder, sortField: .updatedAt) { files, updateFlags in
            FileHomeView(folder: folder, files: files)
        }
    }
}

struct FileHomeContainer: View {
    
    var content: AnyView
    
    init<Content: View>(
        @ViewBuilder content: () -> Content
    ) {
        self.content = AnyView(content())
    }
    
    @State private var scrollViewHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    
    var config = Config()
    
    var body: some View {
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
                            if #available(macOS 14.0, iOS 16.0, *) {
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
                            if #available(macOS 14.0, iOS 16.0, *) {
                                Text(localizable: .homeNoFilesPlaceholder)
                                    .foregroundStyle(.placeholder)
                            } else {
                                Text(localizable: .homeNoFilesPlaceholder)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
            }
            .background {
                config.contentBackground
            }
        }
        .readHeight($scrollViewHeight)
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
            ? nil
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
                .onTapGesture {
                    print("On Tap")
                }
        }
    }
    
    let fileItemWidth: CGFloat = 240
    let folderItemWidth: CGFloat = 220
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        FileHomeContainer {
            VStack(spacing: 30) {
                header()
                    .padding(.horizontal, 20)
                quickActions()
                    .padding(.horizontal, 30)
                groupsAndFiles()
                    .padding(.horizontal, 30)
            }
            .padding(.top, parentGroups.isEmpty ? 36 : 15)
            .padding(.bottom, 30)
            .readHeight($contentHeight)
        }
        .showPlaceholder(files.isEmpty, itemWidth: fileItemWidth)
        .contentBackground {
            Color.clear // .opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = nil
                }
//                .modifier(
//                    ExcalidrawLibraryDropHandler()
//                )
                .modifier(
                    HomeFolderItemDropModifier(group: group)
                )
        }
        .readHeight($scrollViewHeight)
    }
    
    @MainActor @ViewBuilder
    private func header() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(parentGroups) { group in
                    Button {
                        fileState.currentActiveFile = nil
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
                    if #available(macOS 14.0, iOS 17.0, *) {
                        actionsMenu()
                            .buttonStyle(.accessoryBar)
                    } else {
                        actionsMenu()
                    }
                }
            }
            .padding(.horizontal, 10)
        }
    }
    
    @MainActor @ViewBuilder
    private func actionsMenu() -> some View {
        SwiftUI.Group {
            if let group = group as? Group {
                GroupMenuProvider(group: group) { triggers in
                    Menu {
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
                        Image(systemSymbol: .ellipsisCircle)
                    }
                }
            } else if let folder = group as? LocalFolder {
                LocalFolderMenuProvider(folder: folder) { triggers in
                    Menu {
                        LocalFolderMenuItems(
                            folder: folder,
                            canExpand: false
                        ) {
                            triggers.onToogleCreateSubfolder()
                        }
                    } label: {
                        Image(systemSymbol: .ellipsisCircle)
                    }
                }
            }
        }
        .fixedSize()
        .menuIndicator(.hidden)
    }
    
    
    @MainActor @ViewBuilder
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
                NewFileButton(openWithDelay: true)
                
                NewGroupButton(parentID: group.objectID)
                
                Spacer()
            }
            .controlSize(.large)
        }
    }
    
    @MainActor @ViewBuilder
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
                        itemsCount: group.filesCount,
                    )
                    .modifier(FileHomeGroupContextMenuModifier(group: group))
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        fileState.currentActiveGroup = futureActiveGroup(group)
                        fileState.expandToGroup(group.objectID)
                    })
                    .simultaneousGesture(TapGesture().onEnded {
                        selection = group.objectID.description
                    })
                    .modifier(HomeFolderItemDropModifier(group: group))
                }
            }
            
#if os(macOS)
            .animation(.smooth, value: Array(childGroups))
#endif
        }
        // Files
        LazyVGrid(
            columns: [
                .init(.adaptive(minimum: fileItemWidth, maximum: fileItemWidth * 2 - 0.1), spacing: 20)
            ],
            spacing: 20
        ) {
            ForEach(files) { file in
                FileHomeItemView(
                    file: file,
                    isSelected: Binding {
                        selection == file.id
                    } set: { val in
                        if val {
                            selection = file.id
                        }
                    },
                )
            }
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
