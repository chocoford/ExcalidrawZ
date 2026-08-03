//
//  OneDriveCloudStorageProvider.swift
//  ExcalidrawZ
//

import Foundation

struct OneDriveCloudStorageProvider: CloudStorageProvider {
    let descriptor = CloudStorageProviderDescriptor(
        id: .microsoftOneDrive,
        displayName: "OneDrive",
        capabilities: [.readWrite, .deltaChanges]
    )

    private let authenticator: any OneDriveAuthenticating

    init(authenticator: any OneDriveAuthenticating) {
        self.authenticator = authenticator
    }

    func authorizationStatus() async -> CloudStorageAuthorizationStatus {
        do {
            let accounts = try await authenticator.accounts()
            return accounts.isEmpty ? .signedOut : .signedIn(accounts: accounts)
        } catch {
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
        return OneDriveCloudStorageSession(
            account: account,
            tokenProvider: authenticator
        )
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        try await authenticator.signOut(accountID: accountID)
    }
}
