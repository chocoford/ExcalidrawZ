//
//  ExcalidrawFile.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/7/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ExcalidrawFile: FileDocument {
    static var readableContentTypes: [UTType] = [.text]
    
    var content: Data
    
    init() {
        self.content = Data()
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            struct GetFileContentError: LocalizedError {
                var errorDescription: String? { "Get file contents failed." }
            }
            throw GetFileContentError()
        }
        
        print(data)
        self.content = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: content)
    }
}


#if DEBUG

//extension FileDocumentConfiguration<ExcalidrawFile> {
//    static let preview: FileDocumentConfiguration<ExcalidrawFile> = {
//        ExcalidrawFile()
//    }()
//}

#endif
