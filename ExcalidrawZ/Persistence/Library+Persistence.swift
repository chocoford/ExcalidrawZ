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
    
    static func getPersonalLibrary(context: NSManagedObjectContext) throws -> Library {
        let personalLibraryName = String(localizable: .librariesPersonalLibraryName)
        let fetchRequest = NSFetchRequest<Library>(entityName: "Library")
        fetchRequest.predicate = NSPredicate(
            format: "name = %@",
            personalLibraryName
        )
        fetchRequest.fetchLimit = 1
        let results = try context.fetch(fetchRequest)
        
        if let library = results.first {
            return library
        } else {
            let library = Library(name: personalLibraryName, context: context)
            try context.save()
            return library
        }
    }
}
