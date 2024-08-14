//
//  File.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/9.
//

import Foundation
import SwiftUI

extension File {
    
    convenience init(name: String, context: NSManagedObjectContext) {
        self.init(context: context)
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }
    
    func updateElements(with fileData: Data, newCheckpoint: Bool = false) throws {
        guard let data = self.content else { return }
        var obj = try JSONSerialization.jsonObject(with: data) as! [String : Any]
        guard let fileDataJson = try JSONSerialization.jsonObject(with: fileData) as? [String : Any] else {
            return
        }
        obj["elements"] = fileDataJson["elements"]
        obj["files"] = fileDataJson["files"]
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
    }
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
