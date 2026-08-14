//
//  BoxModels.swift
//  ExcalidrawZ
//

import Foundation

enum BoxItemIdentity: Hashable, Sendable {
    case file(String)
    case folder(String)
    case webLink(String)

    init(_ itemID: CloudStorageItemID) throws {
        let components = itemID.rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2, !components[1].isEmpty else {
            throw CloudStorageError.invalidProviderResponse(
                "Invalid Box item identifier: \(itemID.rawValue)"
            )
        }
        switch components[0] {
            case "file": self = .file(components[1])
            case "folder": self = .folder(components[1])
            case "web_link": self = .webLink(components[1])
            default:
                throw CloudStorageError.invalidProviderResponse(
                    "Unsupported Box item identifier: \(itemID.rawValue)"
                )
        }
    }

    var rawID: String {
        switch self {
            case .file(let id), .folder(let id), .webLink(let id): id
        }
    }

    var cloudStorageID: CloudStorageItemID {
        switch self {
            case .file(let id): CloudStorageItemID(rawValue: "file:\(id)")
            case .folder(let id): CloudStorageItemID(rawValue: "folder:\(id)")
            case .webLink(let id): CloudStorageItemID(rawValue: "web_link:\(id)")
        }
    }

    var kind: CloudStorageItem.Kind {
        switch self {
            case .file: .file
            case .folder: .folder
            case .webLink: .shortcut
        }
    }
}

struct BoxItem: Decodable, Sendable {
    struct Parent: Decodable, Sendable {
        let type: String?
        let id: String
    }

    struct Permissions: Decodable, Sendable {
        let canDownload: Bool?
        let canUpload: Bool?
        let canRename: Bool?
        let canDelete: Bool?

        enum CodingKeys: String, CodingKey {
            case canDownload = "can_download"
            case canUpload = "can_upload"
            case canRename = "can_rename"
            case canDelete = "can_delete"
        }
    }

    struct SharedLink: Decodable, Sendable {
        let url: URL?

        enum CodingKeys: String, CodingKey {
            case url
        }
    }

    let type: String
    let id: String
    let name: String?
    let size: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let etag: String?
    let parent: Parent?
    let permissions: Permissions?
    let sharedLink: SharedLink?
    let webLinkURL: URL?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case size
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case etag
        case parent
        case permissions
        case sharedLink = "shared_link"
        case webLinkURL = "url"
    }

    var identity: BoxItemIdentity {
        switch type {
            case "folder": .folder(id)
            case "web_link": .webLink(id)
            default: .file(id)
        }
    }

    var cloudStorageItem: CloudStorageItem {
        CloudStorageItem(
            id: identity.cloudStorageID,
            parentID: parent.map {
                ($0.type == "file" ? BoxItemIdentity.file($0.id) : .folder($0.id))
                    .cloudStorageID
            },
            name: name ?? id,
            kind: identity.kind,
            contentType: nil,
            size: size,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            remoteURL: sharedLink?.url ?? webLinkURL,
            revision: etag,
            capabilities: permissions.map { permissions in
                var capabilities: CloudStorageItemCapabilities = []
                if permissions.canDownload == true { capabilities.insert(.download) }
                if permissions.canUpload == true {
                    capabilities.insert(identity.kind == .folder ? .createChildren : .updateContent)
                }
                if permissions.canRename == true {
                    capabilities.formUnion([.rename, .move])
                }
                if permissions.canDelete == true { capabilities.insert(.delete) }
                return capabilities
            }
        )
    }
}

struct BoxItemCollection: Decodable, Sendable {
    let entries: [BoxItem]
    let nextMarker: String?

    enum CodingKeys: String, CodingKey {
        case entries
        case nextMarker = "next_marker"
    }
}

struct BoxUploadResponse: Decodable, Sendable {
    let entries: [BoxItem]
}

struct BoxEventCollection: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        let eventID: String?

        enum CodingKeys: String, CodingKey {
            case eventID = "event_id"
        }
    }

    let entries: [Entry]
    let nextStreamPosition: String

    enum CodingKeys: String, CodingKey {
        case entries
        case nextStreamPosition = "next_stream_position"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decode([Entry].self, forKey: .entries)
        if let value = try? container.decode(String.self, forKey: .nextStreamPosition) {
            nextStreamPosition = value
        } else {
            nextStreamPosition = String(
                try container.decode(Int64.self, forKey: .nextStreamPosition)
            )
        }
    }
}

struct BoxAPIError: Decodable, Sendable {
    let status: Int?
    let code: String?
    let message: String?
}

extension JSONDecoder {
    static func boxDecoder() -> JSONDecoder {
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
                    debugDescription: "Invalid Box date: \(value)"
                )
            }
            return date
        }
        return decoder
    }
}
