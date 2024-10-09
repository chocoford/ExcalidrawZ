//
//  ExcalidrawFile+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation

extension ExcalidrawFile {
    init(from persistenceFile: File) throws {
        guard let data = persistenceFile.content else {
            struct EmptyContentError: Error {}
            throw EmptyContentError()
        }
        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = persistenceFile.id ?? UUID()
        self.content = persistenceFile.content
    }
}
