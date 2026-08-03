//
//  SidebarActiveFileScrollTarget.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/6/29.
//

import CoreData
import Foundation

enum SidebarActiveFileScrollTarget: Hashable {
    case file(NSManagedObjectID)
    case localFile(URL)
    case temporaryFile(URL)
    case collaborationFile(NSManagedObjectID)
    case cloudStorageFile(CloudStorageItemID)

    init?(activeFile: FileState.ActiveFile?) {
        guard let activeFile else { return nil }

        switch activeFile {
            case .file(let file):
                self = .file(file.objectID)
            case .localFile(let url):
                self = .localFile(url)
            case .temporaryFile(let url):
                self = .temporaryFile(url)
            case .collaborationFile(let file):
                self = .collaborationFile(file.objectID)
            case .cloudStorageFile(let reference):
                self = .cloudStorageFile(reference.itemID)
        }
    }
}

enum SidebarGroupScrollTarget: Hashable {
    case group(NSManagedObjectID)
    case localFolder(NSManagedObjectID)
}
