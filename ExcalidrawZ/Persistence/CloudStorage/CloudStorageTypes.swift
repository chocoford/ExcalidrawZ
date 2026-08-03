//
//  CloudStorageTypes.swift
//  ExcalidrawZ
//
//  Provider-neutral identities and transfer models for connected cloud storage.
//  Remote items are identified by opaque IDs, never by local file URLs.
//

import Foundation

extension Notification.Name {
    static let cloudStorageDocumentContentDidChange = Notification.Name(
        "CloudStorageDocumentContentDidChange"
    )
}

struct CloudStorageProviderID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CloudStorageProviderID {
    static let microsoftOneDrive = Self(rawValue: "microsoft.onedrive")
    static let googleDrive = Self(rawValue: "google.drive")
    static let dropbox = Self(rawValue: "dropbox")
    static let box = Self(rawValue: "box")

    var displayName: String {
        switch self {
            case .microsoftOneDrive: "OneDrive"
            case .googleDrive: "Google Drive"
            case .dropbox: "Dropbox"
            case .box: "Box"
            default: "Cloud Storage"
        }
    }
}

struct CloudStorageAccountID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct CloudStorageItemID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct CloudStorageChangeCursor: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct CloudStorageProviderCapabilities: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    static let createFile = Self(rawValue: 1 << 0)
    static let updateFile = Self(rawValue: 1 << 1)
    static let createFolder = Self(rawValue: 1 << 2)
    static let moveItem = Self(rawValue: 1 << 3)
    static let deleteItem = Self(rawValue: 1 << 4)
    static let deltaChanges = Self(rawValue: 1 << 5)

    static let readWrite: Self = [
        .createFile,
        .updateFile,
        .createFolder,
        .moveItem,
        .deleteItem,
    ]
}

struct CloudStorageProviderDescriptor: Codable, Hashable, Sendable {
    let id: CloudStorageProviderID
    let displayName: String
    let capabilities: CloudStorageProviderCapabilities
}

/// Public account metadata only. Authentication material belongs in the
/// provider implementation and should be stored in Keychain.
struct CloudStorageAccount: Codable, Hashable, Sendable {
    let providerID: CloudStorageProviderID
    let id: CloudStorageAccountID
    let displayName: String
    let emailAddress: String?
}

/// A user-selected remote root. This is the value that can later be persisted
/// alongside App metadata without persisting provider credentials.
struct CloudStorageLocation: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let providerID: CloudStorageProviderID
    let accountID: CloudStorageAccountID
    let rootItemID: CloudStorageItemID
    let displayName: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        providerID: CloudStorageProviderID,
        accountID: CloudStorageAccountID,
        rootItemID: CloudStorageItemID,
        displayName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.accountID = accountID
        self.rootItemID = rootItemID
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

struct CloudStorageItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case file
        case folder
        case package
        case shortcut
        case unknown
    }

    let id: CloudStorageItemID
    let parentID: CloudStorageItemID?
    let name: String
    let kind: Kind
    let contentType: String?
    let size: Int64?
    let createdAt: Date?
    let modifiedAt: Date?
    let remoteURL: URL?

    /// Opaque provider revision, ETag, or content version used for conflict
    /// detection. Callers must not compare revisions across providers.
    let revision: String?
}

/// Stable remote identity carried by an open editor session. Mutable provider
/// metadata such as the latest revision remains owned by
/// `CloudStorageDocumentStore`, so refreshing an item cannot change the active
/// file's identity underneath SwiftUI.
struct CloudStorageDocumentReference: Codable, Hashable, Identifiable, Sendable {
    let locationID: UUID
    let providerID: CloudStorageProviderID
    let accountID: CloudStorageAccountID
    let itemID: CloudStorageItemID

    /// Last-known metadata is only an offline presentation fallback. The
    /// authoritative value lives in `CloudStorageDocumentStore` and is looked
    /// up by `itemID` whenever its location index is available.
    let lastKnownName: String
    let lastKnownModifiedAt: Date?

    init(
        locationID: UUID,
        providerID: CloudStorageProviderID,
        accountID: CloudStorageAccountID,
        itemID: CloudStorageItemID,
        lastKnownName: String,
        lastKnownModifiedAt: Date? = nil
    ) {
        self.locationID = locationID
        self.providerID = providerID
        self.accountID = accountID
        self.itemID = itemID
        self.lastKnownName = lastKnownName
        self.lastKnownModifiedAt = lastKnownModifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case locationID
        case providerID
        case accountID
        case itemID
        case lastKnownName = "name"
        case lastKnownModifiedAt = "modifiedAt"
    }

    var id: String {
        "\(providerID.rawValue):\(accountID.rawValue):\(locationID.uuidString):\(itemID.rawValue)"
    }

    static func == (
        lhs: CloudStorageDocumentReference,
        rhs: CloudStorageDocumentReference
    ) -> Bool {
        lhs.locationID == rhs.locationID
            && lhs.providerID == rhs.providerID
            && lhs.accountID == rhs.accountID
            && lhs.itemID == rhs.itemID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(locationID)
        hasher.combine(providerID)
        hasher.combine(accountID)
        hasher.combine(itemID)
    }
}

