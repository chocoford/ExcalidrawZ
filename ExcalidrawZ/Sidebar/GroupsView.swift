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
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var sidebarDragState: ItemDragState

    var group: Group
    var sortField: ExcalidrawFileSortField
    
    @FetchRequest
    private var children: FetchedResults<Group>
    
    @FetchRequest
    private var files: FetchedResults<File>
    
    @State private var refreshKey = UUID()
    
    init(
        group: Group,
        sortField: ExcalidrawFileSortField
    ) {
        self.group = group
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "parent = %@", group)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Group.name, ascending: true)]
        self._children = FetchRequest(fetchRequest: fetchRequest, animation: .default)
        
        /// Put the important things first.
        let sortDescriptors: [SortDescriptor<File>] = {
            switch sortField {
                case .updatedAt:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse)
                    ]
                case .name:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                        SortDescriptor(\.name, order: .reverse),
                    ]
                case .rank:
                    [
                        SortDescriptor(\.rank, order: .forward),
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                    ]
            }
        }()
        self.sortField = sortField

        self._files = FetchRequest(
            sortDescriptors: sortDescriptors,
            predicate: group.groupType == .trash ? NSPredicate(
                format: "inTrash == YES"
            ) : NSPredicate(
                format: "group == %@ AND inTrash == NO", group
            ),
            animation: .smooth
        )
    }
    
    var isSelectedBinding: Binding<Bool> {
        Binding {
            (
                fileState.currentActiveGroup == .group(group) &&
                fileState.currentActiveFile == nil
            ) ||
            isBeingDropped
        } set: { val in
            DispatchQueue.main.async {
                if val {
                    fileState.currentActiveGroup = .group(group)
                    fileState.currentActiveFile = nil
                }
            }
        }
    }
    
    @State private var isBeingDropped = false
    
    @State private var isExpanded = false

    var body: some View {
        content()
            .animation(.smooth, value: folderStructStyle)
            .onReceive(NotificationCenter.default.publisher(for: .didImportToExcalidrawZ)) { notification in
                guard let fileID = notification.object as? UUID else { return }
                if let file = files.first(where: {$0.id == fileID}) {
                    fileState.currentActiveFile = .file(file)
                }
            }
    }
    
    @MainActor @ViewBuilder
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
    @MainActor @ViewBuilder
    private func diclsureGroupView() -> some View {
        SelectableDisclosureGroup(
            isSelected: isSelectedBinding,
            isExpanded: $isExpanded
        ) {
            ForEach(children) { group in
                GroupsView(group: group, sortField: sortField)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                // `id: \.self` - Prevent crashes caused by closing the Share Sheet that was opened from the app menu.
                // MultiThread access
                ForEach(files, id: \.self) { file in
                    FileRowView(
                        file: file,
                        files: files,
                    )
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
        } label: {
            GroupRowView(
                group: group,
                isSelected: isSelectedBinding.wrappedValue,
                isExpanded: $isExpanded,
                isBeingDropped: $isBeingDropped
            )
            .modifier(GroupRowDragModifier(group: group))
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
                    if canDropToGroup {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                    } else if canDropBelowGroup {
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
        .disclosureGroupIndicatorVisibility(children.isEmpty && files.isEmpty ? .hidden : .visible)
        .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { notification in
            guard let targetGroupID = notification.object as? NSManagedObjectID,
                  targetGroupID == self.group.objectID else { return }
            withAnimation(.smooth(duration: 0.2)) {
                self.isExpanded = true
            }
        }
        .background {
            if canDropBelowGroup {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.2))
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func treeView() -> some View {
        TreeStructureView(children: children, paddingLeading: 6) {
            GroupRowView(
                group: group,
                isSelected: isSelectedBinding.wrappedValue,
                isExpanded: $isExpanded,
                isBeingDropped: $isBeingDropped
            )
        } childView: { child in
            GroupsView(group: child, sortField: sortField)
        }
    }
}

