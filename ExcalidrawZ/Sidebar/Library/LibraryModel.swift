//
//  ExcalidrawLibraryModel.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/4.
//

import Foundation

//enum ExcalidrawLibrary: Codable, Hashable {
//    case v1(V1)
//    case v2(V2)
//    
//    enum CodingKeys: String, CodingKey {
//        case version
//    }
//    
//    init(from decoder: any Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        let version = try container.decode(Int.self, forKey: .version)
//        if version == 1 {
//            self = try .v1(V1(from: decoder))
//        } else {
//            self = try .v2(V2(from: decoder))
//        }
//    }
//
//    
//    init(library: Library) {
//        self = .v2(
//            .init(
//                type: library.type ?? "excalidrawlib",
//                version: Int(library.version),
//                source: library.source ?? "https://excalidraw.com",
//                libraryItems: (library.items?.allObjects as? [LibraryItem])?.map { item in
//                    ExcalidrawLibrary.Item(
//                        id: item.id ?? UUID().uuidString,
//                        status: .init(rawValue: item.status ?? "published") ?? .published,
//                        createdAt: item.createdAt ?? .distantPast,
//                        name: item.name ?? "Untitled",
//                        elements: (try? JSONDecoder().decode([ExcalidrawElement].self, from: item.elements ?? Data())) ?? []
//                    )
//                } ?? []
//            )
//        )
//    }
//    
//    func encode(to encoder: any Encoder) throws {
//        switch self {
//            case .v1(let v1):
//                try v1.encode(to: encoder)
//            case .v2(let v2):
//                try v2.encode(to: encoder)
//        }
//    }
//    
//    var id: UUID {
//        switch self {
//            case .v1(let v1):
//                v1.id
//            case .v2(let v2):
//                v2.id
//        }
//    }
//    var name: String? {
//        switch self {
//            case .v1(let v1):
//                v1.name
//            case .v2(let v2):
//                v2.name
//        }
//    }
//    var type: String {
//        switch self {
//            case .v1(let v1):
//                v1.type
//            case .v2(let v2):
//                v2.type
//        }
//    }
//    var version: Int {
//        switch self {
//            case .v1(let v1):
//                v1.version
//            case .v2(let v2):
//                v2.version
//        }
//    }
//    var libraryItems: [Item] {
//        switch self {
//            case .v1(let v1):
//                v1.library
//            case .v2(let v2):
//                v2.libraryItems
//        }
//    }
//    
//#if DEBUG
//    static var preview: ExcalidrawLibrary {
//        do {
//            return try JSONDecoder().decode(
//                ExcalidrawLibrary.self,
//                from: Data(
//                    contentsOf: Bundle.main.url(forResource: "oracle-cloud-infrastructure-icons", withExtension: "excalidrawlib")!
//                )
//            )
//        } catch {
//            fatalError(error.localizedDescription)
//        }
//    }
//#endif
//}
//
//extension ExcalidrawLibrary {
//    struct V1: Codable, Hashable {
//        var id: UUID = UUID()
//        var name: String?
//        var type: String
//        var version: Int
//        var library: [[ExcalidrawElement]]
//        
//        enum CodingKeys: String, CodingKey {
//            case type, version, library
//        }
//        
//        init(from decoder: any Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            self.id = UUID()
//            self.name = nil
//            self.type = try container.decode(String.self, forKey: .type)
//            self.version = try container.decode(Int.self, forKey: .version)
//            self.source = try container.decode(String.self, forKey: .source)
//            self.libraryItems = try container.decode([ExcalidrawElement].self, forKey: .library)
//        }
//        
//        init(id: UUID = UUID(), name: String? = nil, type: String, version: Int, libraryItems: [Item]) {
//            self.id = id
//            self.name = name
//            self.type = type
//            self.version = version
//            self.library = libraryItems
//        }
//        
//        func encode(to encoder: any Encoder) throws {
//            var container = encoder.container(keyedBy: CodingKeys.self)
//            try container.encode(self.type, forKey: .type)
//            try container.encode(self.version, forKey: .version)
//            try container.encode(self.library, forKey: .library)
//        }
//    }
//    
//    struct V2: Codable, Hashable {
//        var id: UUID = UUID()
//        var name: String?
//        var type: String
//        var version: Int
//        var source: String
//        var libraryItems: [Item]
//        
//        enum CodingKeys: String, CodingKey {
//            case type, version, source, libraryItems
//        }
//        
//        init(from decoder: any Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            self.id = UUID()
//            self.name = nil
//            self.type = try container.decode(String.self, forKey: .type)
//            self.version = try container.decode(Int.self, forKey: .version)
//            self.source = try container.decode(String.self, forKey: .source)
//            self.libraryItems = try container.decode([Item].self, forKey: .libraryItems)
//        }
//        
//        init(id: UUID = UUID(), name: String? = nil, type: String, version: Int, source: String, libraryItems: [Item]) {
//            self.id = id
//            self.name = name
//            self.type = type
//            self.version = version
//            self.source = source
//            self.libraryItems = libraryItems
//        }
//        
//        init(library: Library) {
//            self.init(
//                type: library.type ?? "excalidrawlib",
//                version: Int(library.version),
//                source: library.source ?? "https://excalidraw.com",
//                libraryItems: (library.items?.allObjects as? [LibraryItem])?.map { item in
//                    ExcalidrawLibrary.Item(
//                        id: item.id ?? UUID().uuidString,
//                        status: .init(rawValue: item.status ?? "published") ?? .published,
//                        createdAt: item.createdAt ?? .distantPast,
//                        name: item.name ?? "Untitled",
//                        elements: (try? JSONDecoder().decode([ExcalidrawElement].self, from: item.elements ?? Data())) ?? []
//                    )
//                } ?? []
//            )
//        }
//        
//        func encode(to encoder: any Encoder) throws {
//            var container = encoder.container(keyedBy: CodingKeys.self)
//            try container.encode(self.type, forKey: .type)
//            try container.encode(self.version, forKey: .version)
//            try container.encodeIfPresent(self.source, forKey: .source)
//            try container.encode(self.libraryItems, forKey: .libraryItems)
//        }
//
//        
//        struct Item: Codable, Hashable {
//            enum Status: String, Codable {
//                case published = "published"
//                case unpublished = "unpublished"
//            }
//            
//            var id: String
//            var status: Status
//            var createdAt: Date
//            var name: String
//            var elements: [ExcalidrawElement]
//            
//            enum CodingKeys: String, CodingKey {
//                case id, status, name, elements
//                case createdAt = "created"
//            }
//            
//            init(from decoder: any Decoder) throws {
//                let container = try decoder.container(keyedBy: CodingKeys.self)
//                
//                self.id = try container.decode(String.self, forKey: .id)
//                self.status = try container.decode(Status.self, forKey: .status)
//                let ts = try container.decode(Int.self, forKey: .createdAt)
//                self.createdAt = Date(timeIntervalSince1970: Double(ts) / 1000)
//                self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? StringLiteralType(localizable: .generalUntitled)
//                self.elements = try container.decode([ExcalidrawElement].self, forKey: .elements)
//            }
//            
//            init(id: String, status: Status, createdAt: Date, name: String, elements: [ExcalidrawElement]) {
//                self.id = id
//                self.status = status
//                self.createdAt = createdAt
//                self.name = name
//                self.elements = elements
//            }
//            
//            func encode(to encoder: any Encoder) throws {
//                var container = encoder.container(keyedBy: CodingKeys.self)
//                try container.encode(self.id, forKey: .id)
//                try container.encode(self.status, forKey: .status)
//                try container.encode(Int(self.createdAt.timeIntervalSince1970 * 1000), forKey: .createdAt)
//                try container.encode(self.name, forKey: .name)
//                try container.encode(self.elements, forKey: .elements)
//            }
//            
//        }
//    }
//}

