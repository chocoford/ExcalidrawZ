//
//  OneDriveGraphModels.swift
//  ExcalidrawZ
//

import Foundation

struct OneDriveGraphCollection<Element: Decodable>: Decodable {
    let value: [Element]
    let nextLink: String?
    let deltaLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
        case deltaLink = "@odata.deltaLink"
    }
}

struct OneDriveDriveItem: Decodable {
    struct FileFacet: Decodable {
        let mimeType: String?
    }

    struct ParentReference: Decodable {
        let id: String?
    }

    struct EmptyFacet: Decodable {}

    let id: String
    let name: String?
    let size: Int64?
    let createdDateTime: Date?
    let lastModifiedDateTime: Date?
    let webUrl: URL?
    let eTag: String?
    let file: FileFacet?
    let folder: EmptyFacet?
    let package: EmptyFacet?
    let remoteItem: EmptyFacet?
    let deleted: EmptyFacet?
    let parentReference: ParentReference?

    var cloudStorageItem: CloudStorageItem {
        CloudStorageItem(
            id: CloudStorageItemID(rawValue: id),
            parentID: parentReference?.id.map(CloudStorageItemID.init(rawValue:)),
            name: name ?? id,
            kind: kind,
            contentType: file?.mimeType,
            size: size,
            createdAt: createdDateTime,
            modifiedAt: lastModifiedDateTime,
            remoteURL: webUrl,
            revision: eTag
        )
    }

    private var kind: CloudStorageItem.Kind {
        if remoteItem != nil {
            return .shortcut
        }
        if package != nil {
            return .package
        }
        if folder != nil {
            return .folder
        }
        if file != nil {
            return .file
        }
        return .unknown
    }
}

struct OneDriveGraphErrorEnvelope: Decodable {
    struct GraphError: Decodable {
        let code: String
        let message: String
    }

    let error: GraphError
}

extension JSONDecoder {
    static func oneDriveGraphDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid Microsoft Graph date: \(value)"
                )
            }
            return date
        }
        return decoder
    }
}
