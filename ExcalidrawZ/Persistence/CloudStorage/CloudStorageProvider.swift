//
//  CloudStorageProvider.swift
//  ExcalidrawZ
//
//  A provider creates authenticated account sessions. Each session scopes all
//  opaque item IDs to one provider account and serializes its own operations.
//

import Foundation

protocol CloudStorageProvider: Sendable {
    var descriptor: CloudStorageProviderDescriptor { get }

    func authorizationStatus() async -> CloudStorageAuthorizationStatus
    func authorize() async throws -> CloudStorageAccount
    func authorize(
        using connectionInput: CloudStorageConnectionInput?
    ) async throws -> CloudStorageAccount
    func makeSession(for account: CloudStorageAccount) async throws -> any CloudStorageSession
    func signOut(accountID: CloudStorageAccountID) async throws

    /// Begins the provider's preferred root-selection flow. Most providers
    /// authenticate first and then use ExcalidrawZ's folder browser. Providers
    /// with a security-scoped system picker can authorize and select a root in
    /// one operation instead.
    func selectLocation(
        for account: CloudStorageAccount?
    ) async throws -> CloudStorageLocationSelection
    func selectLocation(
        for account: CloudStorageAccount?,
        using connectionInput: CloudStorageConnectionInput?
    ) async throws -> CloudStorageLocationSelection
}

enum CloudStorageLocationSelection: Sendable {
    case browse(account: CloudStorageAccount)
    case selected(account: CloudStorageAccount, folder: CloudStorageItem)
}

extension CloudStorageProvider {
    func authorize(
        using connectionInput: CloudStorageConnectionInput?
    ) async throws -> CloudStorageAccount {
        guard case nil = connectionInput else {
            throw CloudStorageError.invalidProviderResponse(
                "This provider does not accept server credentials."
            )
        }
        return try await authorize()
    }

    func selectLocation(
        for account: CloudStorageAccount?
    ) async throws -> CloudStorageLocationSelection {
        if let account {
            return .browse(account: account)
        }
        return .browse(account: try await authorize())
    }

    func selectLocation(
        for account: CloudStorageAccount?,
        using connectionInput: CloudStorageConnectionInput?
    ) async throws -> CloudStorageLocationSelection {
        if case nil = connectionInput {
            return try await selectLocation(for: account)
        }
        return .browse(account: try await authorize(using: connectionInput))
    }
}

/// The local URL parameters below are transfer endpoints, not remote identity.
/// Providers can stream downloads into App-managed cache files and upload from
/// them without requiring the entire drawing or media payload in memory.
protocol CloudStorageSession: Actor {
    nonisolated var providerID: CloudStorageProviderID { get }
    nonisolated var account: CloudStorageAccount { get }
    nonisolated var capabilities: CloudStorageProviderCapabilities { get }

    func rootItem() async throws -> CloudStorageItem
    func item(for id: CloudStorageItemID) async throws -> CloudStorageItem
    /// Resolves the provider-facing URL used by reveal and copy-link actions.
    /// Providers may override this when metadata does not carry a stable URL.
    func remoteURL(for item: CloudStorageItem) async throws -> URL
    func listChildren(
        of folderID: CloudStorageItemID,
        pageToken: String?
    ) async throws -> CloudStorageItemPage

    func downloadFile(
        _ fileID: CloudStorageItemID,
        to localURL: URL
    ) async throws -> CloudStorageItem

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> CloudStorageItem

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> CloudStorageItem

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws

    /// Returns changes normalized to the selected root. Providers whose native
    /// change feed is account-wide must filter out unrelated entries, emit a
    /// deletion when an indexed item leaves this subtree, and enumerate a
    /// folder's descendants when it enters the subtree.
    ///
    /// Throw `CloudStorageError.changeTrackingResetRequired` when the provider
    /// can no longer continue from the supplied cursor.
    func changes(
        in rootItemID: CloudStorageItemID,
        since cursor: CloudStorageChangeCursor?
    ) async throws -> CloudStorageChangePage
}

extension CloudStorageSession {
    func remoteURL(for item: CloudStorageItem) async throws -> URL {
        guard let remoteURL = item.remoteURL else {
            throw CloudStorageError.invalidProviderResponse(
                "The cloud storage provider did not return a web URL for this item."
            )
        }
        return remoteURL
    }

    func createFile(
        named name: String,
        in parentID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        throw CloudStorageError.unsupportedOperation(.createFile)
    }

    func updateFile(
        _ fileID: CloudStorageItemID,
        contentsAt localURL: URL,
        condition: CloudStorageWriteCondition
    ) async throws -> CloudStorageItem {
        throw CloudStorageError.unsupportedOperation(.updateFile)
    }

    func createFolder(
        named name: String,
        in parentID: CloudStorageItemID
    ) async throws -> CloudStorageItem {
        throw CloudStorageError.unsupportedOperation(.createFolder)
    }

    func moveItem(
        _ itemID: CloudStorageItemID,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) async throws -> CloudStorageItem {
        throw CloudStorageError.unsupportedOperation(.moveItem)
    }

    func deleteItem(
        _ itemID: CloudStorageItemID,
        condition: CloudStorageWriteCondition
    ) async throws {
        throw CloudStorageError.unsupportedOperation(.deleteItem)
    }

    func changes(
        in rootItemID: CloudStorageItemID,
        since cursor: CloudStorageChangeCursor?
    ) async throws -> CloudStorageChangePage {
        throw CloudStorageError.unsupportedOperation(.readChanges)
    }
}
