//
//  ExcalidrawLibraryModel.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/9/4.
//

import Foundation

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
            self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
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
