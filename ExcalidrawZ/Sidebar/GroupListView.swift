//
//  GroupSidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI
import CoreData

import ChocofordEssentials
import ChocofordUI

struct GroupListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @Environment(\.alert) var alert
    @Environment(\.searchExcalidrawAction) private var searchExcalidraw

    @EnvironmentObject var fileState: FileState
    
    init(sortField: ExcalidrawFileSortField) {
        self.sortField = sortField
    }

    private var sortField: ExcalidrawFileSortField
    
    @State private var isCreateICloudFolderDialogPresented = false
    @State private var isCreateLocalFolderDialogPresented = false
    
    @State private var createGroupType: CreateGroupSheetView.CreateGroupType = .group
    
    var body: some View {
        content
    }
    
    @State private var scrollViewHeight: CGFloat = .zero
    @State private var scrollViewContentHeight: CGFloat = .zero
    
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            VStack(spacing: 0) {
                                Button {
                                    fileState.setActiveFile(nil)
                                    fileState.setActiveGroupIfNeeded(nil)
                                } label: {
                                    HStack {
                                        Image(systemSymbol: .house)
                                            .frame(width: 30, alignment: .leading)
                                        Text(localizable: .sidebarRowHomeTitle)
                                    }
                                }
                                .buttonStyle(
                                    .excalidrawSidebarRow(
                                        isSelected: fileState.currentActiveFile == nil && fileState.currentActiveGroup == nil,
                                        isMultiSelected: false
                                    )
                                )
                                .id("home")
                                
                                Button {
                                    fileState.setActiveFile(nil)
                                    fileState.setActiveGroupIfNeeded(.collaboration)
                                } label: {
                                    HStack {
                                        Image(systemSymbol: .person3)
                                            .frame(width: 30, alignment: .leading)
                                        Text(.localizable(.sidebarGroupRowCollaborationTitle))
                                        
                                        Spacer()
                                        
                                        if !fileState.collaboratingFilesState.values.filter({$0 == .loaded}).isEmpty {
                                            Text(
                                                fileState.collaboratingFilesState.values.filter({$0 == .loaded}).count.formatted()
                                            )
                                            .foregroundStyle(.secondary)
                                            .padding(.trailing, 4)
                                        }
                                    }
                                }
                                .buttonStyle(
                                    .excalidrawSidebarRow(
                                        isSelected: fileState.currentActiveGroup == .collaboration,
                                        isMultiSelected: false
                                    )
                                )
                                
                                // Temporary
                                if !fileState.temporaryFiles.isEmpty {
                                    TemporaryGroupRowView()
                                }
                            }
                            
                            
                            Divider()
                            
                            // iCloud
                            DatabaseGroupsListView(sortField: sortField, fileState: fileState)
                                .modifier(
                                    ContentHeaderCreateButtonModifier(
                                        groupType: .group,
                                        title: .localizable(.sidebarGroupListSectionHeaderICloud)
                                    )
                                )

                            LinkedStorageSidebarSection()
                        }
                        .padding(8)
                        .readHeight($scrollViewContentHeight)
                        
                        Color.clear
                            .frame(height: max(0, scrollViewHeight - scrollViewContentHeight))
                    }
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
#if os(macOS)
                                if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                                    return
                                }
#endif
                                fileState.resetSelections()
                            }
                    }
                }
                .readHeight($scrollViewHeight)
                .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { output in
                    guard let targetGroupID = output.object as? NSManagedObjectID else { return }
#if os(iOS)
                    if fileState.currentActiveFile != nil,
                       isCurrentActiveGroupExpansionTarget(targetGroupID) {
                        scrollToCurrentActiveFileIfNeeded(using: proxy, delay: 0.45)
                    } else {
                        scrollToGroupLabel(targetGroupID, using: proxy, delay: 0.7)
                    }
#else
                    withAnimation(.smooth(duration: 0.2).delay(0.7)) {
                        proxy.scrollTo(targetGroupID)
                        if let group = viewContext.object(with: targetGroupID) as? Group {
                            proxy.scrollTo(group)
                        }
                        if let folder = viewContext.object(with: targetGroupID) as? LocalFolder {
                            proxy.scrollTo(folder)
                        }
                    }
#endif
                }
