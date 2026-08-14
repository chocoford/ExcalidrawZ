//
//  GoogleDriveCloudStorageProvider.swift
//  ExcalidrawZ
//

import Foundation
import Logging

struct GoogleDriveCloudStorageProvider: CloudStorageProvider {
    let descriptor = CloudStorageProviderDescriptor(
        id: .googleDrive,
        displayName: "Google Drive",
        capabilities: .readWrite
    )

    private let authenticator: any GoogleDriveAuthenticating
    private let configuration: GoogleDriveConfiguration
    private let logger = Logger(label: "GoogleDriveCloudStorageProvider")

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
        let account = try await authenticator.accountWithRequiredScope(accountHint: account)
        return .browse(account: account)
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
