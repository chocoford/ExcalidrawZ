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
    case cloudStorageFile(String)

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
                self = .cloudStorageFile(reference.id)
        }
    }
}

enum SidebarGroupScrollTarget: Hashable {
    case group(NSManagedObjectID)
    case localFolder(NSManagedObjectID)
    case cloudStorageFolder(locationID: UUID, itemID: CloudStorageItemID)
    case temporary
    case collaboration
}

extension URL {
    var sidebarLocalFileScrollTarget: SidebarActiveFileScrollTarget { .localFile(self) }
}

extension Group {
    var sidebarGroupScrollTarget: SidebarGroupScrollTarget { .group(objectID) }
}

extension LocalFolder {
    /// Match the lazy collection's identity to its navigation target so locating
    /// an offscreen folder doesn't require building every preceding row.
    var sidebarGroupScrollTarget: SidebarGroupScrollTarget {
        .localFolder(objectID)
    }
}
