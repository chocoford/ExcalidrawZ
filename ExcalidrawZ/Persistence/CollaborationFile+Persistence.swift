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
    
    /// Return if has changed.
    func updateElements(with fileData: Data, newCheckpoint: Bool = false) throws {
        guard let data = self.content else { return }
        var obj = try JSONSerialization.jsonObject(with: data) as! [String : Any]
        guard let fileDataJson = try JSONSerialization.jsonObject(with: fileData) as? [String : Any] else {
            return
        }
        obj["elements"] = fileDataJson["elements"]
        obj.removeValue(forKey: "files")
        let contentData = try JSONSerialization.data(withJSONObject: obj)
        
        self.content = contentData
        self.updatedAt = .now

        let context = self.managedObjectContext ?? PersistenceController.shared.container.newBackgroundContext()
        
        if newCheckpoint {
            let checkpoint = FileCheckpoint(context: context)
            checkpoint.id = UUID()
            checkpoint.content = contentData
            checkpoint.filename = self.name
            checkpoint.updatedAt = .now
            self.addToCheckpoints(checkpoint)
            
            if let checkpoints = try? PersistenceController.shared.fetchFileCheckpoints(of: self, context: context),
               checkpoints.count > 50 {
                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: checkpoints.suffix(checkpoints.count - 50).map{$0.objectID})
                try context.executeAndMergeChanges(using: batchDeleteRequest)
            }
        } else if let checkpoint = try? PersistenceController.shared.getLatestCheckpoint(of: self, context: context) {
            // update latest checkpoint
            checkpoint.content = contentData
            checkpoint.filename = self.name
            checkpoint.updatedAt = .now
        }
        
    }
    
//    public func updateRoomID(_ roomID: String) async throws {
//        guard let context = self.managedObjectContext else { return }
//        try await context.perform {
//            self.roomID = roomID
//            try context.save()
//        }
//    }
}
