//
//  FileCheckpoint+Extension.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import Foundation

#if DEBUG
extension FileCheckpoint {
    static let preview = {
        let checkpoint = FileCheckpoint(context: PersistenceController.preview.container.viewContext)
        checkpoint.id = UUID()
        checkpoint.filename = "preview"
        checkpoint.updatedAt = .now
        return checkpoint
    }()
}
#endif
