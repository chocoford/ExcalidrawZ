//
//  CollaborationFile+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/14/25.
//

import Foundation
import CoreData

extension CollaborationFile {
    convenience init(name: String, content: Data?, isOwner: Bool = false, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = UUID()
        self.roomID = nil
        self.name = name
        self.content = content
        self.isOwner = isOwner
        self.createdAt = .now
        self.updatedAt = .now
        self.inTrash = false
    }
}
