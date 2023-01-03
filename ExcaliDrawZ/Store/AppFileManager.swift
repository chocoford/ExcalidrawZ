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
    
    lazy var defaultGroup: GroupInfo = .init(url: defaultGroupURL)
    
    @Published private(set) var assetFiles: [FileInfo] = []
    @Published private(set) var assetGroups: [GroupInfo] = [] {
        didSet {
            loadFiles()
        }
    }

    lazy var monitor: DirMonitor = DirMonitor(dir: assetDir, queue: .init(label: "com.chocoford.ExcaliDrawZ-DirMonitor"))
    
    var monitorCancellable: AnyCancellable? = nil
    
    init() {
        performMigration()
        
        createDir()
        backupFiles()
        configureMonitor()
    }
    
    func backupFiles() {
        logger.info("backup files...")
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
    
    func createDir() {
        try? fileManager.createDirectory(at: assetDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: trashDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
    }
    
    func configureMonitor() {
        if !monitor.start() {
            fatalError("Dir monitor starts failed.")
        }
        monitorCancellable = monitor.dirWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.loadFiles()
            }
    }
}

extension AppFileManager {
    func loadAssets() -> [FileInfo] {
        do {
            return try fileManager
                .contentsOfDirectory(at: defaultGroupURL, includingPropertiesForKeys: nil)
                .compactMap { FileInfo(from: $0) }
                .filter { $0.fileExtension == "excalidraw" }
                .sorted { $0.updatedAt ?? .distantPast > $1.updatedAt ?? .distantPast}
        } catch {
            return []
        }
    }
    
    func loadFiles() {
        do {
            assetFiles = try fileManager
                .contentsOfDirectory(at: defaultGroupURL,
                                     includingPropertiesForKeys: nil)
                .map { FileInfo(from: $0) }
                .filter { $0.fileExtension == "excalidraw" }
//                .sorted(by: {
//                    $0.name?.hashValue ?? 0 < $1.name?.hashValue ?? 0
//                })
                .sorted { $0.updatedAt ?? .distantPast > $1.updatedAt ?? .distantPast}
        } catch {
            assetFiles = []
        }
    }
    
//    func shuffleFiles() {
//        withAnimation {
//            assetFiles.shuffle()
//        }
//    }
    
    func generateNewFileName() -> URL {
        var name = defaultGroupURL.appending(path: "Untitled").appendingPathExtension("excalidraw")
        var i = 1
        while fileManager.fileExists(atPath: name.path(percentEncoded: false)) {
            name = defaultGroupURL.appending(path: "Untitled \(i)").appendingPathExtension("excalidraw")
            i += 1
        }
        return name
    }
    
    @MainActor
    func createNewFile() -> URL? {
        guard let template = Bundle.main.url(forResource: "template", withExtension: "excalidraw") else { return nil }
        let desURL = generateNewFileName()
        do {
            let data = try Data(contentsOf: template)
            fileManager.createFile(atPath: desURL.path(percentEncoded: false), contents: data)
            self.assetFiles.insert(FileInfo(from: desURL), at: 0)
            logger.info("create new file done. \(desURL.lastPathComponent)")
            return desURL
        } catch {
            dump(error)
            return nil
        }
    }
    
    @MainActor
    func importFile(from url: URL) throws -> URL {
        guard url.pathExtension == "excalidraw" else { throw AppError.importError(.invalidURL) }
        let desURL = avoidDuplicate(url: defaultGroupURL.appendingPathComponent(url.lastPathComponent, conformingTo: .fileURL))
        let data = try Data(contentsOf: url)
        guard fileManager.createFile(atPath: desURL.path(percentEncoded: false), contents: data) else {
            throw AppError.importError(.createError)
        }
        self.assetFiles.insert(FileInfo(from: desURL), at: 0)
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
    
    func renameFile(_ url: URL, to name: String) throws -> URL {
        guard let index = self.assetFiles.firstIndex(where: {
            $0.url == url
        }) else {
            throw RenameError.notFound
        }
        let newURL = url.deletingLastPathComponent().appending(path: name).appendingPathExtension(url.pathExtension)
        try FileManager.default.moveItem(at: url, to: newURL)
        self.assetFiles[index].url = newURL
        self.assetFiles[index].name = name
        return newURL
    }
    
    func removeFile(at url: URL) throws {
        guard let index = assetFiles.firstIndex(where: {
            $0.url == url
        }) else {
            throw DeleteError.notFound
        }
        guard let originName = url.lastPathComponent.split(separator: ".").first else {
            throw DeleteError.nameError
        }
        
        let filename = String(originName)
        
        var name = trashDir.appending(path: filename).appendingPathExtension("excalidraw")
        var i = 1
        while fileManager.fileExists(atPath: name.path(percentEncoded: false)) {
            name = trashDir.appending(path: "\(filename) (\(i))").appendingPathExtension("excalidraw")
            i += 1
        }
        try FileManager.default.moveItem(at: url, to: name)
        self.assetFiles.remove(at: index)
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

