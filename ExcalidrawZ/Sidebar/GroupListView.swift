//
//  GroupSidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

import ChocofordEssentials
import ChocofordUI

struct GroupListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @Environment(\.alert) var alert
    @EnvironmentObject var fileState: FileState
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.createdAt, order: .forward)],
        predicate: NSPredicate(format: "parent = nil")
    )
    var groups: FetchedResults<Group>
    
    init() { }
    
    var displayedGroups: [Group] {
        groups
            .filter {
                $0.groupType != .trash || ($0.groupType == .trash && self.trashedFilesCount > 0)
            }
            .sorted { a, b in
                a.groupType == .default && b.groupType != .default ||
                a.groupType == b.groupType && b.groupType == .normal && a.createdAt ?? .distantPast < b.createdAt ?? .distantPast  ||
                a.groupType != .trash && b.groupType == .trash
            }
    }

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "inTrash == YES")
    )
    private var trashedFiles: FetchedResults<File>
    
    var trashedFilesCount: Int { trashedFiles.count }
    
    @State private var isCreateICloudFolderDialogPresented = false
    @State private var isCreateLocalFolderDialogPresented = false
    
    @State private var createGroupType: CreateGroupSheetView.CreateGroupType = .group
    @State private var isCreateGroupDialogPresented = false
#if os(iOS)
    @State private var isCreateGroupConfirmationDialogPresented = false
#endif
    
    var body: some View {
        content
            .sheet(isPresented: $isCreateGroupDialogPresented) {
                if containerHorizontalSizeClass == .compact {
                    createFolderSheetView()
#if os(iOS)
                        .presentationDetents([.height(140)])
                        .presentationDragIndicator(.visible)
#endif
                } else if #available(iOS 18.0, macOS 13.0, *) {
                    createFolderSheetView()
                        .scrollDisabled(true)
                        .frame(width: 400, height: 140)
#if os(iOS)
                        .presentationSizing(.fitted)
#endif
                } else {
                    createFolderSheetView()
                }
            }
            // Watch Group disappear
            .onChange(of: fileState.isTemporaryGroupSelected) { newValue in
                if !newValue, !fileState.hasAnyActiveGroup {
                    fileState.currentGroup = displayedGroups.first
                }
            }
            .onChange(of: fileState.currentLocalFolder) { newValue in
                if newValue == nil, !fileState.hasAnyActiveGroup {
                    fileState.currentGroup = displayedGroups.first
                }
            }
            .onChange(of: fileState.currentGroup) { newValue in
                if newValue == nil, !fileState.hasAnyActiveGroup {
                    fileState.currentGroup = displayedGroups.first
                }
            }
            .onAppear {
                initialNewGroupName = getNextGroupName()
            }
    }
    
    @MainActor @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    let spacing: CGFloat = 4
                    Button {
                        if !fileState.isInCollaborationSpace {
                            fileState.isInCollaborationSpace = true
                            if containerHorizontalSizeClass != .compact {
                                fileState.currentCollaborationFile = .home
                            }
                        }
                    } label: {
                        Label(.localizable(.sidebarGroupRowCollaborationTitle), systemSymbol: .person3)
                    }
                    .buttonStyle(ListButtonStyle(selected: fileState.isInCollaborationSpace))
                    
                    Divider()

                    // Temporary
                    if !fileState.temporaryFiles.isEmpty {
                        VStack(alignment: .leading, spacing: spacing) {
                            TemporaryGroupRowView()
                        }
                    }
                    // iCloud
                    VStack(alignment: .leading, spacing: spacing) {
                        databaseGroupsList()
                            .modifier(
                                ContentHeaderCreateButtonHoverModifier(
                                    isCreateDialogPresented: Binding {
                                        isCreateGroupDialogPresented && createGroupType == .group
                                    } set: {
                                        if $0 {
                                            isCreateGroupDialogPresented = true
                                            createGroupType = .group
                                        } else {
                                            isCreateGroupDialogPresented = false
                                        }
                                    },
                                    title: .localizable(.sidebarGroupListSectionHeaderICloud)
                                )
                            )
                    }
                    
                    // Local
                    VStack(alignment: .leading, spacing: spacing) {
                        LocalFoldersListView()
                            .modifier(
                                ContentHeaderCreateButtonHoverModifier(
                                    isCreateDialogPresented: $isCreateLocalFolderDialogPresented,
                                    title: .localizable(.sidebarGroupListSectionHeaderLocal)
                                )
                            )
                            .fileImporterWithAlert(
                                isPresented: $isCreateLocalFolderDialogPresented,
                                allowedContentTypes: [.folder],
                                allowsMultipleSelection: true
                            ) { urls in
                                importLocalFolders(urls: urls)
                            }
                    }
                }
                .padding(8)
            }
            .clipped()

            HStack {
#if os(macOS)
                if #available(macOS 13.0, *) {
                    createGroupMenuButton()
                        .buttonStyle(.borderless)
                } else {
                    createGroupMenuButton()
                        .menuStyle(.borderlessButton)
                }
#elseif os(iOS)
                Button {
                    isCreateGroupConfirmationDialogPresented.toggle()
                } label: {
                    Label(
                        .localizable(.sidebarGroupListNewFolder),
                        systemSymbol: .plusCircle
                    )
                }
                .buttonStyle(.borderless)
                .confirmationDialog(
                    .localizable(.sidebarGroupListNewFolder),
                    isPresented: $isCreateGroupConfirmationDialogPresented
                ) {
                    SwiftUI.Group {
                        Button {
                            isCreateGroupDialogPresented.toggle()
                            createGroupType = .group
                        } label: {
                            Text(.localizable(.sidebarGroupListCreateTitle))
                        }
                        
                        Button {
                            isCreateLocalFolderDialogPresented.toggle()
                        } label: {
                            Text(.localizable(.sidebarGroupListButtonAddObservation))
                        }
                    }
                    .labelStyle(.titleAndIcon)
                }
