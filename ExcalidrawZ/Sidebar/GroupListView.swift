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
    @Environment(\.searchExcalidrawAction) private var searchExcalidraw

    @EnvironmentObject var fileState: FileState
    
    @FetchRequest
    var groups: FetchedResults<Group>
    
    init(sortField: ExcalidrawFileSortField) {
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
        
        self._groups = FetchRequest(
            sortDescriptors: sortDescriptors,
            predicate: NSPredicate(format: "parent = nil"),
            animation: .smooth
        )
        
    }
    
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
    
    var body: some View {
        content
    }
    
    @State private var scrollViewHeight: CGFloat = .zero
    @State private var scrollViewContentHeight: CGFloat = .zero
    
    @MainActor @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        VStack(spacing: 0) {
                            Button {
                                fileState.currentActiveFile = nil
                                fileState.currentActiveGroup = nil
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
                            
                            Button {
                                fileState.currentActiveFile = nil
                                fileState.currentActiveGroup = .collaboration
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
                        databaseGroupsList()
                            .modifier(
                                ContentHeaderCreateButtonHoverModifier(
                                    groupType: .group,
                                    title: .localizable(.sidebarGroupListSectionHeaderICloud)
                                )
                            )

                        // Local
                        LocalFoldersListView()
                            .modifier(
                                ContentHeaderCreateButtonHoverModifier(
                                    groupType: .localFolder,
                                    title: .localizable(.sidebarGroupListSectionHeaderLocal)
                                )
                            )
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
            
            Divider()
            
            contentToolbar()
                .buttonStyle(.borderless)
                .padding(8)
        }
    }
    
    @MainActor @ViewBuilder
    private func databaseGroupsList() -> some View {
        // ❕❕❕use `LazyVStack` will cause crash with error:
        //        FAULT: NSGenericException: The window has been marked as needing another Update Constraints in Window pass,
        //        but it has already had more Update Constraints in Window passes than there are views in the window.
        VStack(alignment: .leading, spacing: 0) {
            /// ❕❕❕use `id: \.self` can avoid multi-thread access crash when closing create-room-sheet...
            ForEach(displayedGroups, id: \.self) { group in
                GroupsView(group: group, sortField: fileState.sortField)
            }
        }
        .onChange(of: trashedFilesCount) { count in
            if count == 0,
               case .group(let group) = fileState.currentActiveGroup,
               group.groupType == .trash {
                fileState.currentActiveFile = nil
                fileState.currentActiveGroup = nil
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func contentToolbar() -> some View {
        HStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                SettingsLink().labelStyle(.iconOnly)
            } else {
                SettingsButton(useDefaultLabel: true) {
                    Label(.localizable(.settingsName), systemSymbol: .gear)
                        .labelStyle(.iconOnly)
                }
            }
            
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
    
    @MainActor @ViewBuilder
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
    
}

fileprivate struct ContentHeaderCreateButtonHoverModifier: ViewModifier {
    
    var groupType: NewGroupButton.GroupType
    var title: LocalizedStringKey
    
    init(
        groupType: NewGroupButton.GroupType,
        title: LocalizedStringKey,
    ) {
        self.groupType = groupType
        self.title = title
    }
    
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            header()
            content
        }
        .contentShape(Rectangle())
        .onHover {
            isHovered = $0
        }
    }
    
    @MainActor @ViewBuilder
    private func header() -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            ZStack {
                switch groupType {
                    case .localFolder:
                        newGroupButton()
                    case .group:
                        Menu {
                            SwiftUI.Group {
                                newGroupButton()
                                
                                Button {
                                    let panel = ExcalidrawOpenPanel.importPanel
                                    if panel.runModal() == .OK {
                                        NotificationCenter.default.post(name: .shouldHandleImport, object: panel.urls)
                                    }
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
                }
            }
            .opacity(isHovered ? 1 : 0)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .font(.callout.bold())
        .animation(.smooth, value: isHovered)
    }
    
    @MainActor @ViewBuilder
    private func newGroupButton() -> some View {
        NewGroupButton(type: groupType, parentID: nil) { type in
            ZStack {
                switch type {
                    case .localFolder:
                        Label(.localizable(.fileHomeButtonCreateNewFolder), systemSymbol: .plusCircleFill)
                    case .group:
                        Label(.localizable(.fileHomeButtonCreateNewGroup), systemSymbol: .plusCircleFill)
                }
            }
        }
    }
}
