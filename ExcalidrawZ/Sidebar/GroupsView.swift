//
//  GroupsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/1/25.
//

import SwiftUI
import CoreData

extension Notification.Name {
    static let shouldExpandGroup = Notification.Name("ShouldExpandGroup")
}

struct GroupsView: View {
    @AppStorage("FolderStructureStyle") var folderStructStyle: FolderStructureStyle = .disclosureGroup

    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var sidebarDragState: ItemDragState

    var group: Group
    var sortField: ExcalidrawFileSortField
    var showFiles: Bool
    var fileState: FileState
    
    @FetchRequest
    private var children: FetchedResults<Group>
    
    @FetchRequest
    private var files: FetchedResults<File>
    
    @State private var refreshKey = UUID()
    @StateObject private var selectionState = SidebarGroupRowSelectionState()
    
    init(
        group: Group,
        sortField: ExcalidrawFileSortField,
        showFiles: Bool = true,
        fileState: FileState
    ) {
        self.group = group
        self.fileState = fileState
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(
            format: "parent = %@ AND type != %@",
            group,
            Group.GroupType.trash.rawValue
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Group.name, ascending: true)]
        self._children = FetchRequest(fetchRequest: fetchRequest)
        
        self.sortField = sortField

        self._files = FetchRequest(
            sortDescriptors: ExcalidrawFileSortProvider.fileSortDescriptors(for: sortField),
            predicate: group.groupType == .trash ? File.trashedPredicate : NSPredicate(
                format: "group == %@ AND inTrash == NO", group
            )
        )
        self.showFiles = showFiles
    }
    
    var isSelectedBinding: Binding<Bool> {
        Binding {
            selectionState.isSelected || isBeingDropped
        } set: { val in
            DispatchQueue.main.async {
                if val {
                    fileState.setActiveGroupIfNeeded(.group(group))
                    fileState.setActiveFile(nil)
                }
            }
        }
    }
    
    @State private var isBeingDropped = false
    
    @State private var isExpanded = false

    var body: some View {
        content()
            .animation(.smooth, value: folderStructStyle)
            .onAppear {
                selectionState.bind(group: group, fileState: fileState)
            }
            .onReceive(NotificationCenter.default.publisher(for: .didImportToExcalidrawZ)) { notification in
                guard let fileID = notification.object as? UUID else { return }
                if let file = files.first(where: {$0.id == fileID}) {
                    fileState.setActiveFile(.file(file))
                }
            }
    }
    
    @ViewBuilder
    private func content() -> some View {
        if #available(macOS 13.0, *), folderStructStyle == .disclosureGroup {
            diclsureGroupView()
        } else {
            treeView()
        }
    }
    
    var ancestors: Set<Group> {
        var parents: Set<Group> = []
        var parent: Group? = self.group
        while let p = parent {
            parents.insert(p)
            parent = p.parent
        }
        return parents
    }
    
    var canDrop: Bool {
        if case .group(let groupID) = sidebarDragState.currentDragItem,
           let draggedGroup = viewContext.object(with: groupID) as? Group,
           draggedGroup.parent != self.group,
           !ancestors.contains(draggedGroup),
           self.group.groupType != .trash {
            return true
        } else if case .file(let fileID) = sidebarDragState.currentDragItem,
                  let draggedFile = viewContext.object(with: fileID) as? File,
                  draggedFile.group != self.group {
            return true
        } else if case .localFolder = sidebarDragState.currentDragItem,
                  self.group.groupType != .trash {
            return true
        } else if case .localFile = sidebarDragState.currentDragItem,
                  self.group.groupType != .trash {
            return true
        } else if case .collaborationFile = sidebarDragState.currentDragItem,
                  self.group.groupType != .trash {
            return true
        } else if case .temporaryFile = sidebarDragState.currentDragItem,
                  self.group.groupType != .trash {
            return true
        }
        return false
    }
    
    var canDropToGroup: Bool {
        sidebarDragState.currentDropGroupTarget == .exact(.group(group.objectID)) && canDrop
    }
    
    var canDropBelowGroup: Bool {
        sidebarDragState.currentDropGroupTarget == .below(.group(group.objectID)) && canDrop
    }
    
    
    @available(macOS 13.0, *)
    @ViewBuilder
    private func diclsureGroupView() -> some View {
        SelectableDisclosureGroup(
            isSelected: isSelectedBinding,
            isExpanded: $isExpanded
        ) {
            ForEach(children) { group in
                GroupsView(group: group, sortField: sortField, showFiles: showFiles, fileState: fileState)
            }
            
            if showFiles {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // `id: \.self` - Prevent crashes caused by closing the Share Sheet that was opened from the app menu.
                    // MultiThread access
                    ForEach(files, id: \.self) { file in
//                        Text("File Row View Placeholder")
//                            .padding(6)
                        FileRowView(
                            file: file,
                            files: files,
                            fileState: fileState
                        )
                        .id(SidebarActiveFileScrollTarget.file(file.objectID))
                    }
                    // ⬇️ cause `com.apple.SwiftUI.AsyncRenderer (22): EXC_BREAKPOINT` on iOS
                    // .animation(.smooth, value: files)
                }
                .overlay(alignment: .top) {
                    if sidebarDragState.currentDropFileRowTarget == .startOfGroup(.group(group.objectID)) {
                        DropTargetPlaceholder()
                    }
                }
                .modifier(GroupRowDropModifier(
                    group: group,
                    allow: [
                        .excalidrawGroupRow,
                        .excalidrawLocalFolderRow,
                    ],
                    dropTarget: {.below($0)}
                ))
            }
        } label: {
//            Text(group.name ?? String(localizable: .generalUntitled))
//                .padding(6)
            GroupRowView(
                group: group,
                isSelected: isSelectedBinding.wrappedValue,
                isExpanded: $isExpanded,
                isBeingDropped: $isBeingDropped,
                fileState: fileState
            )
            .id(SidebarGroupScrollTarget.group(group.objectID))
            .modifier(GroupRowDragModifier(group: group))
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                fileState.expandToGroup(group.objectID)
            })
        }
        .extraLabelStyle { content in
            content
                .modifier(
                    GroupContextMenuViewModifier(
                        group: group,
                        canExpand: true,
                    )
                )
                .modifier(GroupRowDropModifier(group: group) { .exact($0) })
                .foregroundStyle(
                    canDropToGroup || canDropBelowGroup
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(HierarchicalShapeStyle.primary)
                )
                .background {
                    if canDropToGroup || canDropBelowGroup && !isExpanded {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                    } else if canDropBelowGroup && isExpanded {
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 12,
                                bottomLeading: 0,
                                bottomTrailing: 0,
                                topTrailing: 12
                            )
                        )
                        .fill(Color.accentColor)
                    }
                }
        }
        .disclosureGroupIndicatorVisibility(children.isEmpty && (files.isEmpty || !showFiles) ? .hidden : .visible)
        .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { notification in
            guard let targetGroupID = notification.object as? NSManagedObjectID,
                  targetGroupID == self.group.objectID else { return }
            withAnimation(.smooth(duration: 0.2)) {
                self.isExpanded = true
            }
        }
        .background {
            if canDropBelowGroup && isExpanded {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.2))
            }
        }
    }
    
    @ViewBuilder
    private func treeView() -> some View {
        TreeStructureView(children: children, paddingLeading: 6) {
            GroupRowView(
                group: group,
                isSelected: isSelectedBinding.wrappedValue,
                isExpanded: $isExpanded,
                isBeingDropped: $isBeingDropped,
                fileState: fileState
            )
            .id(SidebarGroupScrollTarget.group(group.objectID))
            .modifier(
                GroupContextMenuViewModifier(
                    group: group,
                    canExpand: false,
                )
            )
            .modifier(GroupRowDropModifier(group: group) { .exact($0) })
            .foregroundStyle(
                canDropToGroup || canDropBelowGroup
                ? AnyShapeStyle(Color.white)
                : AnyShapeStyle(HierarchicalShapeStyle.primary)
            )
            .background {
                if canDropToGroup || canDropBelowGroup {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor)
                }
            }
        } childView: { child in
            GroupsView(group: child, sortField: sortField, fileState: fileState)
            // No need to show files in tree view, it is too crowded.
        }
    }
}
