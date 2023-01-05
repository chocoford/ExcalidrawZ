//
//  AppFileManager.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation
import Combine
import OSLog

class AppFileManager: ObservableObject {
    static let shared = AppFileManager()
    
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!,
                        category: "AppFileManager")
    
    let fileManager = FileManager.default
    let rootDir = try! FileManager.default
        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        .appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
    
    var assetDir: URL { rootDir.appendingPathComponent("assets", conformingTo: .directory) }
    var trashDir: URL { rootDir.appendingPathComponent("trash", conformingTo: .directory) }
    var backupDir: URL { rootDir.appendingPathComponent("backup", conformingTo: .directory) }
       
    var defaultGroupURL: URL { assetDir.appendingPathComponent("default", conformingTo: .directory) }
        
    init() {
        performMigration()
        
        createDir()
        backupFiles()
    }
    
    private func backupFiles() {
        let today = Date.now.ISO8601Format(.iso8601Date(timeZone: .current))
        let ok = UnsafeMutablePointer<ObjCBool>.allocate(capacity: 1)
        ok[0] = true
        let todayDir = backupDir.appendingPathComponent(today, conformingTo: .directory)
        guard !fileManager.fileExists(atPath: todayDir.path(percentEncoded: false),
                                      isDirectory: ok) else {
            ok.deallocate()
            return
        }
        ok.deallocate()

        do {
            try fileManager.copyItem(at: assetDir, to: todayDir)
        } catch {
            logger.error("\(error)")
        }
    }
    
    private func createDir() {
        try? fileManager.createDirectory(at: assetDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: trashDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
    }
}

extension AppFileManager {
    /// load folders
    func loadGroups() -> [GroupInfo] {
        do {
            return try fileManager
                .contentsOfDirectory(at: assetDir,
                                     includingPropertiesForKeys: nil)
                .filter { $0.isDirectory }
                .compactMap { GroupInfo(url: $0) }
                .sorted(by: {
                    $0.createdAt < $1.createdAt
                })
        } catch {
            return []
        }
    }

    
    func loadFiles(in group: GroupInfo) -> [FileInfo] {
        do {
            return try fileManager
                .contentsOfDirectory(at: group.url,
                                     includingPropertiesForKeys: nil)
                .map { FileInfo(from: $0) }
                .filter { $0.fileExtension == "excalidraw" }
                .sorted { $0.updatedAt ?? .distantPast > $1.updatedAt ?? .distantPast}
        } catch {
            return []
        }
    }
    
    func createNewFile(at dir: URL) -> FileInfo? {
        guard let template = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else { return nil }
        let desURL = avoidDuplicate(url: dir.appending(path: "Untitled").appendingPathExtension("excalidraw"))
        do {
            let data = try Data(contentsOf: template)
            fileManager.createFile(atPath: desURL.path(percentEncoded: false), contents: data)
            logger.info("create new file done. \(desURL.lastPathComponent)")
            return FileInfo(from: desURL)
        } catch {
            dump(error)
            return nil
        }
    }
    
    func importFile(from url: URL, to group: GroupInfo) throws -> URL {
        guard url.pathExtension == "excalidraw" else { throw AppError.fileError(.invalidURL) }
        let desURL = avoidDuplicate(url: group.url.appendingPathComponent(url.lastPathComponent, conformingTo: .fileURL))
        let data = try Data(contentsOf: url, options: .uncached) // .uncached fixes the import bug occurs in x86 mac OS
        guard fileManager.createFile(atPath: desURL.path(percentEncoded: false), contents: data) else {
            throw AppError.fileError(.createError)
        }
        return desURL
    }
    
    func updateFile(_ file: URL, from tempFile: URL) {
        do {
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: tempFile, to: file)
        } catch {
            logger.error("\(error)")
        }
    }
    
    func renameFile(_ url: URL, to name: String) throws {
        let newURL = url.deletingLastPathComponent().appending(path: name).appendingPathExtension(url.pathExtension)
        try FileManager.default.moveItem(at: url, to: newURL)
//        return newURL
    }
    
    func removeFile(at url: URL) throws {
        guard let originName = url.lastPathComponent.split(separator: ".").first else {
            throw FileError.invalidURL
        }
        
        let filename = String(originName)
        let trashURL = avoidDuplicate(url: trashDir.appending(path: filename).appendingPathExtension("excalidraw"))
        try FileManager.default.moveItem(at: url, to: trashURL)
    }
    
    func avoidDuplicate(url: URL) -> URL {
        var result = url
        let name = String(url.lastPathComponent.split(separator: ".").first ?? "Untitled")
        let dir = url.deletingLastPathComponent()
        var i = 1
        while fileManager.fileExists(atPath: result.path(percentEncoded: false)) {
            result = dir.appending(path: "\(name) \(i)").appendingPathExtension("excalidraw")
            i += 1
        }
        return result
    }
}

// MARK: - Version Migration
extension AppFileManager {
    func performMigration() {
        migrateToGroup()
    }
    
    func migrateToGroup() {
        let ok = UnsafeMutablePointer<ObjCBool>.allocate(capacity: 1)
        ok[0] = true
        if !fileManager.fileExists(atPath: defaultGroupURL.path(percentEncoded: false), isDirectory: ok) {
            do {
                try fileManager.createDirectory(at: defaultGroupURL, withIntermediateDirectories: true)
                /// copy all files to default folder
                for itemURL in try fileManager.contentsOfDirectory(at: assetDir, includingPropertiesForKeys: nil) {
                    guard itemURL.pathExtension == "excalidraw" else { continue }
                    try fileManager.moveItem(at: itemURL,
                                             to: defaultGroupURL.appendingPathComponent(itemURL.lastPathComponent,
                                                                                        conformingTo: .fileURL))
                }
            } catch {
                logger.error("\(error)")
            }
        }
        ok.deallocate()
    }
}

