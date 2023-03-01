//
//  File.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/9.
//

import Foundation
import SwiftUI

extension File {
    func updateElements(with elementsData: Data) throws {
        guard let data = self.content else { return }
        var obj = try JSONSerialization.jsonObject(with: data) as! [String : Any]
        let elements = try JSONSerialization.jsonObject(with: elementsData)
        obj["elements"] = elements
        self.content = try JSONSerialization.data(withJSONObject: obj)
        self.updatedAt = .now
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

//extension File: Transferable {
//    public static var transferRepresentation: some TransferRepresentation {
//        CodableRepresentation(contentType: .content)
//        DataRepresentation(contentType: .layer) { layer in
//            layer.data()
//        }, importing: { data in
//            try Layer(data: data)
//        }
//        DataRepresentation(exportedContentType: .png) { layer in
//            layer.pngData()
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
        return file
    }()
}
#endif
