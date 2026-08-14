//
//  OneDriveCloudStorageSession.swift
//  ExcalidrawZ
//

import Foundation

actor OneDriveCloudStorageSession: CloudStorageSession {
    nonisolated let providerID = CloudStorageProviderID.microsoftOneDrive
    nonisolated let account: CloudStorageAccount
    nonisolated let capabilities: CloudStorageProviderCapabilities = [
        .readWrite,
        .deltaChanges,
    ]

    private let graphClient: OneDriveGraphClient

    init(
        account: CloudStorageAccount,
        tokenProvider: any OneDriveAccessTokenProviding,
        urlSession: URLSession = .shared
    ) {
        self.account = account
        self.graphClient = OneDriveGraphClient(
            accountID: account.id,
            tokenProvider: tokenProvider,
            urlSession: urlSession
        )
    }

    func rootItem() async throws -> CloudStorageItem {
        try await graphClient.rootItem().cloudStorageItem
    }

    func item(for id: CloudStorageItemID) async throws -> CloudStorageItem {
        try await graphClient.item(withID: id).cloudStorageItem
    }

    func listChildren(
        of folderID: CloudStorageItemID,
        pageToken: String?
    ) async throws -> CloudStorageItemPage {
        let response = try await graphClient.children(of: folderID, pageLink: pageToken)
        return CloudStorageItemPage(
            items: response.value.map(\.cloudStorageItem),
            nextPageToken: response.nextLink
        )
    }

    func downloadFile(
        _ fileID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> CloudStorageItem {
        try await graphClient.downloadFile(fileID, to: localURL).cloudStorageItem
    }

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        try await graphClient.createFile(
            named: name,
            in: parentID,
            contentsAt: localURL,
            condition: condition
        ).cloudStorageItem
    }

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        try await graphClient.updateFile(
            fileID,
            contentsAt: localURL,
            condition: condition
        ).cloudStorageItem
    }

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> CloudStorageItem {
        try await graphClient.createFolder(named: name, in: parentID).cloudStorageItem
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> CloudStorageItem {
        try await graphClient.moveItem(
            itemID,
            to: parentID,
            newName: newName
        ).cloudStorageItem
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        try await graphClient.deleteItem(itemID, condition: condition)
    }

    func changes(
        in rootItemID: CloudStorageItemID,
        since cursor: CloudStorageChangeCursor?
    ) async throws -> CloudStorageChangePage {
        let response = try await graphClient.changes(
            in: rootItemID,
            continuationLink: cursor?.rawValue
        )
        guard let continuation = response.nextLink ?? response.deltaLink else {
            throw CloudStorageError.invalidProviderResponse(
                "Microsoft Graph delta response did not include a continuation link."
            )
        }
        return CloudStorageChangePage(
            changes: response.value.map { item in
                if item.deleted != nil {
                    return .deleted(CloudStorageItemID(rawValue: item.id))
                }
                return .upsert(item.cloudStorageItem)
            },
            nextCursor: CloudStorageChangeCursor(rawValue: continuation),
            hasMore: response.nextLink != nil
        )
    }
}
