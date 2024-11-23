//
//  ResourceFile+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/14.
//

import Foundation
import CoreData

extension MediaItem {
    convenience init(resource: ExcalidrawFile.ResourceFile, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = resource.id
        self.createdAt = resource.createdAt
        self.dataURL = resource.dataURL
        self.mimeType = resource.mimeType
        self.lastRetrievedAt = resource.lastRetrievedAt
    }
    
    func update(with resourceFile: ExcalidrawFile.ResourceFile) {
        guard self.id == resourceFile.id else { return }
        self.createdAt = resourceFile.createdAt
        self.dataURL = resourceFile.dataURL
        self.mimeType = resourceFile.mimeType
        self.lastRetrievedAt = resourceFile.lastRetrievedAt
    }
    
//    var resourceFile: ExcalidrawFile.ResourceFile {
//        ExcalidrawFile.ResourceFile(
//    }
}