/// Stable folder identity used by Sidebar and File Home navigation. Keeping
/// the selected remote root in the reference lets navigation remain valid
/// without treating provider items as local URLs or Core Data objects.
struct CloudStorageFolderReference: Codable, Hashable, Identifiable, Sendable {
    let location: CloudStorageLocation
    let itemID: CloudStorageItemID
    let parentID: CloudStorageItemID?
    let name: String

    var id: String {
        "\(location.id.uuidString):\(itemID.rawValue)"
    }

    var isLocationRoot: Bool {
        itemID == location.rootItemID
    }

    static func root(of location: CloudStorageLocation) -> Self {
        Self(
            location: location,
            itemID: location.rootItemID,
            parentID: nil,
            name: location.displayName
        )
    }

    init(location: CloudStorageLocation, item: CloudStorageItem) {
        self.location = location
        self.itemID = item.id
        self.parentID = item.parentID
        self.name = item.name
    }

    private init(
        location: CloudStorageLocation,
        itemID: CloudStorageItemID,
        parentID: CloudStorageItemID?,
        name: String
    ) {
        self.location = location
        self.itemID = itemID
        self.parentID = parentID
        self.name = name
    }
}

struct CloudStorageItemPage: Codable, Hashable, Sendable {
    let items: [CloudStorageItem]
    let nextPageToken: String?
}

enum CloudStorageChange: Codable, Hashable, Sendable {
    case upsert(CloudStorageItem)
    case deleted(CloudStorageItemID)
}

struct CloudStorageChangePage: Codable, Hashable, Sendable {
    let changes: [CloudStorageChange]
    let nextCursor: CloudStorageChangeCursor
    let hasMore: Bool
}

enum CloudStorageWriteCondition: Codable, Hashable, Sendable {
    case unconditional
    case ifAbsent
    case ifUnmodified(revision: String)
}

enum CloudStorageAuthorizationStatus: Equatable, Sendable {
    case unknown
    case signedOut
    case authorizing
    case signedIn(accounts: [CloudStorageAccount])
}

enum CloudStorageOperation: String, Codable, Sendable {
    case authorize
    case browse
    case download
    case createFile
    case updateFile
    case createFolder
    case moveItem
    case deleteItem
    case readChanges
}

/// Runtime synchronization state for one provider-backed document.
///
/// This describes only the relationship between this device's local cache and
/// the provider. `synced` means the provider accepted or verified the current
/// revision; it does not imply that another device has downloaded it.
enum CloudStorageDocumentSyncState: Equatable, Sendable {
    case local
    case queued
    case checking
    case downloading(progress: Double?)
    case uploading(progress: Double?)
    case synced(lastVerifiedAt: Date)
    case processing
    case conflict
    case failed(operation: CloudStorageOperation, message: String)

    var isActivelySynchronizing: Bool {
        switch self {
            case .checking, .downloading, .uploading, .processing:
                true
            case .local, .queued, .synced, .conflict, .failed:
                false
        }
    }

    var needsAttention: Bool {
        switch self {
            case .conflict, .failed:
                true
            default:
                false
        }
    }
}

enum CloudStorageFolderSyncState: Equatable, Sendable {
    case idle
    case queued
    case synchronizing
}

enum CloudStorageContentSynchronizationPriority: Int, Comparable, Sendable {
    case background
    case userInitiated

    static func < (
        lhs: CloudStorageContentSynchronizationPriority,
        rhs: CloudStorageContentSynchronizationPriority
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum CloudStorageError: LocalizedError, Equatable, Sendable {
    case authenticationRequired
    case authorizationCancelled
    case accountUnavailable(CloudStorageAccountID)
    case itemNotFound(CloudStorageItemID)
    case itemNameAlreadyExists(String?)
    case conflict
    case rateLimited(retryAfter: TimeInterval?)
    case unsupportedOperation(CloudStorageOperation)
    case invalidProviderResponse(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
            case .authenticationRequired:
                return "Cloud storage authentication is required."
            case .authorizationCancelled:
                return "Cloud storage authorization was cancelled."
            case .accountUnavailable(let accountID):
                return "Cloud storage account is unavailable: \(accountID.rawValue)"
            case .itemNotFound(let itemID):
                return "Cloud storage item was not found: \(itemID.rawValue)"
            case .itemNameAlreadyExists(let name):
                if let name {
                    return "An item named \"\(name)\" already exists in this folder."
                }
                return "An item with this name already exists in this folder."
            case .conflict:
                return "The cloud storage item changed before the operation completed."
            case .rateLimited(let retryAfter):
                if let retryAfter {
                    return "The cloud storage provider rate limited the request. Retry after \(retryAfter) seconds."
                }
                return "The cloud storage provider rate limited the request."
            case .unsupportedOperation(let operation):
                return "The cloud storage provider does not support \(operation.rawValue)."
            case .invalidProviderResponse(let reason):
                return "The cloud storage provider returned an invalid response: \(reason)"
            case .transport(let reason):
                return "The cloud storage request failed: \(reason)"
        }
    }
}
