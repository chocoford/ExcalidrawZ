//
//  ExcalidrawFile.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/7/25.
//

import SwiftUI
import UniformTypeIdentifiers

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
        var created: Int
        var dataURL: String
        var lastRetrieved: Int
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
        self.files = try container.decode([String : ExcalidrawFile.ResourceFile].self, forKey: .files)
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
