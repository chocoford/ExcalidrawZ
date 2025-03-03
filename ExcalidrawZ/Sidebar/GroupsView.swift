//
//  GroupsView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/1/25.
//

import SwiftUI

extension Notification.Name {
    static let shouldExpandGroup = Notification.Name("ShouldExpandGroup")
}

struct GroupsView: View {
    @EnvironmentObject var fileState: FileState

    var groups: FetchedResults<Group>
    var group: Group
    
    @FetchRequest
    private var children: FetchedResults<Group>
    
    init(group: Group, groups: FetchedResults<Group>) {
        self.group = group
        self.groups = groups
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "parent = %@", group)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Group.name, ascending: true)]
        self._children = FetchRequest(fetchRequest: fetchRequest, animation: .default)
    }
    
    var isSelected: Bool { fileState.currentGroup == group }
    
    @State private var isExpanded = false

    var body: some View {
        content()
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        if #available(macOS 13.0, *) {
            SelectableDisclosureGroup(
                isSelected: Binding {
                    isSelected
                } set: { val in
                    DispatchQueue.main.async {
                        if val { fileState.currentGroup = group }
                    }
                },
                isExpanded: $isExpanded
            ) {
                ForEach(children) { group in
                    GroupsView(group: group, groups: groups)
                }
            } label: {
                GroupRowView(
                    group: group,
                    topLevelGroups: groups,
                    isExpanded: $isExpanded
                )
            }
            .disclosureGroupIndicatorVisibility(children.isEmpty ? .hidden : .visible)
            .onReceive(NotificationCenter.default.publisher(for: .shouldExpandGroup)) { notification in
                guard let targetGroupID = notification.object as? NSManagedObjectID,
                      targetGroupID == self.group.objectID else { return }
                withAnimation(.smooth(duration: 0.2)) {
                    self.isExpanded = true
                }
            }
        } else {
            GroupRowView(
                group: group,
                topLevelGroups: groups,
                isExpanded: $isExpanded,
                lagacy: true
            )
        }
    }
}
