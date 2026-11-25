//
//  Group.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import Foundation
import CoreData

#if DEBUG
extension Group {
    static let preview = {
        let group = Group(context: PersistenceController.preview.container.viewContext)
        group.id = UUID()
        group.name = "preview"
        group.createdAt = .now
        return group
    }()
}
#endif

extension Group {
    /// Get the trash group from database
    static var trash: Group? {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest = NSFetchRequest<Group>(entityName: "Group")
        fetchRequest.predicate = NSPredicate(format: "type == %@", GroupType.trash.rawValue)
        fetchRequest.fetchLimit = 1
        return try? context.fetch(fetchRequest).first
    }

    convenience init(name: String, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.createdAt = .now
    }
    
    enum GroupType: String {
        case `default` = "default"
        case trash = "trash"
        case normal = "normal"
        
        var rank: Int {
            switch self {
                case .default:
                    return 0
                case .trash:
                    return 9999
                case .normal:
                    return 1
            }
        }
    }
    
    var groupType: GroupType {
        get {
            return GroupType(rawValue: self.type ?? "normal") ?? .normal
        }
        set {
            self.type = newValue.rawValue
        }
    }
}

enum SidebarGroupOrder {
    static func sortDescriptors(isTopLevel: Bool) -> [NSSortDescriptor] {
        var descriptors = [NSSortDescriptor(keyPath: \Group.rank, ascending: true)]
        if !isTopLevel {
            descriptors.append(NSSortDescriptor(keyPath: \Group.name, ascending: true))
        }
        descriptors.append(NSSortDescriptor(keyPath: \Group.createdAt, ascending: true))
        return descriptors
    }

    @MainActor
    static func move(
        _ sourceID: NSManagedObjectID,
        relativeTo destinationID: NSManagedObjectID,
        insertAfter: Bool,
        in context: NSManagedObjectContext
    ) throws {
        guard sourceID != destinationID,
              let destination = try context.existingObject(with: destinationID) as? Group,
              !destination.isDeleted,
              destination.groupType == .normal else { return }

        let parent = destination.parent
        let request = NSFetchRequest<Group>(entityName: "Group")
        request.predicate = parent.map { NSPredicate(format: "parent == %@", $0) }
            ?? NSPredicate(format: "parent == nil")
        request.sortDescriptors = sortDescriptors(isTopLevel: parent == nil)
        var siblings = try context.fetch(request).filter { $0.groupType == .normal }
        guard let sourceIndex = siblings.firstIndex(where: { $0.objectID == sourceID }),
              let destinationIndex = siblings.firstIndex(where: { $0.objectID == destinationID }) else { return }

        let insertionOffset = destinationIndex + (insertAfter ? 1 : 0)
        let insertionIndex = sourceIndex < insertionOffset ? insertionOffset - 1 : insertionOffset
        guard insertionIndex != sourceIndex else { return }

        let source = siblings.remove(at: sourceIndex)
        siblings.insert(source, at: insertionIndex)
        let previousRanks = siblings.map(\.rank)
        for (index, sibling) in siblings.enumerated() {
            // New groups keep their default rank of zero and appear after the manual order.
            let rank = Int64(index - siblings.count)
            if sibling.rank != rank { sibling.rank = rank }
        }
        do {
            try context.save()
        } catch {
            for (sibling, rank) in zip(siblings, previousRanks) where sibling.rank != rank {
                sibling.rank = rank
            }
            throw error
        }
    }
}

extension Group.GroupType: Comparable {
    static func < (lhs: Group.GroupType, rhs: Group.GroupType) -> Bool {
        return lhs.rank < rhs.rank
    }
}



// MARK: - Transformers
