//
//  ExcalidrawFile+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation
import CoreData

extension ExcalidrawFile {
    init( from persistenceFile: File) throws {
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
    
    init(
        from persistenceFileID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) throws {
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
    
    
    init(from checkpoint: FileCheckpoint) throws {
        guard let data = checkpoint.content else {
            struct EmptyContentError: Error {}
            throw EmptyContentError()
        }
        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = checkpoint.file?.id ?? UUID()
        self.content = checkpoint.content
        self.name = checkpoint.file?.name
    }
    
    mutating func syncFiles(context: NSManagedObjectContext) throws {
        let mediasFetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
        mediasFetchRequest.predicate = NSPredicate(format: "file.id == %@", self.id as CVarArg)
        let medias: [MediaItem] = try context.fetch(mediasFetchRequest)
        let files = medias
            .compactMap{ ExcalidrawFile.ResourceFile(mediaItem: $0) }
            .map{ [$0.id : $0] }
            .merged()
        self.files = files
        
        // update content
        if let content = self.content,
           var contentObject = try JSONSerialization.jsonObject(with: content) as? [String : Any] {
            contentObject["files"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(files))
            self.content = try JSONSerialization.data(withJSONObject: contentObject)
        }
    }
}


extension ExcalidrawFile.ResourceFile {
    init?(mediaItem: MediaItem) {
        guard let id = mediaItem.id, let dataURL = mediaItem.dataURL else {
            return nil
        }
        self.id = id
        self.dataURL = dataURL
        self.createdAt = mediaItem.createdAt ?? Date.distantPast
        self.lastRetrievedAt = mediaItem.lastRetrievedAt ?? Date.distantPast
        self.mimeType = mediaItem.mimeType ?? "image/png"
    }
}
