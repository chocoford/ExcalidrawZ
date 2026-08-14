//
//  BoxCloudStorageProvider.swift
//  ExcalidrawZ
//

import Foundation

struct BoxCloudStorageProvider: CloudStorageProvider {
    let descriptor = CloudStorageProviderDescriptor(
        id: .box,
        displayName: "Box",
        capabilities: [.readWrite, .deltaChanges]
    )

    private let authenticator: any BoxAuthenticating
    private let configuration: BoxConfiguration

    init(
        authenticator: any BoxAuthenticating,
        configuration: BoxConfiguration
    ) {
        self.authenticator = authenticator
        self.configuration = configuration
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
        return BoxCloudStorageSession(
            account: account,
            tokenProvider: authenticator,
            configuration: configuration
        )
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        try await authenticator.signOut(accountID: accountID)
    }
}
