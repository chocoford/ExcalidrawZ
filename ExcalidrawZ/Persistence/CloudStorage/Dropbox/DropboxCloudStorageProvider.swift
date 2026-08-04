//
//  DropboxCloudStorageProvider.swift
//  ExcalidrawZ
//

import Foundation
import Logging

struct DropboxCloudStorageProvider: CloudStorageProvider {
    let descriptor = CloudStorageProviderDescriptor(
        id: .dropbox,
        displayName: "Dropbox",
        capabilities: [.readWrite, .deltaChanges]
    )

    private let authenticator: any DropboxAuthenticating
    private let configuration: DropboxConfiguration
    private let logger = Logger(label: "DropboxCloudStorageProvider")

    init(
        authenticator: any DropboxAuthenticating,
        configuration: DropboxConfiguration
    ) {
        self.authenticator = authenticator
        self.configuration = configuration
    }

    func authorizationStatus() async -> CloudStorageAuthorizationStatus {
        do {
            let accounts = try await authenticator.accounts()
            return accounts.isEmpty ? .signedOut : .signedIn(accounts: accounts)
        } catch {
            logger.error("Unable to restore Dropbox authorization status: \(error)")
            return .unknown
        }
    }

    func authorize() async throws -> CloudStorageAccount {
        try await authenticator.authorize()
    }

    func makeSession(for account: CloudStorageAccount) async throws -> any CloudStorageSession {
        guard account.providerID == descriptor.id else {
            throw CloudStorageError.accountUnavailable(account.id)
        }
        _ = try await authenticator.accessToken(for: account.id)
        return DropboxCloudStorageSession(
            account: account,
            tokenProvider: authenticator,
            configuration: configuration
        )
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        try await authenticator.signOut(accountID: accountID)
    }
}
