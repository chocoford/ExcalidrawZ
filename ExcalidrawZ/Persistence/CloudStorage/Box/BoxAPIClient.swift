//
//  BoxAPIClient.swift
//  ExcalidrawZ
//

import Foundation
import Logging

actor BoxAPIClient {
    private static let itemFields = [
        "type", "id", "name", "size", "created_at", "modified_at", "etag",
        "parent", "permissions", "shared_link",
    ].joined(separator: ",")

    private let logger = Logger(label: "BoxAPIClient")
    private let accountID: CloudStorageAccountID
    private let tokenProvider: any BoxAccessTokenProviding
    private let urlSession: URLSession
    private let configuration: BoxConfiguration
    private let decoder = JSONDecoder.boxDecoder()

    init(
        accountID: CloudStorageAccountID,
        tokenProvider: any BoxAccessTokenProviding,
        configuration: BoxConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.accountID = accountID
        self.tokenProvider = tokenProvider
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func rootItem() async throws -> BoxItem {
        try await item(.folder("0"))
    }

    func item(_ identity: BoxItemIdentity) async throws -> BoxItem {
        try await get(itemURL(identity), itemID: identity.cloudStorageID)
    }

    func children(
        of folderID: CloudStorageItemID,
        marker: String?
    ) async throws -> BoxItemCollection {
        let identity = try BoxItemIdentity(folderID)
        guard case .folder = identity else {
            throw CloudStorageError.invalidProviderResponse("Box children require a folder ID.")
        }
        var query = [
            URLQueryItem(name: "fields", value: Self.itemFields),
            URLQueryItem(name: "usemarker", value: "true"),
            URLQueryItem(name: "limit", value: "1000"),
        ]
        if let marker {
            query.append(URLQueryItem(name: "marker", value: marker))
        }
        return try await get(
            itemURL(identity).appending(path: "items"),
            queryItems: query,
            itemID: folderID
        )
    }

    func downloadFile(
        _ fileID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> BoxItem {
        let identity = try BoxItemIdentity(fileID)
        guard case .file = identity else {
            throw CloudStorageError.invalidProviderResponse("Box download requires a file ID.")
        }
        let metadata = try await item(identity)
        var request = try await authorizedRequest(
            url: itemURL(identity).appending(path: "content"),
            method: "GET"
        )
        if let etag = metadata.etag {
            request.setValue(etag, forHTTPHeaderField: "If-Match")
        }
        let (temporaryURL, response) = try await urlSession.download(for: request)
        try validate(response, data: nil, itemID: fileID, operation: .download)
        try installDownloadedFile(from: temporaryURL, at: localURL)
        return metadata
    }

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> BoxItem {
        try validateDirectUploadSize(at: localURL)
        let parent = try BoxItemIdentity(parentID)
        guard case .folder(let parentRawID) = parent else {
            throw CloudStorageError.invalidProviderResponse("Box upload requires a folder ID.")
        }
        if case .ifUnmodified = condition {
            throw CloudStorageError.unsupportedOperation(.createFile)
        }
        let attributes: [String: Any] = [
            "name": name,
            "parent": ["id": parentRawID],
        ]
        return try await uploadMultipart(
            url: configuration.uploadBaseURL.appending(path: "files/content"),
            attributes: attributes,
            fileURL: localURL,
            condition: condition,
            itemID: nil,
            operation: .createFile
        )
    }

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> BoxItem {
        try validateDirectUploadSize(at: localURL)
        let identity = try BoxItemIdentity(fileID)
        guard case .file(let rawID) = identity else {
            throw CloudStorageError.invalidProviderResponse("Box update requires a file ID.")
        }
        if case .ifAbsent = condition {
            throw CloudStorageError.unsupportedOperation(.updateFile)
        }
        return try await uploadMultipart(
            url: configuration.uploadBaseURL.appending(path: "files/\(rawID)/content"),
            attributes: [:],
            fileURL: localURL,
            condition: condition,
            itemID: fileID,
            operation: .updateFile
        )
    }

    func createFolder(named name: String, in parentID: CloudStorageItemID) async throws -> BoxItem {
        let parent = try BoxItemIdentity(parentID)
        guard case .folder(let rawID) = parent else {
            throw CloudStorageError.invalidProviderResponse("Box folder creation requires a folder ID.")
        }
        return try await sendJSON(
            url: configuration.apiBaseURL.appending(path: "folders"),
            method: "POST",
            body: ["name": name, "parent": ["id": rawID]],
            itemID: parentID,
            operation: .createFolder
        )
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> BoxItem {
        let identity = try BoxItemIdentity(itemID)
        var body: [String: Any] = [:]
        if let parentID {
            let parent = try BoxItemIdentity(parentID)
            guard case .folder(let rawID) = parent else {
                throw CloudStorageError.invalidProviderResponse("Box destination must be a folder.")
            }
            body["parent"] = ["id": rawID]
        }
        if let newName {
            body["name"] = newName
        }
        return try await sendJSON(
            url: itemURL(identity),
            method: "PUT",
            body: body,
            itemID: itemID,
            operation: .moveItem
        )
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        let identity = try BoxItemIdentity(itemID)
        var request = try await authorizedRequest(url: itemURL(identity), method: "DELETE")
        apply(condition, to: &request)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response, data: data, itemID: itemID, operation: .deleteItem)
    }

    func events(since position: String) async throws -> BoxEventCollection {
        do {
            return try await get(
                configuration.apiBaseURL.appending(path: "events"),
                queryItems: [
                    URLQueryItem(name: "stream_type", value: "changes"),
                    URLQueryItem(name: "stream_position", value: position),
                    URLQueryItem(name: "limit", value: "500"),
                ],
                operation: .readChanges
            )
        } catch let error as CloudStorageError {
            if case .transport(let message) = error,
               message.localizedCaseInsensitiveContains("stream_position") {
                throw CloudStorageError.changeTrackingResetRequired
            }
            throw error
        }
    }

    private func get<Value: Decodable>(
        _ url: URL,
        queryItems: [URLQueryItem]? = nil,
        itemID: CloudStorageItemID? = nil,
        operation: CloudStorageOperation = .browse
    ) async throws -> Value {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CloudStorageError.invalidProviderResponse("Unable to construct Box URL.")
        }
        components.queryItems = queryItems ?? [
            URLQueryItem(name: "fields", value: Self.itemFields),
        ]
        guard let requestURL = components.url else {
            throw CloudStorageError.invalidProviderResponse("Unable to construct Box URL.")
        }
        let request = try await authorizedRequest(url: requestURL, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        try validate(response, data: data, itemID: itemID, operation: operation)
        return try decode(Value.self, from: data)
    }

    private func sendJSON<Value: Decodable>(
        url: URL,
        method: String,
        body: [String: Any],
        itemID: CloudStorageItemID?,
        operation: CloudStorageOperation
    ) async throws -> Value {
        var request = try await authorizedRequest(url: url, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response, data: data, itemID: itemID, operation: operation)
        return try decode(Value.self, from: data)
    }

    private func uploadMultipart(
        url: URL,
        attributes: [String: Any],
        fileURL: URL,
        condition: CloudStorageWriteCondition,
        itemID: CloudStorageItemID?,
        operation: CloudStorageOperation
    ) async throws -> BoxItem {
        let boundary = "ExcalidrawZ-\(UUID().uuidString)"
        let bodyURL = try makeMultipartBody(
            boundary: boundary,
            attributes: attributes,
            fileURL: fileURL
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = try await authorizedRequest(url: url, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        apply(condition, to: &request)
        let (data, response) = try await urlSession.upload(for: request, fromFile: bodyURL)
        try validate(response, data: data, itemID: itemID, operation: operation)
        let upload = try decode(BoxUploadResponse.self, from: data)
        guard let item = upload.entries.first else {
            throw CloudStorageError.invalidProviderResponse("Box upload returned no file.")
        }
        return item
    }

    private func makeMultipartBody(
        boundary: String,
        attributes: [String: Any],
        fileURL: URL
    ) throws -> URL {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appending(path: "box-upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        defer { try? handle.close() }

        let attributesData = try JSONSerialization.data(withJSONObject: attributes)
        try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data(
            "Content-Disposition: form-data; name=\"attributes\"\r\nContent-Type: application/json\r\n\r\n".utf8
        ))
        try handle.write(contentsOf: attributesData)
        try handle.write(contentsOf: Data("\r\n--\(boundary)\r\n".utf8))
        try handle.write(contentsOf: Data(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8
        ))

        let source = try FileHandle(forReadingFrom: fileURL)
        defer { try? source.close() }
        while let data = try source.read(upToCount: 1_048_576), !data.isEmpty {
            try handle.write(contentsOf: data)
        }
        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return temporaryURL
    }

    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.requireFreshCloudStorageResponse(forHTTPMethod: method)
        request.setValue(
            "Bearer \(try await tokenProvider.accessToken(for: accountID))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func itemURL(_ identity: BoxItemIdentity) -> URL {
        switch identity {
            case .file(let id): configuration.apiBaseURL.appending(path: "files/\(id)")
            case .folder(let id): configuration.apiBaseURL.appending(path: "folders/\(id)")
            case .webLink(let id): configuration.apiBaseURL.appending(path: "web_links/\(id)")
        }
    }

    private func apply(_ condition: CloudStorageWriteCondition, to request: inout URLRequest) {
        switch condition {
            case .unconditional:
                break
            case .ifAbsent:
                // Box rejects duplicate names by default when creating files.
                // It does not document If-None-Match for multipart uploads.
                break
            case .ifUnmodified(let revision):
                request.setValue(revision, forHTTPHeaderField: "If-Match")
        }
    }

    private func validate(
        _ response: URLResponse,
        data: Data?,
        itemID: CloudStorageItemID?,
        operation: CloudStorageOperation
    ) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidProviderResponse("Missing Box HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let apiError = data.flatMap { try? decoder.decode(BoxAPIError.self, from: $0) }
            logger.error(
                "Box request failed status=\(response.statusCode) operation=\(operation.rawValue) itemID=\(itemID?.rawValue ?? "none") code=\(apiError?.code ?? "unknown") message=\(apiError?.message ?? "none")"
            )
            switch response.statusCode {
                case 401:
                    throw CloudStorageError.authenticationRequired
                case 403:
                    throw CloudStorageError.permissionDenied(operation)
                case 404:
                    if let itemID { throw CloudStorageError.itemNotFound(itemID) }
                case 409 where apiError?.code == "item_name_in_use":
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
            throw CloudStorageError.transport(
                [apiError?.code, apiError?.message]
                    .compactMap { $0 }
                    .joined(separator: ": ")
                    .nonempty ?? "Box returned HTTP \(response.statusCode)."
            )
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(error.localizedDescription)
        }
    }

    private func validateDirectUploadSize(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize > 50 * 1_024 * 1_024 else { return }
        throw CloudStorageError.transport(
            "Box files larger than 50 MB require a chunked upload session."
        )
    }

    private func installDownloadedFile(from temporaryURL: URL, at localURL: URL) throws {
        let fileManager = FileManager.default
        let directoryURL = localURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
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
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}
