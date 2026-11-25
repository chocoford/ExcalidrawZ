//
//  GroupSidebarView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI
import SwiftyAlert
import CoreData

import ChocofordEssentials
import ChocofordUI

struct GroupListView: View {
    @AppStorage("FolderStructureStyle") private var folderStyle: FolderStructureStyle = .disclosureGroup
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @Environment(\.alert) var alert
    @Environment(\.searchExcalidrawAction) private var searchExcalidraw

    @Environment(FileState.self) var fileState
    
    init(sortField: ExcalidrawFileSortField) {
        self.sortField = sortField
    }

    private var sortField: ExcalidrawFileSortField
    
    @State private var isCreateICloudFolderDialogPresented = false
    @State private var isCreateLocalFolderDialogPresented = false
    
    @State private var createGroupType: CreateGroupSheetView.CreateGroupType = .group
    @State private var lastRevealStep: SidebarFileRevealStep?

    private var sidebarFileReveal: SidebarFileReveal? {
        SidebarFileReveal(fileState: fileState, folderStyle: folderStyle)
    }
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        let reveal = sidebarFileReveal
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { viewport in
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
                                    .id(SidebarGroupScrollTarget.collaboration)
                                
                                    // Temporary
                                    if !fileState.temporaryFiles.isEmpty {
                                        TemporaryGroupRowView()
                                            .id(SidebarGroupScrollTarget.temporary)
                                    }
                                }
                            
                            
                                Divider()
                            
                                // App-managed files, optionally synchronized through iCloud.
                                DatabaseGroupsListView(sortField: sortField, fileState: fileState)
                                    .modifier(
                                        ContentHeaderCreateButtonModifier(
                                            groupType: .group,
                                            title: .localizable(.sidebarGroupListSectionHeaderMyFiles)
                                        )
                                    )

                                LinkedStorageSidebarSection()
                            }
                            .padding(8)
                        }
                        .frame(minHeight: viewport.size.height, alignment: .top)
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
                    .environment(\.sidebarFileReveal, reveal)
                    .suppressSidebarHoverWhileScrolling()
                    .watch(value: reveal, initial: true) { reveal in
                        if let step = reveal?.firstStep {
                            Task { @MainActor in
                                scrollToRevealStep(step, using: proxy)
                            }
                        } else {
                            lastRevealStep = nil
                        }
                    }
                    .onPreferenceChange(SidebarFileRevealStepPreference.self) { step in
                        guard let step else { return }
                        Task { @MainActor in
                            scrollToRevealStep(step, using: proxy)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { output in
                        guard let targetGroupID = output.object as? NSManagedObjectID else { return }
                        scrollToGroupLabel(targetGroupID, using: proxy, delay: 0.7)
                    }
                    .watch(value: fileState.currentActiveGroup) { newValue in
                        if newValue == nil {
                            withAnimation(.smooth(duration: 0.2)) {
                                proxy.scrollTo("home")
                            }
                        }
                    }
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

    private func scrollToRevealStep(_ step: SidebarFileRevealStep, using proxy: ScrollViewProxy) {
        guard step.reveal == sidebarFileReveal else { return }
        if let lastRevealStep, lastRevealStep.reveal == step.reveal, lastRevealStep.index >= step.index {
            return
        }
        lastRevealStep = step
        func scroll() {
            switch step.destination {
                case .folder(let target): proxy.scrollTo(target, anchor: .center)
                case .file(let target): proxy.scrollTo(target, anchor: .center)
            }
        }
        withAnimation(.smooth(duration: 0.2)) { scroll() }
        // The lazy stack may register its IDs after the expansion animation starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard lastRevealStep == step, step.reveal == sidebarFileReveal else { return }
            scroll()
        }
    }
}

private struct DatabaseGroupsListView: View {
    @FetchRequest
    private var groups: FetchedResults<Group>

    @FetchRequest(
        sortDescriptors: [],
        predicate: File.trashedPredicate
    )
    private var trashedFiles: FetchedResults<File>