struct ExcalidrawLibrary: Codable, Hashable {
    var id: UUID = UUID()
    var name: String?
    var type: String
    var version: Int
    var source: String?
    var libraryItems: [Item]
    
    enum CodingKeys: String, CodingKey {
        case type, version, source, libraryItems, library
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = nil
        self.type = try container.decode(String.self, forKey: .type)
        self.version = try container.decode(Int.self, forKey: .version)
        switch self.version {
            case 1:
                let items = try container.decode([[ExcalidrawElement]].self, forKey: .library)
                self.libraryItems = items.map{
                    Item(id: UUID().uuidString, status: .published, createdAt: .now, name: "Untitled", elements: $0)
                }
            default:
                self.source = try container.decode(String.self, forKey: .source)
                self.libraryItems = try container.decode([Item].self, forKey: .libraryItems)
        }
        
    }
    
    init(id: UUID = UUID(), name: String? = nil, type: String, version: Int, source: String?, libraryItems: [Item]) {
        self.id = id
        self.name = name
        self.type = type
        self.version = version
        self.source = source
        self.libraryItems = libraryItems
    }
    
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
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.type, forKey: .type)
        try container.encode(self.version, forKey: .version)
        switch self.version {
            case 1:
                try container.encode(self.libraryItems.map{$0.elements}, forKey: .library)
            default:
                try container.encode(self.source, forKey: .source)
                try container.encode(self.libraryItems, forKey: .libraryItems)
        }
    }
    
    
    struct Item: Codable, Hashable {
        enum Status: String, Codable {
            case published = "published"
            case unpublished = "unpublished"
        }
        
        var id: String
        var status: Status
        var createdAt: Date
        var name: String
        var elements: [ExcalidrawElement]
        
        enum CodingKeys: String, CodingKey {
            case id, status, name, elements
            case createdAt = "created"
        }
        
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.id = try container.decode(String.self, forKey: .id)
            self.status = try container.decode(Status.self, forKey: .status)
            let ts = try container.decode(Int.self, forKey: .createdAt)
            self.createdAt = Date(timeIntervalSince1970: Double(ts) / 1000)
            self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? StringLiteralType(localizable: .generalUntitled)
            self.elements = try container.decode([ExcalidrawElement].self, forKey: .elements)
        }
        
        init(id: String, status: Status, createdAt: Date, name: String, elements: [ExcalidrawElement]) {
            self.id = id
            self.status = status
            self.createdAt = createdAt
            self.name = name
            self.elements = elements
        }
        
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.id, forKey: .id)
            try container.encode(self.status, forKey: .status)
            try container.encode(Int(self.createdAt.timeIntervalSince1970 * 1000), forKey: .createdAt)
            try container.encode(self.name, forKey: .name)
            try container.encode(self.elements, forKey: .elements)
        }
        
    }
#if DEBUG
    static var preview: ExcalidrawLibrary {
        do {
            return try JSONDecoder().decode(
                ExcalidrawLibrary.self,
                from: Data(
                    contentsOf: Bundle.main.url(forResource: "oracle-cloud-infrastructure-icons", withExtension: "excalidrawlib")!
                )
            )
        } catch {
            fatalError(error.localizedDescription)
        }
    }
#endif
}
