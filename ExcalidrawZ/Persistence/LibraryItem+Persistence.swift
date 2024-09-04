//
//  LibraryItem+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/3.
//

import SwiftUI
import CoreData

extension LibraryItem {
    var excalidrawLibrary: ExcalidrawLibrary {
        let library = self.library
        return ExcalidrawLibrary(
            type: library?.type ?? "excalidrawlib",
            version: Int(library?.version ?? 0),
            source: library?.source ?? "https://excalidraw.com",
            libraryItems: [
                ExcalidrawLibrary.Item(
                    id: self.id ?? UUID().uuidString,
                    status: .init(rawValue: self.status ?? "published") ?? .published,
                    createdAt: self.createdAt ?? .distantPast,
                    name: self.name ?? "Untitled",
                    elements: (try? JSONDecoder().decode([ExcalidrawElement].self, from: self.elements ?? Data())) ?? []
                )
            ]
        )
    }
}
