//
//  URL+Extension.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import Foundation

extension URL {
    var isDirectory: Bool {
       (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
