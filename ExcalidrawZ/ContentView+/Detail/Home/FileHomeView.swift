//
//  FileHomeView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/3/25.
//

import SwiftUI
import CoreData
import SwiftyAlert
import ChocofordUI

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

struct FileHomeView<HomeGroup: ExcalidrawGroup>: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast

    @Environment(FileState.self) private var fileState
    @Environment(ItemDragState.self) private var dragState

    var group: HomeGroup
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
        self.files = files.map{ .localFile($0) }

        self._childGroups = FetchRequest<LocalFolder>(
            sortDescriptors: [NSSortDescriptor(keyPath: \LocalFolder.filePath, ascending: true)],
            predicate: NSPredicate(format: "parent == %@", group)
        )
        self.groupType = .localFolder
        self.futureActiveGroup = { .localFolder($0) }
    }
    
    @State private var selection: String?
    @State private var folderRefreshRevision = 0
    
    
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
        .task(id: "\(group.objectID.uriRepresentation().absoluteString):\((group as? LocalFolder)?.filePath ?? ""):\(folderRefreshRevision)") {
            guard let folder = group as? LocalFolder else { return }
            do { try await LocalFolder.refreshImmediateChildren(of: folder.objectID) }
            catch is CancellationError {} catch { alertToast(error) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .linkedFolderContentsDidChange)) { notification in
            guard let folder = group as? LocalFolder,
                  LinkedFolderIndexState.affects(notification, folderURL: folder.url) else { return }
            folderRefreshRevision += 1
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
        FileHomeGridContainer(
            files: files,
            itemWidth: fileItemWidth,
            showsPlaceholder: files.isEmpty,
            headerSpacing: fileGridHeaderSpacing
        ) {
            containerHeader()
        } background: {
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
    private func containerHeader() -> some View {
        VStack(spacing: 30) {
#if os(iOS)
            quickActions()
                .padding(.horizontal, 30)
#endif
            if !childGroups.isEmpty {
                childFolderGrid()
                    .padding(.horizontal, 30)
            }
        }
        .padding(.top, 36)
    }
    
    private var fileGridHeaderSpacing: CGFloat {
#if os(macOS)
        childGroups.isEmpty ? 0 : 30
#else
        30
#endif
    }

#if os(iOS)
    private func actionsMenu() -> some View {
        FileHomeGroupActionsMenu(group: group) {
            withAnimation(.smooth) {
                editMode = .active
            }
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .circle)
        .labelStyle(.iconOnly)
        .fixedSize()
    }

    @ViewBuilder
    private func quickActions() -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                quickActionsContent()
            }
        } else {
            quickActionsContent()
        }
    }

    private func quickActionsContent() -> some View {
        HStack(spacing: 10) {
            if (group as? Group)?.groupType != .trash {
                NewFileButton(usesFileHomeOpenTransition: true)
                NewGroupButton(parentID: group.objectID)
            }

            if editMode == .active {
                Button {
                    withAnimation(.smooth) {
                        editMode = .inactive
                    }
                    fileState.resetSelections()
                } label: {
                    Image(systemSymbol: .checkmark)
                        .padding(6)
                }
                .modernButtonStyle(style: .glassProminent, size: .regular, shape: .circle)
            } else {
                actionsMenu()
            }

            Spacer()
        }
        .modernButtonStyle(style: .glass, size: .regular, shape: .capsule)
    }
#endif

    @ViewBuilder
    private func childFolderGrid() -> some View {
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
                    LocalFolderItemCount(folder: group as? LocalFolder,
                                         fallbackCount: group is LocalFolder ? 0 : group.filesCount + group.subgroupsCount) { count in
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
                            itemsCount: count,
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
    }
}

/// Shared by the macOS toolbar and the iOS file-home action row.
struct FileHomeGroupActionsMenu<HomeGroup: ExcalidrawGroup>: View {
    let group: HomeGroup
    var onSelect: (() -> Void)? = nil

    @State private var isImportFilesDialogPresented = false

    var body: some View {
        SwiftUI.Group {
            if let group = group as? Group {
                GroupMenuProvider(group: group) { triggers in
                    Menu {
                        selectionMenuItem
                        GroupMenuItems(
                            group: group,
                            canExpand: false,
                            onToggleRename: triggers.onToggleRename,
                            onToogleCreateSubfolder: triggers.onToogleCreateSubfolder,
                            onToggleDelete: triggers.onToggleDelete,
                            onImportFiles: group.groupType == .trash
                                ? nil
                                : { isImportFilesDialogPresented.toggle() }
                        )
                    } label: {
                        menuLabel
                    }
                }
                .modifier(ImportFilesModifier(isPresented: $isImportFilesDialogPresented))
            } else if let folder = group as? LocalFolder {
                LocalFolderMenuProvider(folder: folder) { triggers in
                    Menu {
                        selectionMenuItem
                        LocalFolderMenuItems(
                            folder: folder,
                            canExpand: false,
                            onToggleCreateSubfolder: triggers.onToogleCreateSubfolder,
                            onToggleRemoveObservation: triggers.onToggleRemoveObservation
                        )
                    } label: {
                        menuLabel
                    }
                }
            }
        }
        .menuIndicator(.hidden)
        .labelStyle(.iconOnly)
    }

    @ViewBuilder
    private var selectionMenuItem: some View {
        if let onSelect {
            Button(action: onSelect) {
                Label(.localizable(.librariesButtonSelect), systemSymbol: .checkmarkCircle)
            }
        }
    }

    private var menuLabel: some View {
        Label(.localizable(.generalButtonMore), systemSymbol: .ellipsis)
#if os(iOS)
            .padding(6)
#endif
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