#if os(iOS)
                .watch(value: fileState.currentActiveFile?.id) { _ in
                    scrollToCurrentActiveFileIfNeeded(using: proxy, delay: 1.0)
                }
#endif
                .watch(value: fileState.currentActiveGroup) { newValue in
                    if newValue == nil {
                        withAnimation(.smooth(duration: 0.2)) {
                            proxy.scrollTo("home")
                        }
                    }
#if os(iOS)
                    if newValue != nil {
                        scrollToCurrentActiveFileIfNeeded(using: proxy, delay: 0.35)
                    }
#endif
                }
            }
            Divider()
            
            contentToolbar()
                .buttonStyle(.borderless)
                .padding(8)
        }
    }
    
    @ViewBuilder
    private func contentToolbar() -> some View {
        HStack {
            SettingsViewButton()

            Spacer()
            
            if #available(macOS 13.0, *) {
                sortMenuButton()
            } else {
                sortMenuButton()
                    .menuStyle(.borderlessButton)
                    // .buttonStyle(.text(size: .small, square: true))
            }
        }
        .padding(4)
        .controlSize(.regular)
        // .background(.ultraThickMaterial)
    }
    
    @ViewBuilder
    private func sortMenuButton() -> some View {
        Menu {
            Picker(
                selection: Binding {
                    fileState.sortField
                } set: { val in
                    withAnimation {
                        fileState.sortField = val
                    }
                }
            ) {
                SwiftUI.Group {
                    Label(.localizable(.sortFileKeyName), systemSymbol: .textformat).tag(ExcalidrawFileSortField.name)
                    Label(.localizable(.sortFileKeyUpdatedAt), systemSymbol: .clock).tag(ExcalidrawFileSortField.updatedAt)
                }
                .labelStyle(.titleAndIcon)
            } label: { }
                .pickerStyle(.inline)
        } label: {
            if #available(macOS 13.0, *) {
                Label(.localizable(.sortFileButtonLabelTitle), systemSymbol: .arrowUpAndDownTextHorizontal)
                    .labelStyle(.iconOnly)
            } else {
                Label(.localizable(.sortFileButtonLabelTitle), systemSymbol: .arrowUpAndDownCircle)
                    .labelStyle(.iconOnly)
            }
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func scrollToGroupLabel(
        _ groupID: NSManagedObjectID,
        using proxy: ScrollViewProxy,
        delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.smooth(duration: 0.2)) {
                if viewContext.object(with: groupID) is Group {
                    proxy.scrollTo(
                        SidebarGroupScrollTarget.group(groupID),
                        anchor: .center
                    )
                } else if viewContext.object(with: groupID) is LocalFolder {
                    proxy.scrollTo(
                        SidebarGroupScrollTarget.localFolder(groupID),
                        anchor: .center
                    )
                } else {
                    proxy.scrollTo(groupID, anchor: .center)
                }
            }
        }
    }

#if os(iOS)
    private func isCurrentActiveGroupExpansionTarget(_ groupID: NSManagedObjectID) -> Bool {
        guard let activeGroup = fileState.currentActiveGroup else {
            return false
        }

        switch activeGroup {
            case .group(let group):
                return group.containsInAncestorChain(groupID)
            case .localFolder(let folder):
                return folder.containsInAncestorChain(groupID)
            case .cloudStorageFolder, .temporary, .collaboration:
                return false
        }
    }

    private func scrollToCurrentActiveFileIfNeeded(
        using proxy: ScrollViewProxy,
        delay: TimeInterval
    ) {
        guard let target = SidebarActiveFileScrollTarget(activeFile: fileState.currentActiveFile),
              let activeFileID = fileState.currentActiveFile?.id else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard fileState.currentActiveFile?.id == activeFileID else { return }
            withAnimation(.smooth(duration: 0.2)) {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }
#endif
    
}

#if os(iOS)
private extension Group {
    func containsInAncestorChain(_ objectID: NSManagedObjectID) -> Bool {
        var currentGroup: Group? = self
        while let group = currentGroup {
            if group.objectID == objectID {
                return true
            }
            currentGroup = group.parent
        }
        return false
    }
}

private extension LocalFolder {
    func containsInAncestorChain(_ objectID: NSManagedObjectID) -> Bool {
        var currentFolder: LocalFolder? = self
        while let folder = currentFolder {
            if folder.objectID == objectID {
                return true
            }
            currentFolder = folder.parent
        }
        return false
    }
}
#endif

