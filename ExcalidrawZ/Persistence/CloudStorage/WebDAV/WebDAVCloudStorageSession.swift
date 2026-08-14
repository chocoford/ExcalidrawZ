//
//  WebDAVCloudStorageSession.swift
//  ExcalidrawZ
//

import Foundation

actor WebDAVCloudStorageSession: CloudStorageSession {
    nonisolated let providerID = CloudStorageProviderID.webDAV
    nonisolated let account: CloudStorageAccount
    nonisolated let capabilities: CloudStorageProviderCapabilities = .readWrite

    private let rootURL: URL
    private let client: WebDAVClient

    init(
        account: CloudStorageAccount,
        credential: WebDAVCredential,
        urlSession: URLSession = .shared
    ) {
        self.account = account
        self.rootURL = credential.serverURL
        self.client = WebDAVClient(
            credential: credential,
            urlSession: urlSession
        )
    }

    func rootItem() async throws -> CloudStorageItem {
        try await client.item(at: rootURL).cloudStorageItem(rootURL: rootURL)
    }

    func item(for id: CloudStorageItemID) async throws -> CloudStorageItem {
        let url = try WebDAVURL.itemURL(for: id)
        return try await client.item(at: url).cloudStorageItem(rootURL: rootURL)
    }

    func remoteURL(for item: CloudStorageItem) async throws -> URL {
        try WebDAVURL.itemURL(for: item.id)
    }

    func listChildren(
        of folderID: CloudStorageItemID,
        pageToken: String?
    ) async throws -> CloudStorageItemPage {
        guard pageToken == nil else {
            return CloudStorageItemPage(items: [], nextPageToken: nil)
        }
        let folderURL = try WebDAVURL.itemURL(for: folderID)
        let resources = try await client.children(of: folderURL)
        return CloudStorageItemPage(
            items: resources.map { $0.cloudStorageItem(rootURL: rootURL) },
            nextPageToken: nil
        )
    }

    func downloadFile(
        _ fileID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> CloudStorageItem {
        let url = try WebDAVURL.itemURL(for: fileID)
        try await client.download(url, to: localURL)
        return try await client.item(at: url).cloudStorageItem(rootURL: rootURL)
    }

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        let parentURL = try WebDAVURL.itemURL(for: parentID)
        return try await client.createFile(
            named: name,
            in: parentURL,
            contentsAt: localURL,
            condition: condition
        ).cloudStorageItem(rootURL: rootURL)
    }

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        let url = try WebDAVURL.itemURL(for: fileID)
        return try await client.updateFile(
            url,
            contentsAt: localURL,
            condition: condition
        ).cloudStorageItem(rootURL: rootURL)
    }

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> CloudStorageItem {
        let parentURL = try WebDAVURL.itemURL(for: parentID)
        return try await client.createFolder(
            named: name,
            in: parentURL
        ).cloudStorageItem(rootURL: rootURL)
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> CloudStorageItem {
        let sourceURL = try WebDAVURL.itemURL(for: itemID)
        let existingItem = try await client.item(at: sourceURL)
        let parentURL: URL?
        if let parentID {
            parentURL = try WebDAVURL.itemURL(for: parentID)
        } else {
            parentURL = nil
        }
        return try await client.moveItem(
            at: sourceURL,
            to: parentURL,
            newName: newName,
            isCollection: existingItem.isCollection
        ).cloudStorageItem(rootURL: rootURL)
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        try await client.delete(
            WebDAVURL.itemURL(for: itemID),
            condition: condition
        )
    }
}
