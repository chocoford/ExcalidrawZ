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
    
    
    enum ArchiveTarget {
        case file(_ groupID: NSManagedObjectID, _ fileID: NSManagedObjectID)
        case localFile(_ folderID: NSManagedObjectID, _ url: URL)
    }
    
    func archiveToLocal(
        group: FileState.ActiveGroup,
        delete: Bool,
        completionHandler: @escaping (_ error: Error?, _ target: ArchiveTarget?) -> Void
    ) throws {
        let roomID = self.objectID
        let name = self.name ?? String(localizable: .generalUntitled)
        let content = self.content
        if case .group(let group) = group {
            let groupID = group.objectID
            Task.detached {
                let context = PersistenceController.shared.container.newBackgroundContext()
                do {
                    let fileID: NSManagedObjectID? = try await context.perform {
                        guard case let group as Group = context.object(with: groupID),
                              let collaborationFile = context.object(with: roomID) as? CollaborationFile else { return nil }
                        let newFile = File(name: name, context: context)
                        newFile.group = group
                        newFile.content = content
                        newFile.inTrash = false
                        
                        context.insert(newFile)
                        
                        if delete {
                            context.delete(collaborationFile)
                        }
                        
                        try context.save()
                        
                        return newFile.objectID
                    }
                    
                    if let fileID {
                        await MainActor.run {
                            completionHandler(nil, .file(groupID, fileID))
                        }
                    } else {
                        await MainActor.run {
                            completionHandler(nil, nil)
                        }
                    }
                } catch {
                    await MainActor.run {
                        completionHandler(error, nil)
                    }
                }
            }
            
        } else if case .localFolder(let localFolder) = group {
            let localFolderID = localFolder.objectID
            Task.detached {
                let context = PersistenceController.shared.container.newBackgroundContext()
                do {
                    let fileURL: URL? = try await context.perform {
                        guard case let localFolder as LocalFolder = context.object(with: localFolderID),
                              let collaborationFile = context.object(with: roomID) as? CollaborationFile else { return nil }
                        let fileURL = try localFolder.withSecurityScopedURL { scopedURL in
                            var file = try ExcalidrawFile(from: roomID, context: context)
                            try file.syncFiles(context: context)
                            let fileURL = scopedURL.appendingPathComponent(
                                name,
                                conformingTo: .excalidrawFile
                            )
                            try file.content?.write(to: fileURL)
                            return fileURL
                        }
    
                        if delete {
                            context.delete(collaborationFile)
                        }
                        
                        try context.save()
                        
                        return fileURL
                    }
                    
                    if let fileURL {
                        await MainActor.run {
                            completionHandler(nil, .localFile(localFolderID, fileURL))
                        }
                    } else {
                        await MainActor.run {
                            completionHandler(nil, nil)
                        }
                    }
                } catch {
                    completionHandler(error, nil)
                }
            }
        }
    }
    
    func delete(context: NSManagedObjectContext, save: Bool = true) throws {
        context.delete(self)
        
        // also delete checkpoints
        let checkpointsFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
        checkpointsFetchRequest.predicate = NSPredicate(format: "collaborationFile = %@", self)
        let checkpoints = try context.fetch(checkpointsFetchRequest)
        if !checkpoints.isEmpty {
            let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: checkpoints.map{$0.objectID})
            try context.executeAndMergeChanges(using: batchDeleteRequest)
        }
        
        if save {
            try context.save()
        }
    }
    
}
