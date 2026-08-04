//
//  DropboxItemPathIndex.swift
//  ExcalidrawZ
//

import Foundation

/// Maintains the path-to-ID relationship required by Dropbox deletion events,
/// which contain a path but no stable item ID.
struct DropboxItemPathIndex {
    private(set) var rootID: CloudStorageItemID?
    private var itemIDsByPath: [String: CloudStorageItemID] = [:]
    private var pathsByItemID: [CloudStorageItemID: String] = [:]

    mutating func reset(rootID: CloudStorageItemID, rootPath: String) {
        self.rootID = rootID
        itemIDsByPath = [rootPath: rootID]
        pathsByItemID = [rootID: rootPath]
    }

    func itemID(for path: String) -> CloudStorageItemID? {
        itemIDsByPath[path]
    }

    func parentID(for path: String?) -> CloudStorageItemID? {
        guard let path else { return nil }
        return itemIDsByPath[Self.parentPath(for: path)]
    }

    static func parentPath(for path: String) -> String {
        let value = (path as NSString).deletingLastPathComponent
        return value == "/" ? "" : value
    }

    mutating func track(
        itemID: CloudStorageItemID,
        path: String,
        isFolder: Bool
    ) {
        if let previousPath = pathsByItemID[itemID], previousPath != path {
            itemIDsByPath.removeValue(forKey: previousPath)
            if isFolder {
                remapDescendants(from: previousPath, to: path, excluding: itemID)
            }
        }
        itemIDsByPath[path] = itemID
        pathsByItemID[itemID] = path
    }

    mutating func remove(_ itemID: CloudStorageItemID) {
        guard let path = pathsByItemID[itemID] else { return }
        let descendantPrefix = path + "/"
        let removedIDs = pathsByItemID.compactMap { candidateID, candidatePath in
            candidatePath == path || candidatePath.hasPrefix(descendantPrefix)
                ? candidateID
                : nil
        }
        for removedID in removedIDs {
            if let removedPath = pathsByItemID.removeValue(forKey: removedID) {
                itemIDsByPath.removeValue(forKey: removedPath)
            }
        }
    }

    private mutating func remapDescendants(
        from previousPath: String,
        to path: String,
        excluding itemID: CloudStorageItemID
    ) {
        let previousPrefix = previousPath + "/"
        var descendants: [(CloudStorageItemID, String)] = []
        for (candidateID, candidatePath) in pathsByItemID {
            guard candidateID != itemID,
                  candidatePath.hasPrefix(previousPrefix) else { continue }
            descendants.append((candidateID, candidatePath))
        }

        for (descendantID, previousDescendantPath) in descendants {
            itemIDsByPath.removeValue(forKey: previousDescendantPath)
            let suffix = previousDescendantPath.dropFirst(previousPath.count)
            let newPath = path + suffix
            pathsByItemID[descendantID] = newPath
            itemIDsByPath[newPath] = descendantID
        }
    }
}