    private var sortField: ExcalidrawFileSortField
    private var fileState: FileState

    init(sortField: ExcalidrawFileSortField, fileState: FileState) {
        self.sortField = sortField
        self.fileState = fileState
        self._groups = FetchRequest(
            sortDescriptors: SidebarGroupOrder.sortDescriptors(isTopLevel: true),
            predicate: NSPredicate(
                format: "parent = nil OR type == %@",
                Group.GroupType.trash.rawValue
            ),
            animation: .smooth(duration: 0.2)
        )
    }

    private var trashedFilesCount: Int {
        trashedFiles.count
    }

    private var displayedGroups: [Group] {
        groups
            .filter {
                $0.groupType != .trash || trashedFilesCount > 0
            }
            .sorted { $0.groupType < $1.groupType }
    }

    var body: some View {
        let displayedGroups = displayedGroups
        let reorderableGroupIDs = Set(displayedGroups.lazy.filter { $0.groupType == .normal }.map(\.objectID))
        // ❕❕❕use `LazyVStack` will cause crash with error:
        //        FAULT: NSGenericException: The window has been marked as needing another Update Constraints in Window pass,
        //        but it has already had more Update Constraints in Window passes than there are views in the window.
        VStack(alignment: .leading, spacing: 0) {
            /// ❕❕❕use `id: \.self` can avoid multi-thread access crash when closing create-room-sheet...
            ForEach(displayedGroups, id: \.self) { group in
                GroupsView(
                    group: group,
                    sortField: sortField,
                    fileState: fileState,
                    reorderableGroupIDs: reorderableGroupIDs
                )
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
    @Environment(\.sidebarHoverSuppressed) private var hoverSuppressed
    @Environment(\.sidebarHoverAnimationsEnabled) private var hoverAnimationsEnabled

    
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
    @State private var isCreateGroupDialogPresented = false
    @State private var isHovered = false

    private var showsHover: Bool { !hoverSuppressed && isHovered }
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            header()
            content
        }
        .contentShape(Rectangle())
        .trackSidebarHover($isHovered)
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
                            SidebarSectionAddIcon(
                                accessibilityLabel: Text(.localizable(.fileHomeButtonCreateNewFolder))
                            )
                        }
                        // Two file importers can not be called in same place
                        .modifier(ImportLocalFolderModifier(isPresented: $isImportLocalFolderDialogPresented))
                    case .group:
                        Button {
                            isCreateGroupDialogPresented.toggle()
                        } label: {
                            SidebarSectionAddIcon(
                                accessibilityLabel: Text(.localizable(.fileHomeButtonCreateNewGroup))
                            )
                        }
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
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .opacity(showsHover ? 1 : 0.4)
            .animation(
                hoverAnimationsEnabled && !hoverSuppressed ? .smooth : nil,
                value: showsHover
            )
        }
        .frame(maxWidth: .infinity)
        .font(.callout.bold())

    }
    
}

struct ImportLocalFolderModifier: ViewModifier {
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
    
    private func importLocalFolders(urls: [URL]) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw AppError.urlError(.startAccessingSecurityScopedResourceFailed)
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    try await context.perform {
                        let request = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                        request.predicate = NSPredicate(
                            format: "parent == nil AND filePath == %@",
                            url.standardizedFileURL.filePath
                        )
                        request.fetchLimit = 1
                        if let existing = try context.fetch(request).first {
                            // Re-linking is also the recovery path for an old
                            // or provider-invalidated bookmark.
                            existing.url = url.standardizedFileURL
                            existing.filePath = url.standardizedFileURL.filePath
                            existing.bookmarkData = try url.bookmarkData(
                                options: existing.bookmarkCreationOptions,
                                includingResourceValuesForKeys: [.nameKey],
                                relativeTo: nil
                            )
                            try context.save()
                            return
                        }

                        _ = try LocalFolder(url: url, context: context)
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
