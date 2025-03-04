//
//  MoveToGroupMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/4/25.
//

import SwiftUI
import CoreData

protocol ExcalidrawFileGroupRepresentable: NSManagedObject, NSFetchRequestResult, Identifiable {
     var name: String? { get }
}

extension Group: ExcalidrawFileGroupRepresentable {
    
}
extension LocalFolder: ExcalidrawFileGroupRepresentable {
    var name: String? {
        url?.lastPathComponent
    }
}

struct MoveToGroupMenu<Group: ExcalidrawFileGroupRepresentable>: View {
    @Environment(\.alertToast) private var alertToast
        
    var group: Group
    var sourceGroup: Group
    var allowSubgroups: Bool
    var childrenSortKey: KeyPath<Group, String?>
    @FetchRequest
    private var childrenGroups: FetchedResults<Group>
    
    var onMove: (_ targetGroupID: NSManagedObjectID) -> Void
    
    init(
        destination group: Group,
        sourceGroup: Group,
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
        if childrenGroups.isEmpty {
            Button {
                self.onMove(group.objectID)
            } label: {
                Text(group.name ?? "Unknown")
            }
        } else if sourceGroup != group || allowSubgroups {
            Menu {
                if sourceGroup != group {
                    Button {
                        self.onMove(group.objectID)
                    } label: {
                        Text("Move to \"\(group.name ?? "Unknown")\"")
                    }
                    
                    Divider()
                }
                ForEach(childrenGroups) { group in
                    MoveToGroupMenu(
                        destination: group,
                        sourceGroup: sourceGroup,
                        childrenSortKey: childrenSortKey,
                        onMove: onMove
                    )
                }
            } label: {
                Text(group.name ?? "Unknown")
            }
        }
    }
}
