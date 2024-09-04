//
//  Library+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/3.
//

import SwiftUI
import CoreData

extension Library {
    convenience init(name: String, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = UUID()
        self.createdAt = Date()
        self.name = name
        self.source = "https://excalidraw.com"
        self.version = 2
        self.items = []
    }
}
