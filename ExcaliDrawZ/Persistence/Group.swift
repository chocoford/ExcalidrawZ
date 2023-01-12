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




// MARK: - Transformers
