//
//  File.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/30.
//

import Foundation

struct FileInfo: Identifiable, Hashable {
    var url: URL
    
    var name: String?
    var fileExtension: String?
    var createdAt: Date?
    var updatedAt: Date?
    var size: String?
    
    var id: String {
        url.path(percentEncoded: false)
    }
  
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    init(url: URL, name: String? = nil, fileExtension: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil, size: String? = nil) {
        self.url = url
        self.name = name
        self.fileExtension = fileExtension
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.size = size
    }
    
    init(from url: URL) {
        self.url = url
        if let name = url.lastPathComponent.split(separator: ".").first {
            self.name = String(name)
        }
        
        self.fileExtension = url.pathExtension
        
        let path = url.path(percentEncoded: false)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            
            // MARK: Created At
            if let createdAt = attributes[FileAttributeKey.creationDate] as? Date {
                self.createdAt = createdAt
            }
            
            // MARK: Updated At
            if let updatedAt = attributes[FileAttributeKey.modificationDate] as? Date {
                self.updatedAt = updatedAt
            }
            
            // MARK: Size
            if let size = attributes[FileAttributeKey.size] as? Double {
                let fileKB = size / 1024
                if fileKB > 1024 {
                    let fileMB: Double = fileKB / 1024
                    self.size = String(format: "%.1fMB", fileMB)
                } else {
                    self.size = String(format: "%.1fKB", fileKB)
                }
            }
        } catch {
            dump(error)
        }
    }

}

#if DEBUG
extension FileInfo {
    static let preview: FileInfo = .init(from: Bundle.main.url(forResource: "template", withExtension: "excalidraw")!)
}
#endif
