//
//  GoogleDriveAPIClient.swift
//  ExcalidrawZ
//

import Foundation
import Logging

actor GoogleDriveAPIClient {
    private static let fileFields = [
        "id", "name", "mimeType", "size", "createdTime", "modifiedTime",
        "webViewLink", "version", "headRevisionId", "md5Checksum",
        "sha256Checksum", "parents", "capabilities", "trashed",
    ].joined(separator: ",")

    private let logger = Logger(label: "GoogleDriveAPIClient")
    private let accountID: CloudStorageAccountID
    private let tokenProvider: any GoogleDriveAccessTokenProviding
    private let configuration: GoogleDriveConfiguration
    private let urlSession: URLSession
    private let decoder = JSONDecoder.googleDriveDecoder()

    init(
        accountID: CloudStorageAccountID,
        tokenProvider: any GoogleDriveAccessTokenProviding,
        configuration: GoogleDriveConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.accountID = accountID
        self.tokenProvider = tokenProvider
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func about() async throws -> GoogleDriveAbout {
        try await get(
            configuration.apiBaseURL.appending(path: "about"),
            queryItems: [URLQueryItem(name: "fields", value: "user")],
            operation: .authorize
        )
    }

    func item(_ itemID: CloudStorageItemID) async throws -> GoogleDriveFile {
        try await get(
            configuration.apiBaseURL.appending(path: "files/\(itemID.rawValue)"),
            queryItems: commonQueryItems + [
                URLQueryItem(name: "fields", value: Self.fileFields),
            ],
            itemID: itemID
        )
    }

    func children(
        of folderID: CloudStorageItemID,
        pageToken: String?
    ) async throws -> GoogleDriveFileList {
        var query = commonQueryItems + [
            URLQueryItem(name: "q", value: "'\(folderID.rawValue)' in parents and trashed = false"),
            URLQueryItem(name: "spaces", value: "drive"),
            URLQueryItem(name: "pageSize", value: "1000"),
            URLQueryItem(name: "orderBy", value: "folder,name_natural"),
            URLQueryItem(
                name: "fields",
                value: "nextPageToken,files(\(Self.fileFields))"
            ),
        ]
        if let pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        return try await get(
            configuration.apiBaseURL.appending(path: "files"),
            queryItems: query,
            itemID: folderID
        )
    }

    func downloadFile(
        _ fileID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> GoogleDriveFile {
        let metadata = try await item(fileID)
        var request = try await authorizedRequest(
            url: try requestURL(
                configuration.apiBaseURL.appending(path: "files/\(fileID.rawValue)"),
                queryItems: [URLQueryItem(name: "alt", value: "media")]
            ),
            method: "GET"
        )
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
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
    ) async throws -> GoogleDriveFile {
        if case .ifUnmodified = condition {
            throw CloudStorageError.unsupportedOperation(.createFile)
        }
        if condition == .ifAbsent {
            try await ensureItemDoesNotExist(named: name, in: parentID)
        }
        return try await uploadMultipart(
            metadata: ["name": name, "parents": [parentID.rawValue]],
            fileURL: localURL
        )
    }

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> GoogleDriveFile {
        if case .ifAbsent = condition {
            throw CloudStorageError.unsupportedOperation(.updateFile)
        }
        try await validate(condition, for: fileID, operation: .updateFile)
        let url = try requestURL(
            configuration.uploadBaseURL.appending(path: "files/\(fileID.rawValue)"),
            queryItems: commonQueryItems + [
                URLQueryItem(name: "uploadType", value: "media"),
                URLQueryItem(name: "fields", value: Self.fileFields),
            ]
        )
        var request = try await authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await urlSession.upload(for: request, fromFile: localURL)
        try self.validate(response, data: data, itemID: fileID, operation: .updateFile)
        return try decode(GoogleDriveFile.self, from: data)
    }

    func createFolder(named name: String, in parentID: CloudStorageItemID) async throws -> GoogleDriveFile {
        try await ensureItemDoesNotExist(named: name, in: parentID)
        return try await sendJSON(
            url: configuration.apiBaseURL.appending(path: "files"),
            method: "POST",
            queryItems: commonQueryItems + [URLQueryItem(name: "fields", value: Self.fileFields)],
            body: [
                "name": name,
                "mimeType": GoogleDriveFile.folderMIMEType,
                "parents": [parentID.rawValue],
            ],
            itemID: parentID,
            operation: .createFolder
        )
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> GoogleDriveFile {
        let current = try await item(itemID)
        var query = commonQueryItems + [URLQueryItem(name: "fields", value: Self.fileFields)]
        if let parentID {
            query.append(URLQueryItem(name: "addParents", value: parentID.rawValue))
            if let parents = current.parents, !parents.isEmpty {
                query.append(URLQueryItem(name: "removeParents", value: parents.joined(separator: ",")))
            }
        }
        let body = newName.map { ["name": $0] } ?? [:]
        return try await sendJSON(
            url: configuration.apiBaseURL.appending(path: "files/\(itemID.rawValue)"),
            method: "PATCH",
            queryItems: query,
            body: body,
            itemID: itemID,
            operation: .moveItem
        )
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        try await validate(condition, for: itemID, operation: .deleteItem)
        let _: GoogleDriveFile = try await sendJSON(
            url: configuration.apiBaseURL.appending(path: "files/\(itemID.rawValue)"),
            method: "PATCH",
            queryItems: commonQueryItems + [URLQueryItem(name: "fields", value: Self.fileFields)],
            body: ["trashed": true],
            itemID: itemID,
            operation: .deleteItem
        )
    }

    private var commonQueryItems: [URLQueryItem] {
        [URLQueryItem(name: "supportsAllDrives", value: "true")]
    }

    private func ensureItemDoesNotExist(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws {
        let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
        let response: GoogleDriveFileList = try await get(
            configuration.apiBaseURL.appending(path: "files"),
            queryItems: commonQueryItems + [
                URLQueryItem(
                    name: "q",
                    value: "'\(parentID.rawValue)' in parents and name = '\(escapedName)' and trashed = false"
                ),
                URLQueryItem(name: "pageSize", value: "1"),
                URLQueryItem(name: "fields", value: "files(\(Self.fileFields))"),
            ],
            itemID: parentID
        )
        if !response.files.isEmpty {
            throw CloudStorageError.itemNameAlreadyExists(name)
        }
    }

    private func validate(
        _ condition: CloudStorageWriteCondition,
        for itemID: CloudStorageItemID,
        operation: CloudStorageOperation
    ) async throws {
        switch condition {
            case .unconditional:
                return
            case .ifAbsent:
                throw CloudStorageError.unsupportedOperation(operation)
            case .ifUnmodified(let revision):
                let remoteFile = try await item(itemID)
                let remoteRevision = remoteFile.cloudStorageItem.revision
                // Existing caches used Drive's broad numeric `version` as
                // their revision token. Accept that token once so the next
                // successful response can migrate the cache to a content
                // fingerprint without surfacing a false conflict.
                let matchesCurrentContent = remoteRevision == revision
                    || remoteFile.version == revision
                guard matchesCurrentContent else {
                    logger.warning(
                        "Google Drive revision conflict itemID=\(itemID.rawValue) expected=\(revision) actual=\(remoteRevision ?? "nil")"
                    )
                    throw CloudStorageError.conflict
                }
        }
    }

    private func uploadMultipart(
        metadata: [String: Any],
        fileURL: URL
    ) async throws -> GoogleDriveFile {
        let boundary = "ExcalidrawZ-\(UUID().uuidString)"
        let bodyURL = try makeMultipartBody(boundary: boundary, metadata: metadata, fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let url = try requestURL(
            configuration.uploadBaseURL.appending(path: "files"),
            queryItems: commonQueryItems + [
                URLQueryItem(name: "uploadType", value: "multipart"),
                URLQueryItem(name: "fields", value: Self.fileFields),
            ]
        )
        var request = try await authorizedRequest(url: url, method: "POST")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await urlSession.upload(for: request, fromFile: bodyURL)
        try validate(response, data: data, itemID: nil, operation: .createFile)
        return try decode(GoogleDriveFile.self, from: data)
    }

    private func makeMultipartBody(
        boundary: String,
        metadata: [String: Any],
        fileURL: URL
    ) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appending(path: "GoogleDriveUpload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }

        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try output.write(contentsOf: Data("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        try output.write(contentsOf: metadataData)
        try output.write(contentsOf: Data("\r\n--\(boundary)\r\n".utf8))
        try output.write(contentsOf: Data("Content-Type: application/octet-stream\r\n\r\n".utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return bodyURL
    }

    private func get<Value: Decodable>(
        _ url: URL,
        queryItems: [URLQueryItem],
        itemID: CloudStorageItemID? = nil,
        operation: CloudStorageOperation = .browse
    ) async throws -> Value {
        let request = try await authorizedRequest(
            url: try requestURL(url, queryItems: queryItems),
            method: "GET"
        )
        let (data, response) = try await urlSession.data(for: request)
        try validate(response, data: data, itemID: itemID, operation: operation)
        return try decode(Value.self, from: data)
    }

    private func sendJSON<Value: Decodable>(
        url: URL,
        method: String,
        queryItems: [URLQueryItem],
        body: [String: Any],
        itemID: CloudStorageItemID?,
        operation: CloudStorageOperation
    ) async throws -> Value {
        var request = try await authorizedRequest(
            url: try requestURL(url, queryItems: queryItems),
            method: method
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response, data: data, itemID: itemID, operation: operation)
        return try decode(Value.self, from: data)
    }

    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.requireFreshCloudStorageResponse(forHTTPMethod: method)
        request.setValue(
            "Bearer \(try await tokenProvider.accessToken(for: accountID))",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func requestURL(_ url: URL, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CloudStorageError.invalidProviderResponse("Unable to construct Google Drive URL.")
        }
        components.queryItems = queryItems
        guard let result = components.url else {
            throw CloudStorageError.invalidProviderResponse("Unable to construct Google Drive URL.")
        }
        return result
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode Google Drive response: \(error.localizedDescription)"
            )
        }
    }

    private func validate(
        _ response: URLResponse,
        data: Data?,
        itemID: CloudStorageItemID?,
        operation: CloudStorageOperation
    ) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidProviderResponse("Missing Google Drive HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let apiError = data.flatMap { try? decoder.decode(GoogleDriveAPIErrorResponse.self, from: $0) }
            let reason = apiError?.error.errors?.first?.reason
            let message = apiError?.error.message ?? "Google Drive returned HTTP \(response.statusCode)."
            logger.error(
                "Google Drive request failed status=\(response.statusCode) operation=\(operation.rawValue) itemID=\(itemID?.rawValue ?? "none") reason=\(reason ?? "none") message=\(message)"
            )
            switch response.statusCode {
                case 401:
                    throw CloudStorageError.authenticationRequired
                case 403 where reason == "rateLimitExceeded" || reason == "userRateLimitExceeded":
                    throw CloudStorageError.rateLimited(retryAfter: nil)
                case 403:
                    throw CloudStorageError.permissionDenied(operation)
                case 404:
                    if let itemID { throw CloudStorageError.itemNotFound(itemID) }
                case 409, 412:
                    throw CloudStorageError.conflict
                case 429:
                    let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(TimeInterval.init)
                    throw CloudStorageError.rateLimited(retryAfter: retryAfter)
                default:
                    break
            }
            throw CloudStorageError.transport(message)
        }
    }

    private func installDownloadedFile(from temporaryURL: URL, at destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }
}
