//
//  GoogleDriveCloudStorageProvider.swift
//  ExcalidrawZ
//

import Foundation
import Logging

struct GoogleDriveCloudStorageProvider: CloudStorageProvider {
    // `drive.file` only exposes items selected through Picker or created by
    // ExcalidrawZ. Selecting a folder does not recursively grant its existing
    // descendants, so this provider must not advertise full folder semantics.
    private static let driveFileCapabilities: CloudStorageProviderCapabilities = [
        .createFile,
        .updateFile,
        .moveItem,
        .deleteItem,
    ]

    let descriptor = CloudStorageProviderDescriptor(
        id: .googleDrive,
        displayName: "Google Drive",
        capabilities: driveFileCapabilities
    )

    private let authenticator: any GoogleDriveAuthenticating
    private let configuration: GoogleDriveConfiguration
    private let logger = Logger(label: "GoogleDriveCloudStorageProvider")

    let requiresLocationSelectionForReauthorization = true

    init(
        authenticator: any GoogleDriveAuthenticating,
        configuration: GoogleDriveConfiguration
    ) {
        self.authenticator = authenticator
        self.configuration = configuration
    }

    func authorizationStatus() async -> CloudStorageAuthorizationStatus {
        do {
            let accounts = try await authenticator.accounts()
            return accounts.isEmpty ? .signedOut : .signedIn(accounts: accounts)
        } catch {
            logger.error("Unable to restore Google Drive authorization status: \(error)")
            return .unknown
        }
    }

    func authorize() async throws -> CloudStorageAccount {
        try await authenticator.authorize()
    }

    func selectLocation(
        for account: CloudStorageAccount?
    ) async throws -> CloudStorageLocationSelection {
        let selection = try await authenticator.authorizeAndSelectFolder(
            accountHint: account,
            folderIDHint: nil
        )
        let session = try await makeSession(for: selection.account)
        let folder = try await session.item(for: selection.folderID)
        guard folder.kind == .folder else {
            throw CloudStorageError.invalidProviderResponse(
                "Google Picker did not return a folder."
            )
        }
        return .selected(account: selection.account, folder: folder)
    }

    func reauthorizeAccess(
        to location: CloudStorageLocation,
        accountHint: CloudStorageAccount?
    ) async throws -> CloudStorageAccount {
        let selection = try await authenticator.authorizeAndSelectFolder(
            accountHint: accountHint,
            folderIDHint: location.rootItemID
        )
        guard selection.folderID == location.rootItemID else {
            throw CloudStorageError.invalidProviderResponse(
                "Select the Google Drive folder previously linked to ExcalidrawZ."
            )
        }
        return selection.account
    }

    func makeSession(for account: CloudStorageAccount) async throws -> any CloudStorageSession {
        guard account.providerID == descriptor.id else {
            throw CloudStorageError.accountUnavailable(account.id)
        }
        _ = try await authenticator.accessToken(for: account.id)
        return GoogleDriveCloudStorageSession(
            account: account,
            tokenProvider: authenticator,
            configuration: configuration
        )
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        try await authenticator.signOut(accountID: accountID)
    }
}
