//
//  BoxCloudStorageSession.swift
//  ExcalidrawZ
//

import Foundation

actor BoxCloudStorageSession: CloudStorageSession {
    nonisolated let providerID = CloudStorageProviderID.box
    nonisolated let account: CloudStorageAccount
    nonisolated let capabilities: CloudStorageProviderCapabilities = [
        .readWrite,
        .deltaChanges,
    ]

    private let client: BoxAPIClient
    private var trackedRootID: CloudStorageItemID?
    private var trackedItems: [CloudStorageItemID: CloudStorageItem] = [:]
    private var hasTrackedSnapshot = false

    init(
        account: CloudStorageAccount,
        tokenProvider: any BoxAccessTokenProviding,
        configuration: BoxConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.account = account
        self.client = BoxAPIClient(
            accountID: account.id,
            tokenProvider: tokenProvider,
            configuration: configuration,
            urlSession: urlSession
        )
    }

    func rootItem() async throws -> CloudStorageItem {
        try await client.rootItem().cloudStorageItem
    }

    func item(for id: CloudStorageItemID) async throws -> CloudStorageItem {
        try await client.item(BoxItemIdentity(id)).cloudStorageItem
    }

    func remoteURL(for item: CloudStorageItem) async throws -> URL {
        let identity = try BoxItemIdentity(item.id)
        let path: String
        switch identity {
            case .file(let id): path = "file/\(id)"
            case .folder(let id): path = "folder/\(id)"
            case .webLink:
                if let remoteURL = item.remoteURL { return remoteURL }
                throw CloudStorageError.unsupportedOperation(.browse)
        }
        guard let remoteURL = URL(string: "https://app.box.com/\(path)") else {
            throw CloudStorageError.invalidProviderResponse("Unable to construct Box web URL.")
        }
        return remoteURL
    }

    func listChildren(
        of folderID: CloudStorageItemID,
        pageToken: String?
    ) async throws -> CloudStorageItemPage {
        let response = try await client.children(of: folderID, marker: pageToken)
        return CloudStorageItemPage(
            items: response.entries.map(\.cloudStorageItem),
            nextPageToken: response.nextMarker
        )
    }

    func downloadFile(
        _ fileID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> CloudStorageItem {
        try await client.downloadFile(fileID, to: localURL).cloudStorageItem
    }

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        let item = try await client.createFile(
            named: name,
            in: parentID,
            contentsAt: localURL,
            condition: condition
        ).cloudStorageItem
        track(item)
        return item
    }

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        let item = try await client.updateFile(
            fileID,
            contentsAt: localURL,
            condition: condition
        ).cloudStorageItem
        track(item)
        return item
    }

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> CloudStorageItem {
        let item = try await client.createFolder(named: name, in: parentID).cloudStorageItem
        track(item)
        return item
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> CloudStorageItem {
        let item = try await client.moveItem(itemID, to: parentID, newName: newName)
            .cloudStorageItem
        track(item)
        return item
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        try await client.deleteItem(itemID, condition: condition)
        trackedItems.removeValue(forKey: itemID)
    }

    func changes(
        in rootItemID: CloudStorageItemID,
        since cursor: CloudStorageChangeCursor?
    ) async throws -> CloudStorageChangePage {
        if cursor == nil {
            let currentItems = try await snapshot(of: rootItemID)
            let events = try await client.events(since: "now")
            trackedRootID = rootItemID
            trackedItems = currentItems
            hasTrackedSnapshot = true
            return CloudStorageChangePage(
                changes: currentItems.values.map(CloudStorageChange.upsert),
                nextCursor: CloudStorageChangeCursor(rawValue: events.nextStreamPosition),
                hasMore: false
            )
        }

        guard trackedRootID == rootItemID, hasTrackedSnapshot else {
            // Box change positions are account-wide and do not encode enough
            // ancestry to reconstruct a selected subtree after app relaunch.
            throw CloudStorageError.changeTrackingResetRequired
        }

        let events = try await client.events(since: cursor!.rawValue)
        guard !events.entries.isEmpty else {
            return CloudStorageChangePage(
                changes: [],
                nextCursor: CloudStorageChangeCursor(rawValue: events.nextStreamPosition),
                hasMore: false
            )
        }

        let currentItems = try await snapshot(of: rootItemID)
        var changes = currentItems.compactMap { id, item -> CloudStorageChange? in
            trackedItems[id] == item ? nil : .upsert(item)
        }
        changes.append(contentsOf: trackedItems.keys
            .filter { currentItems[$0] == nil }
            .map(CloudStorageChange.deleted))
        trackedItems = currentItems

        return CloudStorageChangePage(
            changes: changes,
            nextCursor: CloudStorageChangeCursor(rawValue: events.nextStreamPosition),
            hasMore: false
        )
    }

    private func snapshot(
        of rootItemID: CloudStorageItemID
    ) async throws -> [CloudStorageItemID: CloudStorageItem] {
        var items: [CloudStorageItemID: CloudStorageItem] = [:]
        var pendingFolders = [rootItemID]

        while let folderID = pendingFolders.popLast() {
            var pageToken: String?
            repeat {
                let page = try await listChildren(of: folderID, pageToken: pageToken)
                for item in page.items {
                    items[item.id] = item
                    if item.kind == .folder {
                        pendingFolders.append(item.id)
                    }
                }
                pageToken = page.nextPageToken
            } while pageToken != nil
        }
        return items
    }

    private func track(_ item: CloudStorageItem) {
        guard trackedRootID != nil else { return }
        trackedItems[item.id] = item
    }
}
