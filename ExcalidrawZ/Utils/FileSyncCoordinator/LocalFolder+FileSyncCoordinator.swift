//
//  LocalFolder+FileSyncCoordinator.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/23/25.
//

import Foundation
import CoreData

extension LocalFolder {
    var isInICloudDrive: Bool {
        var currentURL: URL? = url

        while let u = currentURL {
            do {
                let values = try u.resourceValues(forKeys: [.isUbiquitousItemKey])
                if values.isUbiquitousItem == true {
                    return true
                }
            } catch {
                // ignore
            }

            let parent = u.deletingLastPathComponent()
            if parent == u { break }
            currentURL = parent
        }

        return false
    }
}