#endif
                Spacer()
            }
            .padding(4)
  }

    }
    
    @MainActor @ViewBuilder
    private func databaseGroupsList() -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            /// ❕❕❕use `id: \.self` can avoid multi-thread access crash when closing create-room-sheet...
            ForEach(displayedGroups, id: \.self) { group in
                 GroupsView(group: group)
            }
        }
        .onChange(of: trashedFilesCount) { count in
            if count == 0 && fileState.currentGroup?.groupType == .trash {
                fileState.currentGroup = displayedGroups.first
            }
        }
        .onChange(of: displayedGroups) { newValue in
            if fileState.currentGroup == nil {
                fileState.currentGroup = displayedGroups.first
            } else if fileState.currentLocalFolder == nil,
                      !fileState.isTemporaryGroupSelected,
                      !fileState.isInCollaborationSpace,
                      !displayedGroups.contains(where: {$0 == fileState.currentGroup}) {
                fileState.currentGroup = displayedGroups.first
            }
            initialNewGroupName = getNextGroupName()
        }
    }
    
    @MainActor @ViewBuilder
    private func createGroupMenuButton() -> some View {
        Menu {
            SwiftUI.Group {
                Button {
                    isCreateGroupDialogPresented.toggle()
                    createGroupType = .group
                } label: {
                    Text(.localizable(.sidebarGroupListCreateTitle))
                }
                
                Button {
                    isCreateLocalFolderDialogPresented.toggle()
                } label: {
                    Text(.localizable(.sidebarGroupListButtonAddObservation))
                }
            }
            .labelStyle(.titleAndIcon)
        } label: {
            Label(
                .localizable(.sidebarGroupListNewFolder),
                systemSymbol: .plusCircle
            )
        }
        .menuIndicator(.hidden)
    }
    
    @State private var initialNewGroupName: String = ""
    
    @MainActor @ViewBuilder
    private func createFolderSheetView() -> some View {
        CreateGroupSheetView(
            name: $initialNewGroupName,
            createType: createGroupType
        ) { name in
            Task {
                do {
                    try await fileState.createNewGroup(
                        name: name,
                        activate: true,
                        context: viewContext
                    )
                } catch {
                    alertToast(error)
                }
            }
        }
    }
    
    func getNextGroupName() -> String {
        let name = String(localizable: .sidebarGroupListCreateNewGroupNamePlaceholder)
        var result = name
        var i = 1
        while groups.first(where: {$0.name == result}) != nil {
            result = "\(name) \(i)"
            i += 1
        }
        return result
    }
    
    private func importLocalFolders(urls: [URL]) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    
                    guard let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .isHiddenKey]
                    ) else {
                        return
                    }
                    
                    // Check the folder is too large (too many subfolders)
                    var count = 0
                    for case let url as URL in enumerator.allObjects {
                        let isHidden = (try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? false
                        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        if !isHidden && isDirectory {
                            count += 1
                        }
                    }
                    
                    if count > 1000 {
                        await MainActor.run {
                            struct FolderTooLargeError: LocalizedError {
                                var errorDescription: String? {
                                    .init(localizable: .sidebarLocalFolderTooLargeAlertDescription)
                                }
                            }
                            alert(title: .localizable(.sidebarLocalFolderTooLargeAlertTitle), error: FolderTooLargeError())
                        }
                        return
                    }
                    
                    try await context.perform {
                        let localFolder = try LocalFolder(url: url, context: context)
                        context.insert(localFolder)
                        try localFolder.refreshChildren(context: context)
                        // create checkpoints for every file in folder
                        for case let url as URL in enumerator {
                            if url.pathExtension == "excalidraw" {
                                let checkpoint = LocalFileCheckpoint(context: context)
                                checkpoint.url = url
                                checkpoint.content = try Data(contentsOf: url)
                                checkpoint.updatedAt = .now
                                context.insert(checkpoint)
                            }
                        }
                        try context.save()
                    }
                    
                    url.stopAccessingSecurityScopedResource()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

fileprivate struct ContentHeaderCreateButtonHoverModifier: ViewModifier {
    
    @Binding var isCreateDialogPresented: Bool
    var title: LocalizedStringKey
    
    init(
        isCreateDialogPresented: Binding<Bool>,
        title: LocalizedStringKey
    ) {
        self._isCreateDialogPresented = isCreateDialogPresented
        self.title = title
    }
    
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        Section {
            content
        } header: {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                if isHovered {
                    Button {
                        isCreateDialogPresented.toggle()
                    } label: {
                        Label(
                            .localizable(.sidebarGroupListNewFolder),
                            systemSymbol: .plusCircleFill
                        )
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.callout.bold())
            .animation(.smooth, value: isHovered)
        }
        .onHover {
            isHovered = $0
        }
    }
}



#if DEBUG


//struct GroupSidebarView_Previews: PreviewProvider {
//    static var previews: some View {
//        GroupListView(
//            store: .init(
//                initialState: .init(
//                    groups: [Group.preview],
//                    state: .init()
//                ),
//                reducer: {
//                    GroupStore()
//                }
//            )
//        )
//    }
//}
#endif
 
