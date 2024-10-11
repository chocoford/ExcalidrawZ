//
//  ExcalidrawFile+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation
import CoreData

extension ExcalidrawFile {
    init(from persistenceFile: File) throws {
        guard let data = persistenceFile.content else {
            struct EmptyContentError: Error {}
            throw EmptyContentError()
        }
        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = persistenceFile.id ?? UUID()
        self.content = persistenceFile.content
        self.name = persistenceFile.name
    }
    
    init(from persistenceFileID: NSManagedObjectID, context: NSManagedObjectContext) throws {
        guard let persistenceFile = context.object(with: persistenceFileID) as? File else {
            struct FileNotFoundError: Error {}
            throw FileNotFoundError()
        }
        guard let data = persistenceFile.content else {
            struct EmptyContentError: Error {}
            throw EmptyContentError()
        }
        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = persistenceFile.id ?? UUID()
        self.content = persistenceFile.content
        self.name = persistenceFile.name
    }
}
