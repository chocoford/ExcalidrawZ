//
//  AppFileManager.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import Foundation

struct AppFileManager {
    static let shared = AppFileManager()
    
    let fileManager = FileManager.default
    let rootDir = try! FileManager.default
        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        .appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
    
    var assetDir: URL {
        rootDir.appendingPathComponent("assets", conformingTo: .directory)
    }
        
    
    init() {
        print(assetDir)
        // create asset dir if needed.
        do {
            try fileManager.createDirectory(at: assetDir, withIntermediateDirectories: true)
        } catch {
            dump(error)
        }
    }
}

extension AppFileManager {
    struct FileInfo: Identifiable {
        var url: URL
        
        var name: String?
        var createdAt: Date?
        var updatedAt: Date?
        var size: String?
        
        var id: String {
            url.path()
        }
    }
    
    var assetFiles: [FileInfo] {
        do {
            return try fileManager.contentsOfDirectory(at: assetDir, includingPropertiesForKeys: nil)
                .compactMap { generateFileInfo(url: $0) }
        } catch {
            return []
        }
    }
}

private extension AppFileManager {

    func generateFileInfo(url: URL) -> FileInfo? {
        var result = FileInfo(url: url, name: url.lastPathComponent)
        
        guard url.pathExtension == "excalidraw" else { return nil }
        
        let path = url.path(percentEncoded: false)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            
            // MARK: Created At
            if let createdAt = attributes[FileAttributeKey.creationDate] as? Date {
                result.createdAt = createdAt
            }
            
            // MARK: Updated At
            if let updatedAt = attributes[FileAttributeKey.modificationDate] as? Date {
                result.updatedAt = updatedAt
            }
            
            // MARK: Size
            if let size = attributes[FileAttributeKey.size] as? Double {
                let fileKB = size / 1024
                if fileKB > 1024 {
                    let fileMB: Double = fileKB / 1024
                    result.size = String(format: "%.1fMB", fileMB)
                } else {
                    result.size = String(format: "%.1fKB", fileKB)
                }
            }
        } catch {
            dump(error)
        }
        return result
            
    }
}
