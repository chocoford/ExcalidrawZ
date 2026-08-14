//
//  URL+Extension.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import Foundation

extension URL {
    var isDirectory: Bool {
       (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    func rebased(from oldRootURL: URL, to newRootURL: URL) -> URL? {
        let sourcePath = standardizedFileURL.path
        let oldRootPath = oldRootURL.standardizedFileURL.path
        guard sourcePath == oldRootPath || sourcePath.hasPrefix(oldRootPath + "/") else {
            return nil
        }

        let relativePath = String(sourcePath.dropFirst(oldRootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { return newRootURL.standardizedFileURL }
        return newRootURL.standardizedFileURL.appendingPathComponent(relativePath)
    }
}
