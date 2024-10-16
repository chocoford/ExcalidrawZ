//
//  LibraryModel+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation

extension ExcalidrawLibrary {
    init(library: Library) {
        self.init(
            type: library.type ?? "excalidrawlib",
            version: Int(library.version),
            source: library.source ?? "https://excalidraw.com",
            libraryItems: (library.items?.allObjects as? [LibraryItem])?.map { item in
                ExcalidrawLibrary.Item(
                    id: item.id ?? UUID().uuidString,
                    status: .init(rawValue: item.status ?? "published") ?? .published,
                    createdAt: item.createdAt ?? .distantPast,
                    name: item.name ?? "Untitled",
                    elements: (try? JSONDecoder().decode([ExcalidrawElement].self, from: item.elements ?? Data())) ?? []
                )
            } ?? []
        )
    }
}
