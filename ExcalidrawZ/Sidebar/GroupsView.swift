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

    @EnvironmentObject var fileState: FileState

    var group: Group
    var sortField: ExcalidrawFileSortField
    
    @FetchRequest
    private var children: FetchedResults<Group>
    
    @FetchRequest
    private var files: FetchedResults<File>
    
    init(
        group: Group,
        sortField: ExcalidrawFileSortField
    ) {
        self.group = group
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "parent = %@", group)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Group.name, ascending: true)]
        self._children = FetchRequest(fetchRequest: fetchRequest, animation: .default)
        
        
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
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse),
                        SortDescriptor(\.rank, order: .forward),
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
    
    var isSelected: Bool { fileState.currentGroup == group && fileState.currentFile == nil }
    
    @State private var isExpanded = false

    var body: some View {
        content()
            .animation(.smooth, value: folderStructStyle)
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if #available(macOS 13.0, *), folderStructStyle == .disclosureGroup {
            diclsureGroupView()
        } else {
            treeView()
        }
    }
    
    @available(macOS 13.0, *)
    @MainActor @ViewBuilder
    private func diclsureGroupView() -> some View {
        SelectableDisclosureGroup(
            isSelected: Binding {
                isSelected
            } set: { val in
                DispatchQueue.main.async {
                    if val {
                        fileState.currentGroup = group
                        fileState.currentFile = nil
                    }
                }
            },
            isExpanded: $isExpanded
        ) {
            ForEach(children) { group in
                GroupsView(group: group, sortField: sortField)
            }
            
            ForEach(files) { file in
                FileRowView(
                    file: file,
                    sortField: sortField,
                )
            }
            
        } label: {
            GroupRowView(
                group: group,
                isExpanded: $isExpanded
            )
        }
        .disclosureGroupIndicatorVisibility(children.isEmpty && files.isEmpty ? .hidden : .visible)
        .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { notification in
            guard let targetGroupID = notification.object as? NSManagedObjectID,
                  targetGroupID == self.group.objectID else { return }
            withAnimation(.smooth(duration: 0.2)) {
                self.isExpanded = true
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func treeView() -> some View {
        TreeStructureView(children: children, paddingLeading: 6) {
            GroupRowView(
                group: group,
                isExpanded: $isExpanded
            )
        } childView: { child in
            GroupsView(group: child, sortField: sortField)
        }
    }
}

