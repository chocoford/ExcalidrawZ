//
//  GoogleDriveModels.swift
//  ExcalidrawZ
//

import Foundation

struct GoogleDriveFile: Decodable, Sendable {
    static let folderMIMEType = "application/vnd.google-apps.folder"

    struct Capabilities: Decodable, Sendable {
        let canDownload: Bool?
        let canAddChildren: Bool?
        let canModifyContent: Bool?
        let canRename: Bool?
        let canMoveItemWithinDrive: Bool?
        let canTrash: Bool?
    }

    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let createdTime: Date?
    let modifiedTime: Date?
    let webViewLink: URL?
    let version: String?
    let headRevisionId: String?
    let md5Checksum: String?
    let sha256Checksum: String?
    let parents: [String]?
    let capabilities: Capabilities?
    let trashed: Bool?

    var cloudStorageItem: CloudStorageItem {
        let isFolder = mimeType == Self.folderMIMEType
        return CloudStorageItem(
            id: CloudStorageItemID(rawValue: id),
            parentID: parents?.first.map(CloudStorageItemID.init(rawValue:)),
            name: name,
            kind: isFolder ? .folder : .file,
            contentType: isFolder ? nil : mimeType,
            size: size.flatMap(Int64.init),
            createdAt: createdTime,
            modifiedAt: modifiedTime,
            remoteURL: webViewLink,
            // Drive's `version` changes for every server-side mutation,
            // including changes unrelated to file content. Using it as an
            // optimistic content token makes sequential saves conflict with
            // the app's own previous upload. Prefer a content fingerprint;
            // binary Excalidraw files expose these fields through Drive v3.
            revision: sha256Checksum
                ?? md5Checksum
                ?? headRevisionId
                ?? version
                ?? modifiedTime.map { String($0.timeIntervalSince1970) },
            capabilities: cloudStorageCapabilities(isFolder: isFolder)
        )
    }

    private func cloudStorageCapabilities(isFolder: Bool) -> CloudStorageItemCapabilities? {
        guard let capabilities else { return nil }
        var result: CloudStorageItemCapabilities = []
        if capabilities.canDownload == true { result.insert(.download) }
        if capabilities.canAddChildren == true { result.insert(.createChildren) }
        if capabilities.canModifyContent == true { result.insert(.updateContent) }
        if capabilities.canRename == true { result.insert(.rename) }
        if capabilities.canMoveItemWithinDrive == true { result.insert(.move) }
        if capabilities.canTrash == true { result.insert(.delete) }
        if isFolder { result.remove(.download) }
        return result
    }
}

struct GoogleDriveFileList: Decodable, Sendable {
    let nextPageToken: String?
    let files: [GoogleDriveFile]
}

struct GoogleDriveAbout: Decodable, Sendable {
    struct User: Decodable, Sendable {
        let displayName: String?
        let emailAddress: String?
        let permissionId: String
    }

    let user: User
}

struct GoogleDriveAPIErrorResponse: Decodable, Sendable {
    struct APIError: Decodable, Sendable {
        let code: Int?
        let message: String?
        let errors: [Detail]?
    }

    struct Detail: Decodable, Sendable {
        let reason: String?
        let message: String?
    }

    let error: APIError
}

extension JSONDecoder {
    static func googleDriveDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let fractionalDateFormatter = ISO8601DateFormatter()
        fractionalDateFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        let standardDateFormatter = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = fractionalDateFormatter.date(from: value) { return date }

            guard let date = standardDateFormatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid Google Drive date: \(value)"
                )
            }
            return date
        }
        return decoder
    }
}
