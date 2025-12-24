//
//  CompactBrowseRootView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/19/25.
//

import SwiftUI
import CoreData

import ChocofordUI
import SFSafeSymbols

#if os(iOS)
struct CompactBrowseRootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var fileState: FileState

    @FetchRequest
    private var groups: FetchedResults<Group>

    init(sortField: ExcalidrawFileSortField = .updatedAt) {
        // Sort descriptors for groups
        let groupSortDescriptors: [SortDescriptor<Group>] = {
            switch sortField {
                case .updatedAt:
                    [
                        SortDescriptor(\.type, order: .forward),
                        SortDescriptor(\.createdAt, order: .reverse),
                    ]
                case .name:
                    [
                        SortDescriptor(\.type, order: .forward),
                        SortDescriptor(\.name, order: .forward),
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                    ]
                case .rank:
                    [
                        SortDescriptor(\.type, order: .forward),
                        SortDescriptor(\.rank, order: .forward),
                        SortDescriptor(\.createdAt, order: .reverse),
                    ]
            }
        }()

        self._groups = FetchRequest(
            sortDescriptors: groupSortDescriptors,
            predicate: NSPredicate(format: "parent = nil"),
            animation: .smooth
        )

    }

    var body: some View {
        if #available(iOS 17.0, *) {
            NavigationStack {
                content()
            }

        } else {
            NavigationStack {
                content()
            }
        }
    }
    
    @State private var isICloudSectionExpanded = true
    @State private var isLocalSectionExpanded = true

    @State private var editMode: EditMode = .inactive

    @MainActor @ViewBuilder
    private func content() -> some View {
        List {
            // iCloud Section
            expandableSection(isExpanded: $isICloudSectionExpanded) {
                ForEach(groups) { group in
                    NavigationLink(value: group.objectID) {
                        Label {
                            Text(group.name ?? String(localizable: .generalUntitled))
                        } icon: {
                            if group.groupType == .trash {
                                Image(systemSymbol: .trash)
                                    .foregroundStyle(.red)
                            } else {
                                Image(systemSymbol: .folderFill)
                                    .foregroundStyle(.blue)
                            }

                        }
                    }
                }
            } header: {
                Text("iCloud")
            }

            // Local Folders Section
            expandableSection(isExpanded: $isLocalSectionExpanded) {
                LocalFoldersProvider { folders in
                    ForEach(folders) { folder in
                        NavigationLink(value: folder.objectID) {
                            Label {
                                Text(folder.name ?? String(localizable: .generalUntitled))
                            } icon: {
                                Image(systemSymbol: .folderFill)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }
                    
                    if folders.isEmpty {
                        LocalFolderEmptyPlaceholderView()
                    }
                }
            } header: {
                Text("Local Folders")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Browse")
        .toolbar(content: toolbarContent)
        .navigationDestination(for: NSManagedObjectID.self) { objectID in
            if #available(iOS 18.0, *) {
                navigationDestination(objectID)
                    .toolbarVisibility(editMode.isEditing ? .hidden : .visible, for: .tabBar)
            } else {
                navigationDestination(objectID)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func navigationDestination(_ objectID: NSManagedObjectID) -> some View {
        ZStack {
            if let group = viewContext.object(with: objectID) as? (any ExcalidrawGroup) {
                if group is LocalFolder {
                    LocalFoldersProvider { _ in
                        CompactBrowserDestinationView(group: group)
                    }
                } else {
                    CompactBrowserDestinationView(group: group)
                }
            }
        }
        .environment(\.editMode, $editMode)
    }
    
    @MainActor @ViewBuilder
    private func expandableSection<Content: View, Header: View>(
        isExpanded: Binding<Bool>,
        content: () -> Content,
        header: () -> Header = { EmptyView() }
    ) -> some View {
        if #available(iOS 17.0, *) {
            Section(isExpanded: isExpanded) {
                content()
            } header: { header() }
        } else {
            Section {
                content()
            } header: { header() }
        }
    }
    
    @State private var isImportLocalFolderDialogPresented = false
    
    @MainActor @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            SettingsViewButton()
        }
        
        ToolbarItem(placement: .automatic) {
            Menu {
                SwiftUI.Group {
                    NewGroupButton(type: .group, parentID: nil) { type in
                        ZStack {
                            switch type {
                                case .localFolder:
                                    Label(.localizable(.fileHomeButtonCreateNewFolder), systemSymbol: .plusCircleFill)
                                case .group:
                                    Label(.localizable(.fileHomeButtonCreateNewGroup), systemSymbol: .plusCircleFill)
                            }
                        }
                    }
                    
                    Button {
                        isImportLocalFolderDialogPresented.toggle()
                    } label: {
                        Label(.localizable(.fileHomeButtonCreateNewFolder), systemSymbol: .squareAndArrowDown)
                    }
                }
                .labelStyle(.titleAndIcon)
            } label: {
                Label("More", systemSymbol: .ellipsis)
                    .labelStyle(.iconOnly)
            }
            .modifier(ImportLocalFolderModifier(isPresented: $isImportLocalFolderDialogPresented))
        }
    }
}

struct CompactBrowserDestinationView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.editMode) private var editMode
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var layoutState: LayoutState

    var objectID: NSManagedObjectID

    init<HomeGroup: ExcalidrawGroup>(group: HomeGroup) {
        self.objectID = group.objectID
    }
    
    @State private var isImportFilesDialogPresented = false
    @State private var isCreateGroupDialogPresented = false
    
    var body: some View {
        if #available(iOS 18.0, *) {
            content()
        } else {
            content()
                .overlay(alignment: .bottomLeading) {
                    if editMode?.wrappedValue.isEditing == true {
                        if #available(iOS 26.0, *) {
                            editModeToolbarContent()
                                .glassEffect(in: .capsule)
                                .safeAreaPadding(.bottom, 10)
                                .safeAreaPadding(.horizontal, 20)
                        } else {
                            editModeToolbarContent()
                        }
                        
                    }
                }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        let group = viewContext.object(with: objectID)
        SwiftUI.Group {
            if let group = group as? Group {
                CompactGroupBrowserView(
                    group: group,
                    sortField: fileState.sortField
                )
            } else if let folder = group as? LocalFolder {
                CompactLocalFolderBrowserView(
                    folder: folder
                )
            }
        }
        .navigationBarBackButtonHidden(editMode?.wrappedValue.isEditing == true)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let group = group as? Group {
                    CompactContentMoreMenu(group: group)
                } else if let group = group as? LocalFolder {
                    CompactContentMoreMenu(group: group)
                }
            }
            
            ToolbarItem(placement: .navigation) {
                if editMode?.wrappedValue.isEditing == true {
                    if let group = group as? Group {
                        SelectAllToolbarButton(group: group)
                    } else if let group = group as? LocalFolder {
                        SelectAllToolbarButton(group: group)
                    }
                }
            }
            
            ToolbarItem(placement: .principal) {
                if let group = group as? Group {
                    GroupMenuProvider(
                        group: group
                    ) { triggers in
                        Menu {
                            Section {
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
                                .labelStyle(.titleAndIcon)
                            } header: {
                                CompactFolderItemView(group: group)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(group.name ?? String(localizable: .generalUntitled))
                                    .truncationMode(.middle)
                                Image(systemSymbol: .chevronDownCircleFill)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: 150)
                        }
                    }
                } else if let folder = group as? LocalFolder {
                    LocalFolderMenuProvider(folder: folder) { triggers in
                        Menu {
                            Section {
                                LocalFolderMenuItems(
                                    folder: folder,
                                    canExpand: false
                                ) {
                                    triggers.onToogleCreateSubfolder()
                                }
                                .labelStyle(.titleAndIcon)
                            } header: {
                                CompactFolderItemView(group: folder)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(folder.name ?? String(localizable: .generalUntitled))
                                    .truncationMode(.middle)
                                Image(systemSymbol: .chevronDownCircleFill)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: 150)
                        }
                    }
                }
            }
            
            ToolbarItemGroup(placement: .bottomBar) {
                if #available(iOS 18.0, *), editMode?.wrappedValue.isEditing == true {
                    FileMenuProvider(files: fileState.selectedFiles) { triggers in
                        FileMenuItems(
                            files: fileState.selectedFiles
                        ) {
                            triggers.onToggleRename()
                        } onTogglePermanentlyDelete: {
                            triggers.onTogglePermanentlyDelete()
                        }
                        .labelStyle(.iconOnly)
                    }
                    .disabled(!fileState.selectedGroups.isEmpty)
                }
            }
        }
    }
    
    
    @MainActor @ViewBuilder
    private func editModeToolbarContent() -> some View {
        HStack(spacing: 16) {
            FileMenuProvider(files: fileState.selectedFiles) { triggers in
                FileMenuItems(
                    files: fileState.selectedFiles
                ) {
                    triggers.onToggleRename()
                } onTogglePermanentlyDelete: {
                    triggers.onTogglePermanentlyDelete()
                }
                .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }
    
}


struct CompactContentMoreMenu<HomeGroup: ExcalidrawGroup>: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var layoutState: LayoutState
    @EnvironmentObject private var fileState: FileState
    
    enum Capability {
        case select
        case createGroup
        case importFiles
    }
    
    var group: HomeGroup
    var capability: Set<Capability>
    
    init(group: HomeGroup, capability: Capability...) {
        self.group = group
        self.capability = Set(capability)
    }
    
    init(group: HomeGroup) {
        self.group = group
        self.capability = Set(
            [
                .select,
                .createGroup,
                .importFiles,
            ]
        )
    }
    
    init() where HomeGroup == Group {
        self.group = .init()
        self.capability = Set(
            [
               
            ]
        )
    }
    
    @State private var isImportFilesDialogPresented = false
    @State private var isCreateGroupDialogPresented = false
    
    
    var body: some View {
        if editMode?.wrappedValue.isEditing == true {
            Button {
                editMode?.wrappedValue = .inactive
            } label: {
                Label(.localizable(.generalButtonDone), systemSymbol: .checkmark)
                    .labelStyle(.iconOnly)
            }
            .modernButtonStyle(style: .glassProminent)
        } else {
            let groupType: NewGroupButton.GroupType = group is Group ? .group : .localFolder
            Menu {
                if !capability.intersection([.createGroup, .importFiles, .select]).isEmpty {
                    Section {
                        if capability.contains(.select) {
                            Button {
                                editMode?.wrappedValue = .active
                            } label: {
                                Label(.localizable(.librariesButtonSelect), systemSymbol: .checkmarkCircle)
                            }
                        }
                        
                        if capability.contains(.createGroup) {
                            Button {
                                isCreateGroupDialogPresented.toggle()
                            } label: {
                                switch groupType {
                                    case .localFolder:
                                        AnyView(Label(.localizable(.fileHomeButtonCreateNewFolder), systemSymbol: .folderBadgePlus))
                                    case .group:
                                        AnyView(Label(.localizable(.fileHomeButtonCreateNewGroup), systemSymbol: .folderBadgePlus))
                                }
                            }
                        }
                        
                        if capability.contains(.importFiles) {
                            Button {
                                isImportFilesDialogPresented.toggle()
                            } label: {
                                Label(
                                    .localizable(.menubarButtonImport),
                                    systemSymbol: .squareAndArrowDown
                                )
                            }
                        }
                    }
                }
                
                Section {
                    Picker("", selection: $layoutState.compactBrowserLayout) {
                        Label("Icon", systemSymbol: .squareGrid2x2).tag(LayoutState.CompactBrowserLayout.grid)
                        Label("List", systemSymbol: .listDash).tag(LayoutState.CompactBrowserLayout.list)
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Label("More", systemSymbol: .ellipsis)
                    .labelStyle(.iconOnly)
            }
            .modifier(ImportFilesModifier(isPresented: $isImportFilesDialogPresented))
            .modifier(
                CreateGroupModifier(
                    isPresented: Binding {
                        isCreateGroupDialogPresented && groupType == .group
                    } set: {
                        isCreateGroupDialogPresented = $0
                    },
                    parentGroupID: group.objectID,
                )
            )
            .modifier(
                CreateFolderModifier(
                    isPresented: Binding {
                        isCreateGroupDialogPresented && groupType == .localFolder
                    } set: {
                        isCreateGroupDialogPresented = $0
                    },
                    parentFolderID: group.objectID
                )
            )
        }
    }
}

struct SelectAllToolbarButton: View {
    @Environment(\.editMode) private var editMode
    @EnvironmentObject private var fileState: FileState
    
    @FetchRequest
    private var subgroups: FetchedResults<Group>
    @FetchRequest
    private var files: FetchedResults<File>
    
    @FetchRequest
    private var subfolders: FetchedResults<LocalFolder>
    
    init<HomeGroup: ExcalidrawGroup>(group: HomeGroup) {
        self._subgroups = FetchRequest(
            sortDescriptors: [],
            predicate: .init(format: "parent == %@", group)
        )
        
        self._files = FetchRequest(
            sortDescriptors: [],
            predicate: .init(format: "group == %@", group)
        )
        
        self._subfolders = FetchRequest(
            sortDescriptors: [],
            predicate: .init(format: "parent == %@", group)
        )
    }
    
    var isAllSelected: Bool {
        return fileState.selectedGroups == Set(subgroups.map{$0.objectID} + subfolders.map{$0.objectID})
        && fileState.selectedFiles == Set(files)
    }
    
    
    var body: some View {
        Button {
            if isAllSelected {
                deselectAll()
            } else {
                selectAllGroupsAndFiles()
            }
        } label: {
            Text(localizable: isAllSelected ? .generalButtonCancel : .librariesImportSelectAll)
        }
        .onDisappear {
            deselectAll()
        }
    }
    
    private func selectAllGroupsAndFiles() {
        fileState.selectedGroups = Set(subgroups.map{$0.objectID} + subfolders.map{$0.objectID})
        fileState.selectedFiles = Set(files)
    }
    
    private func deselectAll() {
        fileState.selectedGroups = []
        fileState.selectedFiles = []
    }
}

#Preview {
    CompactBrowseRootView()
}
#endif
