//
//  DropboxAPIClient.swift
//  ExcalidrawZ
//

import Foundation
import Logging

actor DropboxAPIClient {
    nonisolated static let rootItemID = CloudStorageItemID(rawValue: "root")

    private let logger = Logger(label: "DropboxAPIClient")
    private let accountID: CloudStorageAccountID
    private let tokenProvider: any DropboxAccessTokenProviding
    private let configuration: DropboxConfiguration
    private let urlSession: URLSession
    private let decoder = JSONDecoder.dropboxDecoder()

    init(
        accountID: CloudStorageAccountID,
        tokenProvider: any DropboxAccessTokenProviding,
        configuration: DropboxConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.accountID = accountID
        self.tokenProvider = tokenProvider
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func metadata(for itemID: CloudStorageItemID) async throws -> DropboxMetadata {
        guard itemID != Self.rootItemID else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox account root has no remote metadata object."
            )
        }
        return try await sendJSON(
            route: "files/get_metadata",
            body: ["path": itemID.rawValue],
            itemID: itemID,
            operation: .browse
        )
    }

    func listFolder(
        _ folderID: CloudStorageItemID,
        recursive: Bool,
        includeDeleted: Bool
    ) async throws -> DropboxListFolderResult {
        try await sendJSON(
            route: "files/list_folder",
            body: [
                "path": try pathArgument(for: folderID),
                "recursive": recursive,
                "include_deleted": includeDeleted,
                "include_non_downloadable_files": false,
            ],
            itemID: folderID,
            operation: .browse
        )
    }

    func continueListFolder(
        cursor: String,
        operation: CloudStorageOperation = .browse
    ) async throws -> DropboxListFolderResult {
        try await sendJSON(
            route: "files/list_folder/continue",
            body: ["cursor": cursor],
            operation: operation
        )
    }

    func downloadFile(
        _ fileID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> DropboxMetadata {
        var request = try await authorizedRequest(
            url: configuration.contentBaseURL.appending(path: "files/download"),
            method: "POST"
        )
        request.setValue(
            try argumentHeader(["path": fileID.rawValue]),
            forHTTPHeaderField: "Dropbox-API-Arg"
        )
        let (temporaryURL, response) = try await urlSession.download(for: request)
        try validate(response, data: nil, itemID: fileID, operation: .download)
        guard let metadataHeader = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Dropbox-API-Result"),
              let metadataData = metadataHeader.data(using: .utf8) else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox download did not return file metadata."
            )
        }
        let metadata = try decode(DropboxMetadata.self, from: metadataData)
        try installDownloadedFile(from: temporaryURL, at: localURL)
        return metadata
    }

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> DropboxMetadata {
        if case .ifUnmodified = condition {
            throw CloudStorageError.unsupportedOperation(.createFile)
        }
        let destination = try await childPath(named: name, in: parentID)
        let mode: Any = condition == .ifAbsent ? "add" : "overwrite"
        return try await upload(
            localURL,
            arguments: [
                "path": destination,
                "mode": mode,
                "autorename": false,
                "mute": false,
                "strict_conflict": condition == .ifAbsent,
            ],
            itemID: nil,
            operation: .createFile
        )
    }

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> DropboxMetadata {
        if case .ifAbsent = condition {
            throw CloudStorageError.unsupportedOperation(.updateFile)
        }
        let current = try await metadata(for: fileID)
        guard case .file(let file) = current, let path = file.pathLower else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox did not return a path for the file being updated."
            )
        }
        let mode: Any
        switch condition {
            case .ifUnmodified(let revision):
                mode = [".tag": "update", "update": revision]
            case .unconditional:
                mode = "overwrite"
            case .ifAbsent:
                throw CloudStorageError.unsupportedOperation(.updateFile)
        }
        return try await upload(
            localURL,
            arguments: [
                "path": path,
                "mode": mode,
                "autorename": false,
                "mute": false,
                "strict_conflict": true,
            ],
            itemID: fileID,
            operation: .updateFile
        )
    }

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> DropboxMetadata {
        let result: DropboxRelocationResult = try await sendJSON(
            route: "files/create_folder_v2",
            body: [
                "path": try await childPath(named: name, in: parentID),
                "autorename": false,
            ],
            itemID: parentID,
            operation: .createFolder
        )
        return result.metadata
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> DropboxMetadata {
        let current = try await metadata(for: itemID)
        guard let currentPath = current.pathLower else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox did not return a path for the item being moved."
            )
        }
        let destinationName = newName ?? currentPath.lastDropboxPathComponent
        let destinationParentPath: String
        if let parentID {
            destinationParentPath = try await folderPath(for: parentID)
        } else {
            destinationParentPath = currentPath.deletingLastDropboxPathComponent
        }
        let destinationPath = destinationParentPath.appendingDropboxPathComponent(destinationName)
        guard destinationPath != currentPath else { return current }

        let result: DropboxRelocationResult = try await sendJSON(
            route: "files/move_v2",
            body: [
                "from_path": itemID.rawValue,
                "to_path": destinationPath,
                "allow_shared_folder": true,
                "autorename": false,
                "allow_ownership_transfer": false,
            ],
            itemID: itemID,
            operation: .moveItem
        )
        return result.metadata
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        if case .ifAbsent = condition {
            throw CloudStorageError.unsupportedOperation(.deleteItem)
        }
        if case .ifUnmodified(let revision) = condition {
            let current = try await metadata(for: itemID)
            guard case .file(let file) = current, file.rev == revision else {
                throw CloudStorageError.conflict
            }
        }
        let _: DropboxRelocationResult = try await sendJSON(
            route: "files/delete_v2",
            body: ["path": itemID.rawValue],
            itemID: itemID,
            operation: .deleteItem
        )
    }

    func webURL(for itemID: CloudStorageItemID) async throws -> URL {
        let metadata = try await metadata(for: itemID)
        guard let path = metadata.pathDisplay,
              var components = URLComponents(string: "https://www.dropbox.com/home") else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox did not return a display path for this item."
            )
        }
        components.path += path
        guard let url = components.url else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to construct Dropbox web URL."
            )
        }
        return url
    }

    private func upload(
        _ localURL: URL,
        arguments: [String: Any],
        itemID: CloudStorageItemID?,
        operation: CloudStorageOperation
    ) async throws -> DropboxMetadata {
        var request = try await authorizedRequest(
            url: configuration.contentBaseURL.appending(path: "files/upload"),
            method: "POST"
        )
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(try argumentHeader(arguments), forHTTPHeaderField: "Dropbox-API-Arg")
        let (data, response) = try await urlSession.upload(for: request, fromFile: localURL)
        try validate(response, data: data, itemID: itemID, operation: operation)
        return try decode(DropboxMetadata.self, from: data)
    }

    private func sendJSON<Value: Decodable>(
        route: String,
        body: [String: Any],
        itemID: CloudStorageItemID? = nil,
        operation: CloudStorageOperation
    ) async throws -> Value {
        var request = try await authorizedRequest(
            url: configuration.apiBaseURL.appending(path: route),
            method: "POST"
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
        request.setValue(
            "Bearer \(try await tokenProvider.accessToken(for: accountID))",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func pathArgument(for itemID: CloudStorageItemID) throws -> String {
        itemID == Self.rootItemID ? "" : itemID.rawValue
    }

    private func folderPath(for itemID: CloudStorageItemID) async throws -> String {
        if itemID == Self.rootItemID { return "" }
        let metadata = try await metadata(for: itemID)
        guard case .folder(let folder) = metadata, let path = folder.pathLower else {
            throw CloudStorageError.invalidProviderResponse(
                "Dropbox did not return a path for the destination folder."
            )
        }
        return path
    }

    private func childPath(named name: String, in parentID: CloudStorageItemID) async throws -> String {
        try await folderPath(for: parentID).appendingDropboxPathComponent(name)
    }

    private func argumentHeader(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to encode Dropbox request arguments."
            )
        }
        return json.unicodeEscapedForHTTPHeader
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode Dropbox response: \(Self.decodingDescription(for: error))"
            )
        }
    }

    private nonisolated static func decodingDescription(for error: Error) -> String {
        guard let error = error as? DecodingError else {
            return error.localizedDescription
        }

        let context: DecodingError.Context
        let detail: String
        switch error {
            case .keyNotFound(let key, let value):
                context = value
                detail = "missing key '\(key.stringValue)'"
            case .typeMismatch(let type, let value):
                context = value
                detail = "expected \(type)"
            case .valueNotFound(let type, let value):
                context = value
                detail = "missing value of type \(type)"
            case .dataCorrupted(let value):
                context = value
                detail = "invalid data"
            @unknown default:
                return error.localizedDescription
        }

        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        let location = path.isEmpty ? "root" : path
        return "\(detail) at \(location): \(context.debugDescription)"
    }

    private func validate(
        _ response: URLResponse,
        data: Data?,
        itemID: CloudStorageItemID?,
        operation: CloudStorageOperation
    ) throws {
        guard let response = response as? HTTPURLResponse else {
            throw CloudStorageError.invalidProviderResponse("Missing Dropbox HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let apiError = data.flatMap { try? decoder.decode(DropboxAPIError.self, from: $0) }
            let summary = apiError?.errorSummary ?? "Dropbox returned HTTP \(response.statusCode)."
            logger.error(
                "Dropbox request failed status=\(response.statusCode) operation=\(operation.rawValue) itemID=\(itemID?.rawValue ?? "none") summary=\(summary)"
            )
            switch response.statusCode {
                case 401:
                    throw CloudStorageError.authenticationRequired
                case 403:
                    throw CloudStorageError.permissionDenied(operation)
                case 409 where summary.hasPrefix("reset/"):
                    throw CloudStorageError.changeTrackingResetRequired
                case 409 where summary.contains("not_found"):
                    if let itemID { throw CloudStorageError.itemNotFound(itemID) }
                case 409 where summary.contains("conflict"):
                    if operation == .createFile || operation == .createFolder {
                        throw CloudStorageError.itemNameAlreadyExists(nil)
                    }
                    throw CloudStorageError.conflict
                case 429:
                    let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(TimeInterval.init)
                    throw CloudStorageError.rateLimited(retryAfter: retryAfter)
                default:
                    break
            }
            throw CloudStorageError.transport(summary)
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

private extension String {
    var deletingLastDropboxPathComponent: String {
        let value = (self as NSString).deletingLastPathComponent
        return value == "/" ? "" : value
    }

    var lastDropboxPathComponent: String {
        (self as NSString).lastPathComponent
    }

    func appendingDropboxPathComponent(_ component: String) -> String {
        if isEmpty { return "/\(component)" }
        return (self as NSString).appendingPathComponent(component)
    }

    var unicodeEscapedForHTTPHeader: String {
        unicodeScalars.map { scalar in
            if scalar.value < 0x80 {
                return String(scalar)
            }
            if scalar.value <= 0xFFFF {
                return String(format: "\\u%04X", scalar.value)
            }
            let value = scalar.value - 0x10000
            let high = 0xD800 + (value >> 10)
            let low = 0xDC00 + (value & 0x3FF)
            return String(format: "\\u%04X\\u%04X", high, low)
        }
        .joined()
    }
}
