//
//  OneDriveGraphClient.swift
//  ExcalidrawZ
//

import Foundation
import Logging

actor OneDriveGraphClient {
    private static let graphHost = "graph.microsoft.com"

    private let logger = Logger(label: "OneDriveGraphClient")
    private let accountID: CloudStorageAccountID
    private let tokenProvider: any OneDriveAccessTokenProviding
    private let urlSession: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder.oneDriveGraphDecoder()

    init(
        accountID: CloudStorageAccountID,
        tokenProvider: any OneDriveAccessTokenProviding,
        urlSession: URLSession = .shared,
        baseURL: URL = URL(string: "https://graph.microsoft.com/v1.0")!
    ) {
        self.accountID = accountID
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
        self.baseURL = baseURL
    }

    func rootItem() async throws -> OneDriveDriveItem {
        try await getItem(at: baseURL.appending(path: "me/drive/root"))
    }

    func item(withID itemID: CloudStorageItemID) async throws -> OneDriveDriveItem {
        try await getItem(
            at: itemURL(itemID),
            itemID: itemID
        )
    }

    func children(
        of folderID: CloudStorageItemID,
        pageLink: String?
    ) async throws -> OneDriveGraphCollection<OneDriveDriveItem> {
        let url: URL
        if let pageLink {
            url = try validatedContinuationURL(pageLink)
        } else {
            url = itemURL(folderID).appending(path: "children")
        }
        return try await get(url, itemID: folderID)
    }

    func downloadFile(
        _ itemID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> OneDriveDriveItem {
        let metadata = try await item(withID: itemID)
        var request = try await authorizedRequest(
            url: itemURL(itemID).appending(path: "content"),
            method: "GET"
        )
        if let revision = metadata.eTag {
            request.setValue(revision, forHTTPHeaderField: "If-Match")
        }
        let (temporaryURL, response) = try await urlSession.download(for: request)
        try validate(response: response, data: nil, itemID: itemID)

        try installDownloadedFile(from: temporaryURL, at: localURL)
        return metadata
    }

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> OneDriveDriveItem {
        let parentComponent = encodedPathComponent(parentID.rawValue)
        let nameComponent = encodedPathComponent(name)
        guard let url = URL(
            string: "\(baseURL.absoluteString)/me/drive/items/\(parentComponent):/\(nameComponent):/content"
        ) else {
            throw CloudStorageError.invalidProviderResponse("Unable to construct upload URL.")
        }
        return try await uploadFile(
            at: localURL,
            to: url,
            condition: condition,
            itemID: nil
        )
    }

    func updateFile(
        _ itemID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> OneDriveDriveItem {
        try await uploadFile(
            at: localURL,
            to: itemURL(itemID).appending(path: "content"),
            condition: condition,
            itemID: itemID
        )
    }

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> OneDriveDriveItem {
        let body: [String: Any] = [
            "name": name,
            "folder": [:],
            "@microsoft.graph.conflictBehavior": "fail",
        ]
        return try await sendJSON(
            url: itemURL(parentID).appending(path: "children"),
            method: "POST",
            body: body,
            itemID: parentID
        )
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> OneDriveDriveItem {
        var body: [String: Any] = [:]
        if let parentID {
            body["parentReference"] = ["id": parentID.rawValue]
        }
        if let newName {
            body["name"] = newName
        }
        return try await sendJSON(
            url: itemURL(itemID),
            method: "PATCH",
            body: body,
            itemID: itemID
        )
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        var request = try await authorizedRequest(url: itemURL(itemID), method: "DELETE")
        apply(condition, to: &request)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, itemID: itemID)
    }

    func changes(
        in rootItemID: CloudStorageItemID,
        continuationLink: String?
    ) async throws -> OneDriveGraphCollection<OneDriveDriveItem> {
        let url: URL
        if let continuationLink {
            url = try validatedContinuationURL(continuationLink)
        } else {
            url = itemURL(rootItemID).appending(path: "delta")
        }
        return try await get(url)
    }

    private func getItem(
        at url: URL,
        itemID: CloudStorageItemID? = nil
    ) async throws -> OneDriveDriveItem {
        try await get(url, itemID: itemID)
    }

    private func get<Value: Decodable>(
        _ url: URL,
        itemID: CloudStorageItemID? = nil
    ) async throws -> Value {
        let request = try await authorizedRequest(url: url, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, itemID: itemID)
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(error.localizedDescription)
        }
    }

    private func uploadFile(
        at localURL: URL,
        to remoteURL: URL,
        condition: CloudStorageWriteCondition,
        itemID: CloudStorageItemID?
    ) async throws -> OneDriveDriveItem {
        var request = try await authorizedRequest(url: remoteURL, method: "PUT")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        apply(condition, to: &request)
        let (data, response) = try await urlSession.upload(for: request, fromFile: localURL)
        try validate(response: response, data: data, itemID: itemID)
        do {
            return try decoder.decode(OneDriveDriveItem.self, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(error.localizedDescription)
        }
    }

    private func sendJSON<Value: Decodable>(
        url: URL,
        method: String,
        body: [String: Any],
        itemID: CloudStorageItemID?
    ) async throws -> Value {
        var request = try await authorizedRequest(url: url, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, itemID: itemID)
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(error.localizedDescription)
        }
    }

    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "Bearer \(try await tokenProvider.accessToken(for: accountID))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(
        response: URLResponse,
        data: Data?,
        itemID: CloudStorageItemID?
    ) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidProviderResponse("Missing HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let graphError = data.flatMap {
                try? decoder.decode(OneDriveGraphErrorEnvelope.self, from: $0)
            }?.error
            logger.error(
                "Microsoft Graph request failed status=\(response.statusCode) itemID=\(itemID?.rawValue ?? "none") code=\(graphError?.code ?? "unknown") message=\(graphError?.message ?? "none")"
            )
            let changeTrackingResetCodes: Set<String> = [
                "resyncrequired",
                "resyncchangesapplydifferences",
                "resyncchangesuploaddifferences",
                "syncstatenotfound",
            ]
            if response.statusCode == 410
                || changeTrackingResetCodes.contains(graphError?.code.lowercased() ?? "") {
                throw CloudStorageError.changeTrackingResetRequired
            }
            switch response.statusCode {
                case 401:
                    throw CloudStorageError.authenticationRequired
                case 404:
                    if let itemID {
                        throw CloudStorageError.itemNotFound(itemID)
                    }
                case 409 where graphError?.code == "nameAlreadyExists":
                    throw CloudStorageError.itemNameAlreadyExists(nil)
                case 409, 412:
                    throw CloudStorageError.conflict
                case 429:
                    let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(TimeInterval.init)
                    throw CloudStorageError.rateLimited(retryAfter: retryAfter)
                default:
                    break
            }

            if let graphError {
                throw CloudStorageError.transport(
                    "\(graphError.code): \(graphError.message)"
                )
            }
            throw CloudStorageError.transport("Microsoft Graph returned HTTP \(response.statusCode).")
        }
    }

    private func apply(_ condition: CloudStorageWriteCondition, to request: inout URLRequest) {
        switch condition {
            case .unconditional:
                break
            case .ifAbsent:
                request.setValue("*", forHTTPHeaderField: "If-None-Match")
            case .ifUnmodified(let revision):
                request.setValue(revision, forHTTPHeaderField: "If-Match")
        }
    }

    private func installDownloadedFile(from temporaryURL: URL, at localURL: URL) throws {
        let fileManager = FileManager.default
        let directoryURL = localURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let stagingURL = directoryURL.appending(
            path: ".\(localURL.lastPathComponent).\(UUID().uuidString).download"
        )
        try fileManager.moveItem(at: temporaryURL, to: stagingURL)
        do {
            if fileManager.fileExists(atPath: localURL.path) {
                _ = try fileManager.replaceItemAt(localURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: localURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func itemURL(_ itemID: CloudStorageItemID) -> URL {
        baseURL
            .appending(path: "me/drive/items")
            .appending(path: itemID.rawValue)
    }

    private func validatedContinuationURL(_ value: String) throws -> URL {
        guard let url = URL(string: value),
              url.scheme == "https",
              url.host?.lowercased() == Self.graphHost else {
            throw CloudStorageError.invalidProviderResponse("Invalid Microsoft Graph continuation URL.")
        }
        return url
    }

    private func encodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":/?#%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