private struct DatabaseGroupsListView: View {
    @FetchRequest
    private var groups: FetchedResults<Group>

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "inTrash == YES")
    )
    private var trashedFiles: FetchedResults<File>

    private var sortField: ExcalidrawFileSortField
    private var fileState: FileState

    init(sortField: ExcalidrawFileSortField, fileState: FileState) {
        /// Put the important things first.
        let sortDescriptors: [SortDescriptor<Group>] = {
            switch sortField {
                case .updatedAt:
                    [
                        // SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse)
                    ]
                case .name:
                    [
                        SortDescriptor(\.name, order: .reverse),
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                    ]
                case .rank:
                    [
                        SortDescriptor(\.rank, order: .forward),
                        // SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                    ]
            }
        }()

        self.sortField = sortField
        self.fileState = fileState
        self._groups = FetchRequest(
            sortDescriptors: sortDescriptors,
            predicate: NSPredicate(
                format: "parent = nil OR type == %@",
                Group.GroupType.trash.rawValue
            )
        )
    }

    private var trashedFilesCount: Int {
        trashedFiles.count
    }

    private var displayedGroups: [Group] {
        groups
            .filter {
                $0.groupType != .trash || ($0.groupType == .trash && trashedFilesCount > 0)
            }
            .sorted { a, b in
                a.groupType == .default && b.groupType != .default ||
                a.groupType == b.groupType && b.groupType == .normal && a.createdAt ?? .distantPast < b.createdAt ?? .distantPast  ||
                a.groupType != .trash && b.groupType == .trash
            }
    }

    var body: some View {
        // ❕❕❕use `LazyVStack` will cause crash with error:
        //        FAULT: NSGenericException: The window has been marked as needing another Update Constraints in Window pass,
        //        but it has already had more Update Constraints in Window passes than there are views in the window.
        VStack(alignment: .leading, spacing: 0) {
            /// ❕❕❕use `id: \.self` can avoid multi-thread access crash when closing create-room-sheet...
            ForEach(displayedGroups, id: \.self) { group in
                GroupsView(group: group, sortField: sortField, fileState: fileState)
            }
        }
        .watch(value: trashedFilesCount) { count in
            if count == 0,
               case .group(let group) = fileState.currentActiveGroup,
               group.groupType == .trash {
                fileState.setActiveFile(nil)
                fileState.setActiveGroupIfNeeded(nil)
            }
        }
    }
}

fileprivate struct ContentHeaderCreateButtonModifier: ViewModifier {
    @Environment(\.alert) private var alert
    @Environment(\.alertToast) private var alertToast

    
    var groupType: NewGroupButton.GroupType
    var title: LocalizedStringKey
    
    init(
        groupType: NewGroupButton.GroupType,
        title: LocalizedStringKey,
    ) {
        self.groupType = groupType
        self.title = title
    }
    
    @State private var isImportLocalFolderDialogPresented = false
    @State private var isImportFilesDialogPresented = false
    @State private var isCreateGroupDialogPresented = false
    @State private var isHovered = false

    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            header()
            content
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
    
    @ViewBuilder
    private func header() -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            ZStack {
                switch groupType {
                    case .localFolder:
                        Button {
                             isImportLocalFolderDialogPresented.toggle()
                        } label: {
                            Label(.localizable(.fileHomeButtonCreateNewFolder), systemSymbol: .plusCircleFill)
                        }
                        // Two file importers can not be called in same place
                        .modifier(ImportLocalFolderModifier(isPresented: $isImportLocalFolderDialogPresented))
                    case .group:
                        Menu {
                            SwiftUI.Group {
                                Button {
                                    isCreateGroupDialogPresented.toggle()
                                } label: {
                                    Label(.localizable(.fileHomeButtonCreateNewGroup), systemSymbol: .plusCircleFill)
                                }

                                // New: Use fileImporter for cross-platform support
                                Button {
                                    isImportFilesDialogPresented.toggle()
                                } label: {
                                    Label(
                                        .localizable(.menubarButtonImport),
                                        systemSymbol: .squareAndArrowDown
                                    )
                                }
                            }
                            .labelStyle(.titleAndIcon)
                        } label: {
                            Label(.localizable(.fileHomeButtonCreateNewGroup), systemSymbol: .plusCircleFill)
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .modifier(ImportFilesModifier(isPresented: $isImportFilesDialogPresented))
                        .modifier(
                            CreateGroupModifier(
                                isPresented: $isCreateGroupDialogPresented,
                                parentGroupID: nil,
                            )
                        )
                    case .cloudStorageFolder:
                        EmptyView()
                }
            }
#if os(macOS)
            .controlSize(.large)
            .padding(.trailing, 2)
#endif
#if os(iOS)
            .tint(.secondary)
#endif
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0.4)
        }
        .font(.callout.bold())
        .animation(.smooth, value: isHovered)

    }
    
}

