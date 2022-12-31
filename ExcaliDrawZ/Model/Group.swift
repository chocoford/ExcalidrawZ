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
    
    init(url: URL) {
        self.url = url
    }
}
