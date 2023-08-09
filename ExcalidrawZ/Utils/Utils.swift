//
//  Utils.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/26.
//

import Foundation

func loadResource<T: Decodable>(_ filename: String) -> T {
    let data: Data

    guard let file = Bundle.main.url(forResource: filename, withExtension: nil)
        else {
            fatalError("Couldn't find \(filename) in main bundle.")
    }

    do {
        data = try Data(contentsOf: file)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }

    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(T.self):\n\(error.localizedDescription)")
    }
}



func archiveAllFiles() throws {
    let panel = ExcalidrawOpenPanel.exportPanel
    if panel.runModal() == .OK {
        if let url = panel.url {
            let filemanager = FileManager.default
            do {
                let allFiles = try PersistenceController.shared.listAllFiles()
                let exportURL = url.appendingPathComponent("ExcalidrawZ exported at \(Date.now.formatted(date: .abbreviated, time: .shortened))", conformingTo: .directory)
                try filemanager.createDirectory(at: exportURL, withIntermediateDirectories: false)
                for files in allFiles {
                    let dir = exportURL.appendingPathComponent(files.key, conformingTo: .directory)
                    try filemanager.createDirectory(at: dir, withIntermediateDirectories: false)
                    for file in files.value {
                        let filePath = dir.appendingPathComponent(file.name ?? "untitled", conformingTo: .fileURL).appendingPathExtension("excalidraw")
                        let path = filePath.absoluteString.replacingOccurrences(of: "file://", with: "").removingPercentEncoding ?? ""//.path(percentEncoded: false)
                        print(path)
                        if !filemanager.createFile(atPath: path, contents: file.content) {
                            print("export file \(path) failed")
                        }
                    }
                }
            } catch {
                throw error
            }
        } else {
            throw AppError.fileError(.invalidURL)
        }
    }
}


func getTempDirectory() throws -> URL? {
    let fileManager: FileManager = FileManager.default
    var directory: URL? = nil
    if #available(macOS 13.0, *) {
        directory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: .applicationSupportDirectory, create: true)
    } else if let temp = URL(string: NSTemporaryDirectory()) {
        directory = temp
        try fileManager.createDirectory(at: directory!, withIntermediateDirectories: true)
    }
    return directory
}
