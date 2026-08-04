//
//  DropboxModels.swift
//  ExcalidrawZ
//

import Foundation
import UniformTypeIdentifiers

enum DropboxMetadata: Decodable, Sendable {
    case file(DropboxFileMetadata)
    case folder(DropboxFolderMetadata)
    case deleted(DropboxDeletedMetadata)

    private enum CodingKeys: String, CodingKey {
        case tag = ".tag"
        case id
        case rev
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeIfPresent(String.self, forKey: .tag) {
            case "file": self = .file(try DropboxFileMetadata(from: decoder))
            case "folder": self = .folder(try DropboxFolderMetadata(from: decoder))
            case "deleted": self = .deleted(try DropboxDeletedMetadata(from: decoder))
            case nil where container.contains(.rev):
                self = .file(try DropboxFileMetadata(from: decoder))
            case nil where container.contains(.id):
                self = .folder(try DropboxFolderMetadata(from: decoder))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .tag,
                    in: container,
                    debugDescription: "Dropbox metadata has no supported subtype discriminator."
                )
        }
    }

    var pathLower: String? {
        switch self {
            case .file(let metadata): metadata.pathLower
            case .folder(let metadata): metadata.pathLower
            case .deleted(let metadata): metadata.pathLower
        }
    }

    var pathDisplay: String? {
        switch self {
            case .file(let metadata): metadata.pathDisplay
            case .folder(let metadata): metadata.pathDisplay
            case .deleted(let metadata): metadata.pathDisplay
        }
    }

    var itemID: CloudStorageItemID? {
        switch self {
            case .file(let metadata): CloudStorageItemID(rawValue: metadata.id)
            case .folder(let metadata): CloudStorageItemID(rawValue: metadata.id)
            case .deleted: nil
        }
    }

    var isFolder: Bool {
        if case .folder(_) = self { return true }
        return false
    }

    func cloudStorageItem(parentID: CloudStorageItemID?) -> CloudStorageItem? {
        switch self {
            case .file(let metadata): metadata.cloudStorageItem(parentID: parentID)
            case .folder(let metadata): metadata.cloudStorageItem(parentID: parentID)
            case .deleted: nil
        }
    }
}

struct DropboxFileMetadata: Decodable, Sendable {
    let id: String
    let name: String
    let pathLower: String?
    let pathDisplay: String?
    let clientModified: Date?
    let serverModified: Date?
    let rev: String
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case pathLower = "path_lower"
        case pathDisplay = "path_display"
        case clientModified = "client_modified"
        case serverModified = "server_modified"
        case rev
        case size
    }

    func cloudStorageItem(parentID: CloudStorageItemID?) -> CloudStorageItem {
        CloudStorageItem(
            id: CloudStorageItemID(rawValue: id),
            parentID: parentID,
            name: name,
            kind: .file,
            contentType: UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType,
            size: size,
            createdAt: clientModified,
            modifiedAt: serverModified ?? clientModified,
            remoteURL: nil,
            revision: rev,
            capabilities: .writableFile
        )
    }
}

struct DropboxFolderMetadata: Decodable, Sendable {
    let id: String
    let name: String
    let pathLower: String?
    let pathDisplay: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case pathLower = "path_lower"
        case pathDisplay = "path_display"
    }

    func cloudStorageItem(parentID: CloudStorageItemID?) -> CloudStorageItem {
        CloudStorageItem(
            id: CloudStorageItemID(rawValue: id),
            parentID: parentID,
            name: name,
            kind: .folder,
            contentType: nil,
            size: nil,
            createdAt: nil,
            modifiedAt: nil,
            remoteURL: nil,
            revision: nil,
            capabilities: .writableFolder
        )
    }
}

struct DropboxDeletedMetadata: Decodable, Sendable {
    let name: String
    let pathLower: String?
    let pathDisplay: String?

    enum CodingKeys: String, CodingKey {
        case name
        case pathLower = "path_lower"
        case pathDisplay = "path_display"
    }
}

struct DropboxListFolderResult: Decodable, Sendable {
    let entries: [DropboxMetadata]
    let cursor: String
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case entries
        case cursor
        case hasMore = "has_more"
    }
}

struct DropboxRelocationResult: Decodable, Sendable {
    let metadata: DropboxMetadata
}

struct DropboxAPIError: Decodable, Sendable {
    let errorSummary: String?

    enum CodingKeys: String, CodingKey {
        case errorSummary = "error_summary"
    }
}

extension JSONDecoder {
    static func dropboxDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let standard = ISO8601DateFormatter()
            guard let date = standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid Dropbox date: \(value)"
                )
            }
            return date
        }
        return decoder
    }
}
