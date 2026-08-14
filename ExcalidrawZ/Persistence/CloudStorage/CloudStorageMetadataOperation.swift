//
//  CloudStorageMetadataOperation.swift
//  ExcalidrawZ
//

import Foundation

/// A durable provider-neutral metadata mutation. The local index is updated
/// before this operation is enqueued, keeping UI and navigation usable offline.
struct CloudStorageMetadataOperation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case createFile
        case createFolder
        case moveItem
        case deleteItem
    }

    let id: UUID
    var kind: Kind
    var itemID: CloudStorageItemID
    var parentID: CloudStorageItemID?
    var name: String?
    var revision: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        itemID: CloudStorageItemID,
        parentID: CloudStorageItemID? = nil,
        name: String? = nil,
        revision: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.itemID = itemID
        self.parentID = parentID
        self.name = name
        self.revision = revision
        self.createdAt = createdAt
    }

    func replacingItemIDs(
        using replacements: [CloudStorageItemID: CloudStorageItemID]
    ) -> Self {
        var operation = self
        operation.itemID = replacements[itemID] ?? itemID
        if let parentID {
            operation.parentID = replacements[parentID] ?? parentID
        }
        return operation
    }
}

extension CloudStorageItemID {
    static func pendingLocalID() -> Self {
        Self(rawValue: "local-pending:\(UUID().uuidString)")
    }

    var isPendingLocalID: Bool {
        rawValue.hasPrefix("local-pending:")
    }
}

extension CloudStorageMetadataOperation {
    var cloudOperation: CloudStorageOperation {
        switch kind {
            case .createFile:
                .createFile
            case .createFolder:
                .createFolder
            case .moveItem:
                .moveItem
            case .deleteItem:
                .deleteItem
        }
    }
}
