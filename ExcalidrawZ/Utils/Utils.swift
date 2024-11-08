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


#if canImport(AppKit)
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
                        var index = 1
                        var filename = file.name ?? String(localizable: .newFileNamePlaceholder)
                        var fileURL: URL = dir.appendingPathComponent(filename, conformingTo: .fileURL).appendingPathExtension("excalidraw")
                        var retryCount = 0
                        while filemanager.fileExists(at: fileURL), retryCount < 100 {
                            if filename.hasSuffix(" (\(index))") {
                                filename = filename.replacingOccurrences(of: " (\(index))", with: "")
                                index += 1
                            }
                            filename = "\(filename) (\(index))"
                            fileURL = fileURL
                                .deletingLastPathComponent()
                                .appendingPathComponent(filename, conformingTo: .excalidrawFile)
                            retryCount += 1
                        }
                        let filePath: String
                        if #available(macOS 13.0, *) {
                            filePath = fileURL.path(percentEncoded: false)
                        } else {
                            filePath = fileURL.standardizedFileURL.path
                        }
                        print(filePath)
                        if !filemanager.createFile(atPath: filePath, contents: file.content) {
                            print("export file \(filePath) failed")
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
#endif

func getTempDirectory() throws -> URL {
    let fileManager: FileManager = FileManager.default
    let directory: URL
    if #available(macOS 13.0, *) {
        directory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: .applicationSupportDirectory,
            create: true
        )
    } else {
        directory = fileManager.temporaryDirectory
    }
    return directory
}


func flatFiles(in directory: URL) throws -> [URL] {
    let fileManager = FileManager.default
    var isDirectory = false
    guard fileManager.fileExists(at: directory, isDirectory: &isDirectory) else {
        return []
    }
    guard isDirectory else { return [directory] }
    
    let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [])
    let files = try contents.flatMap { try flatFiles(in: $0) }
    
    print(#function, "files: \(files)")
    return files
}
