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
    var filesCount: Int { get }
    
    func getParent() -> Any?
}

extension Group: ExcalidrawGroup {
    func getParent() -> Any? {
        parent
    }
    var filesCount: Int {
        files?.count ?? 0
    }
}
extension LocalFolder: ExcalidrawGroup {
    var name: String? {
        url?.lastPathComponent
    }
    func getParent() -> Any? {
        parent
    }
    var filesCount: Int {
        (try? self.getFiles(deep: false).count) ?? 0
    }
}

struct MoveToGroupMenu<Group: ExcalidrawGroup>: View {
    @Environment(\.alertToast) private var alertToast
        
    var group: Group
    var sourceGroup: Group?
    var allowSubgroups: Bool
    var childrenSortKey: KeyPath<Group, String?>
    @FetchRequest
    private var childrenGroups: FetchedResults<Group>
    
    var onMove: (_ targetGroupID: NSManagedObjectID) -> Void
    
    init(
        destination group: Group,
        sourceGroup: Group?,
        childrenSortKey: KeyPath<Group, String?>,
        allowSubgroups: Bool = false,
        onMove: @escaping (_ targetGroupID: NSManagedObjectID) -> Void
    ) {
        self.group = group
        self.sourceGroup = sourceGroup
        self.allowSubgroups = allowSubgroups
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
        } else if sourceGroup == nil || !filteredChildren.isEmpty || (sourceGroup!.getParent() as? Group != group && sourceGroup != group) {
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
                        onMove: onMove
                    )
                }
            } label: {
                Text(group.name ?? String(localizable: .generalUnknown))
            }
        }
    }
}
