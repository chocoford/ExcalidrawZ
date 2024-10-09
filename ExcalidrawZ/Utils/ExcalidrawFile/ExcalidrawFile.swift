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
    
    /// The file content encoded to data.
    var content: Data?
    
    struct AppState: Codable, Hashable, Sendable {
        var viewBackgroundColor: String
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
        
        self.content = try? JSONEncoder().encode(self)
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
        
        self.content = try JSONEncoder().encode(self)
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
        let url = Bundle.main.url(forResource: "template", withExtension: "excalidraw")!
        self = try! JSONDecoder().decode(ExcalidrawFile.self, from: Data(contentsOf: url))
    }
}

//struct ExcalidrawFileDocument {
//    var content: Data
//    init() {
//        self.content = Data()
//    }
//    
//}

extension ExcalidrawFile: FileDocument {
    static var readableContentTypes: [UTType] = [.text]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            struct GetFileContentError: LocalizedError {
                var errorDescription: String? { "Get file contents failed." }
            }
            throw GetFileContentError()
        }
        self = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: content ?? Data())
    }
}


#if DEBUG
extension ExcalidrawFile {
    static let preview: ExcalidrawFile = {
        ExcalidrawFile()
    }()
}


#endif
