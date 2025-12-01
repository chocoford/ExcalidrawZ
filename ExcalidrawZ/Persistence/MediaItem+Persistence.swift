//
//  ResourceFile+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/11/14.
//

import Foundation
import CoreData

extension MediaItem {
    /// Initialize MediaItem with metadata only
    /// After calling this, you should call MediaItem.saveDataURL() to save the data URL to iCloud Drive
    convenience init(resource: ExcalidrawFile.ResourceFile, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = resource.id
        self.createdAt = resource.createdAt
        // Don't set dataURL here - caller should use MediaItem.saveDataURL() after insert
        self.mimeType = resource.mimeType
        self.lastRetrievedAt = resource.lastRetrievedAt
    }
}
