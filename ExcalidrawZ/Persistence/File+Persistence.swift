//
//  File.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/9.
//

import Foundation
import SwiftUI
import CoreData

extension File {
    convenience init(name: String, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }
    
    convenience init(url: URL, context: NSManagedObjectContext) throws {
        let lastPathComponent = url.lastPathComponent

        var fileNameURL = url
        for _ in 0..<lastPathComponent.count(where: {$0 == "."}) {
            fileNameURL.deletePathExtension()
        }
        let filename: String = fileNameURL.lastPathComponent
        
        self.init(name: filename, context: context)
        self.content = try Data(contentsOf: url)
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

        let viewContext = self.managedObjectContext ?? PersistenceController.shared.container.newBackgroundContext()
        if newCheckpoint {
            let checkpoint = FileCheckpoint(context: viewContext)
            checkpoint.id = UUID()
            checkpoint.content = contentData
            checkpoint.filename = self.name
            checkpoint.updatedAt = .now
            self.addToCheckpoints(checkpoint)
            
            if let checkpoints = try? PersistenceController.shared.fetchFileCheckpoints(of: self, viewContext: viewContext),
               checkpoints.count > 50 {
                self.removeFromCheckpoints(checkpoints.last!)
            }
        } else if let checkpoint = try? PersistenceController.shared.getLatestCheckpoint(of: self, viewContext: viewContext) {
            // update latest checkpoint
            checkpoint.content = contentData
            checkpoint.filename = self.name
            checkpoint.updatedAt = .now
        }
        
//        return true
    }
    
//    func update(file: ExcalidrawFile, context: NSManagedObjectContext) async throws {
//        try await context.perform {
//            guard let file = context.object(with: id) as? File,
//                  let content = excalidrawFile.content else { return }
//            
//            try file.updateElements(
//                with: content,
//                newCheckpoint: !didUpdateFile
//            )
//            let newMedias = excalidrawFile.files.filter { (id, _) in
//                file.medias?.contains(where: {
//                    ($0 as? MediaItem)?.id == id
//                }) != true
//            }
//            
//            // also update medias
//            for (_, resource) in newMedias {
//                let mediaItem = MediaItem(resource: resource, context: bgContext)
//                mediaItem.file = file
//                bgContext.insert(mediaItem)
//            }
//            
//            try bgContext.save()
//        }
//    }
}

struct FileLocalizable: Codable {
    let fileID: UUID
    let groupID: UUID
}

extension FileLocalizable: Transferable {
    @available(macOS 13.0, *)
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

//@available(macOS 13.0, *)
//extension File: Transferable {
//    public static var transferRepresentation: some TransferRepresentation {
////        CodableRepresentation(contentType: .content)
//        DataRepresentation(contentType: .layer) { layer in
//            layer.data()
//        } importing: { data in
////            try Layer(data: data)
//            
//        }
//        DataRepresentation(exportedContentType: .fileURL) { layer in
//            
//        }
//    }
//}

#if DEBUG
extension File {
    static let preview = {
        let file = File(context: PersistenceController.preview.container.viewContext)
        file.id = UUID()
        file.name = "preview"
        file.createdAt = .now
        file.group = Group.preview
//        file.content = 
        return file
    }()
}
#endif
