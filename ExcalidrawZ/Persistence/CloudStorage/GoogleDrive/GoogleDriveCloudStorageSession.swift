//
//  GoogleDriveCloudStorageSession.swift
//  ExcalidrawZ
//

import Foundation

actor GoogleDriveCloudStorageSession: CloudStorageSession {
    nonisolated let providerID = CloudStorageProviderID.googleDrive
    nonisolated let account: CloudStorageAccount
    nonisolated let capabilities: CloudStorageProviderCapabilities = [
        .createFile,
        .updateFile,
        .moveItem,
        .deleteItem,
    ]

    private let client: GoogleDriveAPIClient
    init(
        account: CloudStorageAccount,
        tokenProvider: any GoogleDriveAccessTokenProviding,
        configuration: GoogleDriveConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.account = account
        self.client = GoogleDriveAPIClient(
            accountID: account.id,
            tokenProvider: tokenProvider,
            configuration: configuration,
            urlSession: urlSession
        )
    }

    func rootItem() async throws -> CloudStorageItem {
        try await client.item(CloudStorageItemID(rawValue: "root")).cloudStorageItem
    }

    func item(for id: CloudStorageItemID) async throws -> CloudStorageItem {
        try await client.item(id).cloudStorageItem
    }

    func remoteURL(for item: CloudStorageItem) async throws -> URL {
        if let remoteURL = item.remoteURL { return remoteURL }
        guard var components = URLComponents(string: "https://drive.google.com/open") else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct Google Drive web URL."
            )
        }
        components.queryItems = [URLQueryItem(name: "id", value: item.id.rawValue)]
        guard let remoteURL = components.url else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct Google Drive web URL."
            )
        }
        return remoteURL
    }

    func listChildren(
        of folderID: CloudStorageItemID,
        pageToken: String?
    ) async throws -> CloudStorageItemPage {
        let response = try await client.children(of: folderID, pageToken: pageToken)
        return CloudStorageItemPage(
            items: response.files.map(\.cloudStorageItem),
            nextPageToken: response.nextPageToken
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
        try await client.createFile(
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
        try await client.updateFile(
            fileID,
            contentsAt: localURL,
            condition: condition
        ).cloudStorageItem
    }

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> CloudStorageItem {
        try await client.createFolder(named: name, in: parentID).cloudStorageItem
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> CloudStorageItem {
        try await client.moveItem(itemID, to: parentID, newName: newName).cloudStorageItem
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        try await client.deleteItem(itemID, condition: condition)
    }
}