struct ImportFilesModifier: ViewModifier {
    @Binding var isImportFilesDialogPresented: Bool
    
    init(isPresented: Binding<Bool>) {
        self._isImportFilesDialogPresented = isPresented
    }
    
    func body(content: Content) -> some View {
        content
            .fileImporterWithAlert(
                isPresented: $isImportFilesDialogPresented,
                allowedContentTypes: [
                    .init(filenameExtension: "excalidraw") ?? .excalidrawFile,
                    .excalidrawPNG,
                    .excalidrawSVG,
                    .png,
                    .svg,
                    .folder  // Also allow directory selection
                ],
                allowsMultipleSelection: true
            ) { urls in
                NotificationCenter.default.post(
                    name: .shouldHandleImport,
                    object: urls
                )
            }
    }
}

struct ImportLocalFolderModifier: ViewModifier {
    @Environment(\.alert) private var alert
    @Environment(\.alertToast) private var alertToast
    
    @Binding var isImportLocalFolderDialogPresented: Bool
    
    init(isPresented: Binding<Bool>) {
        self._isImportLocalFolderDialogPresented = isPresented
    }
    
    func body(content: Content) -> some View {
        content
            .fileImporterWithAlert(
                isPresented: $isImportLocalFolderDialogPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true
            ) { urls in
                importLocalFolders(urls: urls)
            }
    }
    
    private struct FolderTooLargeError: LocalizedError {
        var errorDescription: String? {
            .init(localizable: .sidebarLocalFolderTooLargeAlertDescription)
        }
    }
    
    private func importLocalFolders(urls: [URL]) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                let folders = try context.fetch(request)
                
                for url in urls where folders.contains(where: { $0.url == url }) == false {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    guard let enumerator = FileManager.default.enumerator(
                        at: url,
                        includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .isHiddenKey]
                    ) else {
                        return
                    }
                    
                    var urls: [URL] = []
                    var count = 0
                    while let itemURL = enumerator.nextObject() as? URL {
                        let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                        let isHidden = resourceValues?.isHidden ?? false
                        let isDirectory = resourceValues?.isDirectory ?? false
                        
                        if isHidden {
                            if isDirectory {
                                enumerator.skipDescendants()
                            }
                            continue
                        }
                        
                        urls.append(itemURL)
                        if isDirectory {
                            count += 1
                        }
                    }
                    
                    if count > 1000 {
                        await MainActor.run {
                            alert(
                                title: .init(localizable: .sidebarLocalFolderTooLargeAlertTitle),
                                error: FolderTooLargeError()
                            )
                        }
                        return
                    }
                    
                    try await context.perform { [urls] in
                        let localFolder = try LocalFolder(url: url, context: context)
                        context.insert(localFolder)
                        try localFolder.refreshChildren(context: context)
                        // create checkpoints for every file in folder
                        for url in urls {
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
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}

struct ImportLocalFolderButton: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @State private var isImportLocalFolderDialogPresented = false
    
    var body: some View {
        Button {
            isImportLocalFolderDialogPresented.toggle()
        } label: {
            if containerHorizontalSizeClass == .compact {
                HStack(spacing: 4) {
                    Image(systemSymbol: .squareAndArrowDown)
                    Text(localizable: .sidebarGroupListButtonAddObservation)
                }
            } else {
                Label(.localizable(.sidebarGroupListButtonAddObservation), systemSymbol: .squareAndArrowDown)
            }
        }
        .modifier(ImportLocalFolderModifier(isPresented: $isImportLocalFolderDialogPresented))
    }
}
