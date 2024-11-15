//
//  ExcalidrawFile.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/7/25.
//

import SwiftUI
import UniformTypeIdentifiers

import CoreData

struct ExcalidrawFile: Codable, Hashable, Sendable {
    var id = UUID()
    
    var source: String
    var files: [String: ResourceFile]
    var version: Int
    var elements: [ExcalidrawElement]
    var appState: AppState
    var type: String
    
    // MARK: Additional info (would not be encoded)
    /// The file content encoded to data.
    var content: Data?
    var name: String?
    
    struct AppState: Codable, Hashable, Sendable {
        var gridSize: Int?
        var viewBackgroundColor: String?
    }
    struct ResourceFile: Codable, Hashable, Sendable {
        var mimeType: String
        var id: String
        var createdAt: Date
        var dataURL: String
        var lastRetrievedAt: Date
        
        enum CodingKeys: String, CodingKey {
            case mimeType
            case id
            case createdAt = "created"
            case dataURL
            case lastRetrievedAt = "lastRetrieved"
        }
        
        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
            self.mimeType = try container.decode(String.self, forKey: ExcalidrawFile.ResourceFile.CodingKeys.mimeType)
            self.id = try container.decode(String.self, forKey: .id)
            let created = try container.decode(Int.self, forKey: .createdAt)
            self.createdAt = Date(timeIntervalSince1970: TimeInterval(created) / 1000)
            self.dataURL = try container.decode(String.self, forKey: .dataURL)
            let lastRetrieved = try container.decode(Int.self, forKey: .lastRetrievedAt)
            self.lastRetrievedAt = Date(timeIntervalSince1970: TimeInterval(lastRetrieved))
        }
        
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.mimeType, forKey: .mimeType)
            try container.encode(self.id, forKey: .id)
            try container.encode(Int(self.createdAt.timeIntervalSince1970 * 1000), forKey: .createdAt)
            try container.encode(self.dataURL, forKey: .dataURL)
            try container.encode(Int(self.lastRetrievedAt.timeIntervalSince1970 * 1000), forKey: .lastRetrievedAt)
        }
    }
    
    init(
        id: UUID = UUID(),
        source: String,
        files: [String : ResourceFile],
        version: Int,
        elements: [ExcalidrawElement],
        appState: AppState,
        type: String
    ) {
        self.id = id
        self.source = source
        self.files = files
        self.version = version
        self.elements = elements
        self.appState = appState
        self.type = type
    }
    
    enum CodingKeys: String, CodingKey {
        case source
        case files
        case version
        case elements
        case appState
        case type
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try container.decode(String.self, forKey: .source)
        // maybe empty if from core data
        self.files = try container.decodeIfPresent([String : ExcalidrawFile.ResourceFile].self, forKey: .files) ?? [:]
        self.version = try container.decode(Int.self, forKey: .version)
        self.elements = try container.decode([ExcalidrawElement].self, forKey: .elements)
        self.appState = try container.decode(ExcalidrawFile.AppState.self, forKey: .appState)
        self.type = try container.decode(String.self, forKey: .type)
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.source, forKey: .source)
        try container.encode(self.files, forKey: .files)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.elements, forKey: .elements)
        try container.encode(self.appState, forKey: .appState)
        try container.encode(self.type, forKey: .type)
    }

    init() {
        try! self.init(contentsOf: Bundle.main.url(forResource: "template", withExtension: "excalidraw")!)
    }
    
    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .uncached)
        try self.init(data: data)
    }
    
    init(data: Data) throws {
        self = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self.content = data
    }
}


extension UTType {
    static var excalidrawFile: UTType {
        UTType(importedAs: "com.chocoford.excalidrawFile", conformingTo: .json)
    }
    static var excalidrawlibFile: UTType {
        UTType(importedAs: "com.chocoford.excalidrawlibFile", conformingTo: .json)
    }
    static var excalidrawlibJSON: UTType {
        UTType(exportedAs: "com.chocoford.excalidrawlibJSON", conformingTo: .json)
    }
    static var excalidrawPNG: UTType {
        UTType(exportedAs: "com.chocoford.excalidrawPNG", conformingTo: .png)
    }
    static var excalidrawSVG: UTType {
        UTType(exportedAs: "com.chocoford.excalidrawSVG", conformingTo: .svg)
    }
}


#if DEBUG
extension ExcalidrawFile {
    static let preview: ExcalidrawFile = {
        ExcalidrawFile()
    }()
}


#endif
