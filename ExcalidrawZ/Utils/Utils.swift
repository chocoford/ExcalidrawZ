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
                let exportURL = url.appendingPathComponent("ExcalidrawZ exported at \(Date.now.formatted(date: .abbreviated, time: .shortened))", conformingTo: .directory)
                try filemanager.createDirectory(at: exportURL, withIntermediateDirectories: false)
                try archiveAllFiles(to: exportURL)
            } catch {
                throw error
            }
        } else {
            throw AppError.fileError(.invalidURL)
        }
    }
}

func getBackupsDir() throws -> URL {
    let filemanager = FileManager.default
    let supportDir = try filemanager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let backupsDir = supportDir.appendingPathComponent("backups", conformingTo: .directory)
    if !filemanager.fileExists(at: backupsDir) {
        try filemanager.createDirectory(at: backupsDir, withIntermediateDirectories: true)
    }
    return backupsDir
}

func backupFiles() throws {
    let fileManager = FileManager.default
    let backupsDir = try getBackupsDir()
    
    let today = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let exportURL = backupsDir.appendingPathComponent(formatter.string(from: today), conformingTo: .directory)
    
    if fileManager.fileExists(at: exportURL) { return }
    print("--- backupFiles --- \(exportURL)")
    
    try fileManager.createDirectory(at: exportURL, withIntermediateDirectories: true)
    try archiveAllFiles(to: exportURL)
    
    // clean
    let backupFolders: [URL] = try fileManager.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
        .filter { $0.hasDirectoryPath && formatter.date(from: $0.lastPathComponent) != nil }
    let sortedFolders = backupFolders.compactMap { folder -> (URL, Date)? in
        if let date = formatter.date(from: folder.lastPathComponent) {
            return (folder, date)
        }
        return nil
    }.sorted { $0.1 > $1.1 }
    
    var foldersToKeep: [URL] = []
    var seenMonths: Set<String> = []
    var seenYears: Set<String> = []
    for (folder, date) in sortedFolders {
        let daysDifference = Calendar.current.dateComponents([.day], from: date, to: today).day ?? 0
        if daysDifference <= 7 {
            foldersToKeep.append(folder)
        } else if daysDifference <= 365 {
            let monthKey = formatter.string(from: date).prefix(7) // yyyy-MM
            if !seenMonths.contains(String(monthKey)) {
                seenMonths.insert(String(monthKey))
                foldersToKeep.append(folder)
            }
        } else {
            let yearKey = formatter.string(from: date).prefix(4) // yyyy
            if !seenYears.contains(String(yearKey)) {
                seenYears.insert(String(yearKey))
                foldersToKeep.append(folder)
            }
        }
    }
    let foldersToDelete = Set(sortedFolders.map { $0.0 }).subtracting(foldersToKeep)
    for folder in foldersToDelete {
        do {
            try fileManager.removeItem(at: folder)
        } catch {
            print(error)
        }
    }
}

func archiveAllFiles(to url: URL) throws {
    let filemanager = FileManager.default
    let allFiles = try PersistenceController.shared.listAllFiles()
    for files in allFiles {
        let dir = url.appendingPathComponent(files.key, conformingTo: .directory)
        try filemanager.createDirectory(at: dir, withIntermediateDirectories: false)
        for file in files.value {
            var file = try ExcalidrawFile(from: file)
            try file.syncFiles(context: PersistenceController.shared.container.viewContext)
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
            let filePath: String = fileURL.filePath
            if !filemanager.createFile(atPath: filePath, contents: file.content) {
                print("export file \(filePath) failed")
            }
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
