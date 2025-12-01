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
