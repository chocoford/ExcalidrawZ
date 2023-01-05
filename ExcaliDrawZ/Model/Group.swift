//
//  Group.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/30.
//

import Foundation

struct GroupInfo: Identifiable, Hashable {
    var id: Int {
        url.hashValue
    }
    
    var url: URL
    var name: String {
        url.lastPathComponent
    }
    var createdAt: Date
    
    init(url: URL) {
        self.url = url
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        
        // MARK: Created At
        self.createdAt = attributes?[FileAttributeKey.creationDate] as? Date ?? .distantPast
            

    }
}
