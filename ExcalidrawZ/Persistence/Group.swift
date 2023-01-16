//
//  Group.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2023/1/10.
//

import Foundation

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
    enum GroupType: String {
        case `default` = "default"
        case trash = "trash"
        case normal = "normal"
        
        var rank: Int {
            switch self {
                case .default:
                    return 0
                case .trash:
                    return 100
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

extension Group.GroupType: Comparable {
    static func < (lhs: Group.GroupType, rhs: Group.GroupType) -> Bool {
        return lhs.rank < rhs.rank
    }
}



// MARK: - Transformers
