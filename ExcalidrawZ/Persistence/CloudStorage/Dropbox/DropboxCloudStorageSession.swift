//
//  DropboxCloudStorageSession.swift
//  ExcalidrawZ
//

import Foundation

actor DropboxCloudStorageSession: CloudStorageSession {
    nonisolated let providerID = CloudStorageProviderID.dropbox
    nonisolated let account: CloudStorageAccount
    nonisolated let capabilities: CloudStorageProviderCapabilities = [
        .readWrite,
        .deltaChanges,
    ]

    private let client: DropboxAPIClient
    private var pathIndex = DropboxItemPathIndex()
    private var hasTrackedSnapshot = false

    init(
        account: CloudStorageAccount,
        tokenProvider: any DropboxAccessTokenProviding,
        configuration: DropboxConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.account = account
        self.client = DropboxAPIClient(
            accountID: account.id,
            tokenProvider: tokenProvider,
            configuration: configuration,
            urlSession: urlSession
        )
    }

    func rootItem() async throws -> CloudStorageItem {
        CloudStorageItem(
            id: DropboxAPIClient.rootItemID,
            parentID: nil,
            name: "Dropbox",
            kind: .folder,
            contentType: nil,
            size: nil,
            createdAt: nil,
            modifiedAt: nil,
            remoteURL: URL(string: "https://www.dropbox.com/home"),
            revision: nil,
            capabilities: .writableFolder
        )
    }

    func item(for id: CloudStorageItemID) async throws -> CloudStorageItem {
        if id == DropboxAPIClient.rootItemID {
            return try await rootItem()
        }
        let metadata = try await client.metadata(for: id)
        guard let item = metadata.cloudStorageItem(parentID: parentID(for: metadata.pathLower)) else {
            throw CloudStorageError.itemNotFound(id)
        }
        track(metadata, item: item)
        return item
    }

    func remoteURL(for item: CloudStorageItem) async throws -> URL {
        if item.id == DropboxAPIClient.rootItemID {
            return URL(string: "https://www.dropbox.com/home")!
        }
        return try await client.webURL(for: item.id)
    }

    func listChildren(
        of folderID: CloudStorageItemID,
        pageToken: String?
    ) async throws -> CloudStorageItemPage {
        let response: DropboxListFolderResult
        if let pageToken {
            response = try await client.continueListFolder(cursor: pageToken)
        } else {
            response = try await client.listFolder(
                folderID,
                recursive: false,
                includeDeleted: false
            )
        }
        let items = response.entries.compactMap { metadata -> CloudStorageItem? in
            guard let item = metadata.cloudStorageItem(parentID: folderID) else { return nil }
            track(metadata, item: item)
            return item
        }
        return CloudStorageItemPage(
            items: items,
            nextPageToken: response.hasMore ? response.cursor : nil
        )
    }

    func downloadFile(
        _ fileID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> CloudStorageItem {
        let metadata = try await client.downloadFile(fileID, to: localURL)
        guard let item = metadata.cloudStorageItem(parentID: parentID(for: metadata.pathLower)) else {
            throw CloudStorageError.itemNotFound(fileID)
        }
        track(metadata, item: item)
        return item
    }

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        let metadata = try await client.createFile(
            named: name,
            in: parentID,
            contentsAt: localURL,
            condition: condition
        )
        guard let item = metadata.cloudStorageItem(parentID: parentID) else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox file creation did not return file metadata."
            )
        }
        track(metadata, item: item)
        return item
    }

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        let metadata = try await client.updateFile(
            fileID,
            contentsAt: localURL,
            condition: condition
        )
        guard let item = metadata.cloudStorageItem(parentID: parentID(for: metadata.pathLower)) else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox file update did not return file metadata."
            )
        }
        track(metadata, item: item)
        return item
    }

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> CloudStorageItem {
        let metadata = try await client.createFolder(named: name, in: parentID)
        guard let item = metadata.cloudStorageItem(parentID: parentID) else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox folder creation did not return folder metadata."
            )
        }
        track(metadata, item: item)
        return item
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> CloudStorageItem {
        let metadata = try await client.moveItem(itemID, to: parentID, newName: newName)
        let resolvedParentID = parentID ?? self.parentID(for: metadata.pathLower)
        guard let item = metadata.cloudStorageItem(parentID: resolvedParentID) else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox move did not return item metadata."
            )
        }
        track(metadata, item: item)
        return item
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        try await client.deleteItem(itemID, condition: condition)
        removeTrackedItem(itemID)
    }

    func changes(
        in rootItemID: CloudStorageItemID,
        since cursor: CloudStorageChangeCursor?
    ) async throws -> CloudStorageChangePage {
        guard let cursor else {
            return try await establishSnapshot(rootItemID: rootItemID)
        }
        guard pathIndex.rootID == rootItemID, hasTrackedSnapshot else {
            // A Dropbox cursor contains path changes, while deletion entries do
            // not carry item IDs. Rebuild the path index after a process restart.
            throw CloudStorageError.changeTrackingResetRequired
        }

        let response = try await client.continueListFolder(
            cursor: cursor.rawValue,
            operation: .readChanges
        )
        return CloudStorageChangePage(
            changes: applyChanges(response.entries),
            nextCursor: CloudStorageChangeCursor(rawValue: response.cursor),
            hasMore: response.hasMore
        )
    }

    private func establishSnapshot(
        rootItemID: CloudStorageItemID
    ) async throws -> CloudStorageChangePage {
        pathIndex.reset(
            rootID: rootItemID,
            rootPath: try await rootPath(for: rootItemID)
        )

        var response = try await client.listFolder(
            rootItemID,
            recursive: true,
            includeDeleted: true
        )
        var entries = response.entries
        while response.hasMore {
            response = try await client.continueListFolder(
                cursor: response.cursor,
                operation: .readChanges
            )
            entries.append(contentsOf: response.entries)
        }

        let upserts = entries.compactMap { metadata -> (DropboxMetadata, CloudStorageItemID)? in
            guard let itemID = metadata.itemID else { return nil }
            return (metadata, itemID)
        }
        for (metadata, itemID) in upserts {
            if let path = metadata.pathLower {
                pathIndex.track(
                    itemID: itemID,
                    path: path,
                    isFolder: metadata.isFolder
                )
            }
        }

        let items = upserts
            .sorted { pathDepth($0.0.pathLower) < pathDepth($1.0.pathLower) }
            .compactMap { metadata, _ -> CloudStorageItem? in
                guard let item = metadata.cloudStorageItem(
                    parentID: parentID(for: metadata.pathLower)
                ) else { return nil }
                track(metadata, item: item)
                return item
            }
        hasTrackedSnapshot = true

        return CloudStorageChangePage(
            changes: items.map(CloudStorageChange.upsert),
            nextCursor: CloudStorageChangeCursor(rawValue: response.cursor),
            hasMore: false
        )
    }

    private func applyChanges(_ entries: [DropboxMetadata]) -> [CloudStorageChange] {
        var changes: [CloudStorageChange] = []
        let incomingFolderIDsByPath: [String: CloudStorageItemID] = Dictionary(
            uniqueKeysWithValues: entries.compactMap { metadata in
                guard metadata.isFolder,
                      let path = metadata.pathLower,
                      let itemID = metadata.itemID else { return nil }
                return (path, itemID)
            }
        )

        for metadata in entries {
            switch metadata {
                case .deleted:
                    guard let path = metadata.pathLower,
                          let itemID = pathIndex.itemID(for: path) else { continue }
                    changes.append(.deleted(itemID))
                    removeTrackedItem(itemID)
                case .file(_), .folder(_):
                    let parentID = parentID(for: metadata.pathLower)
                        ?? metadata.pathLower
                            .map { DropboxItemPathIndex.parentPath(for: $0) }
                            .flatMap { incomingFolderIDsByPath[$0] }
                    guard let item = metadata.cloudStorageItem(parentID: parentID) else {
                        continue
                    }
                    track(metadata, item: item)
                    changes.append(.upsert(item))
            }
        }
        return changes
    }

    private func rootPath(for rootItemID: CloudStorageItemID) async throws -> String {
        guard rootItemID != DropboxAPIClient.rootItemID else { return "" }
        let metadata = try await client.metadata(for: rootItemID)
        guard case .folder(let folder) = metadata, let path = folder.pathLower else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox did not return a path for the selected root folder."
            )
        }
        return path
    }

    private func parentID(for path: String?) -> CloudStorageItemID? {
        pathIndex.parentID(for: path)
    }

    private func track(_ metadata: DropboxMetadata, item: CloudStorageItem) {
        guard let path = metadata.pathLower else { return }
        pathIndex.track(
            itemID: item.id,
            path: path,
            isFolder: metadata.isFolder
        )
    }

    private func removeTrackedItem(_ itemID: CloudStorageItemID) {
        pathIndex.remove(itemID)
    }

    private func pathDepth(_ path: String?) -> Int {
        path?.split(separator: "/").count ?? 0
    }
}
