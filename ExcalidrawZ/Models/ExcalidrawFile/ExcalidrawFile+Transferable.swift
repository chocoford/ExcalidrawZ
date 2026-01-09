//
//  ExcalidrawFile+Transferable.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/11.
//

import SwiftUI

@available(macOS 13.0, *)
extension ExcalidrawFile: Transferable {
    func fileURL() throws -> URL {
        let fileManager: FileManager = FileManager.default
        let directory: URL = try getTempDirectory()
        
        let fileExtension = "excalidraw"
        
        let filename = (self.name ?? String(localizable: .newFileNamePlaceholder)) + ".\(fileExtension)"
        let url = directory.appendingPathComponent(filename, conformingTo: .fileURL)
        if fileManager.fileExists(atPath: url.absoluteString) {
            try fileManager.removeItem(at: url)
        }
        fileManager.createFile(atPath: url.filePath, contents: self.content)
        return url
    }
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .excalidrawFile) { file in
            SentTransferredFile(try file.fileURL(), allowAccessingOriginalFile: false)
        }
        
        DataRepresentation(exportedContentType: .excalidrawFile) { file in
            file.content ?? Data()
        }
    }
}
