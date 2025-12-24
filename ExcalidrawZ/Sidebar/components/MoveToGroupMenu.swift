//
//  MoveToGroupMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/4/25.
//

import SwiftUI
import CoreData

protocol ExcalidrawGroup: NSManagedObject, NSFetchRequestResult, Identifiable {
    var name: String? { get }
    var groupType: Group.GroupType { get }
    var filesCount: Int { get }
    var subgroupsCount: Int { get }
    
    func getParent() -> Any?
}

extension Group: ExcalidrawGroup {
    func getParent() -> Any? {
        parent
    }
    var filesCount: Int {
        files?.count ?? 0
    }
    var subgroupsCount: Int {
        children?.count ?? 0
    }
}
extension LocalFolder: ExcalidrawGroup {
    var name: String? {
        url?.lastPathComponent
    }
    var groupType: Group.GroupType { .default }
    func getParent() -> Any? {
        parent
    }
    var filesCount: Int {
        (try? self.getFiles(deep: false).count) ?? 0
    }
    var subgroupsCount: Int {
        (try? self.getFolders().count) ?? 0
    }
}

struct MoveToGroupMenu<Group: ExcalidrawGroup>: View {
    @Environment(\.alertToast) private var alertToast
        
    var group: Group
    var sourceGroup: Group?
    var allowSubgroups: Bool
    var canMoveToParentGroup: Bool
    var childrenSortKey: KeyPath<Group, String?>
    @FetchRequest
    private var childrenGroups: FetchedResults<Group>
    
    var onMove: (_ targetGroupID: NSManagedObjectID) -> Void
    
    /// Move to group menu
    /// - Parameters:
    ///  - destination: The group to move to
    ///  - sourceGroup: The current group of the item being moved. If `nil`, it means the item is not currently in any group.
    ///  - childrenSortKey: The key path to sort the child groups of the destination
    ///  - allowSubgroups: Whether to allow moving into subgroups of the source group. Default is `false`.
    ///  - onMove: The action to perform when a group is selected to move to
    init(
        destination group: Group,
        sourceGroup: Group?,
        childrenSortKey: KeyPath<Group, String?>,
        allowSubgroups: Bool = false,
        canMoveToParentGroup: Bool = true,
        onMove: @escaping (_ targetGroupID: NSManagedObjectID) -> Void
    ) {
        self.group = group
        self.sourceGroup = sourceGroup
        self.allowSubgroups = allowSubgroups
        self.canMoveToParentGroup = canMoveToParentGroup
        self.childrenSortKey = childrenSortKey
        self.onMove = onMove
        self._childrenGroups = FetchRequest(
            sortDescriptors: [SortDescriptor(childrenSortKey, order: .forward)],
            predicate: NSPredicate(format: "parent = %@", group),
            animation: .default
        )
    }
    
    var body: some View {
        let filteredChildren = childrenGroups.filter({
            sourceGroup != $0 || allowSubgroups
        })
        
        if childrenGroups.isEmpty {
            Button {
                self.onMove(group.objectID)
            } label: {
                Text(group.name ?? String(localizable: .generalUnknown))
            }
        } else if sourceGroup == nil || !filteredChildren.isEmpty || (
            (canMoveToParentGroup || sourceGroup!.getParent() as? Group != group) && sourceGroup != group
        ) {
            Menu {
                if sourceGroup == nil || (sourceGroup!.getParent() as? Group != group && sourceGroup != group) {
                    Button {
                        self.onMove(group.objectID)
                    } label: {
                        Text("Move to \"\(group.name ?? String(localizable: .generalUnknown))\"")
                    }
                    
                    Divider()
                }

                ForEach(filteredChildren) { child in
                    MoveToGroupMenu(
                        destination: child,
                        sourceGroup: sourceGroup,
                        childrenSortKey: childrenSortKey,
                        allowSubgroups: allowSubgroups,
                        canMoveToParentGroup: canMoveToParentGroup,
                        onMove: onMove
                    )
                }
            } label: {
                Text(group.name ?? String(localizable: .generalUnknown))
            }
        }
    }
}
