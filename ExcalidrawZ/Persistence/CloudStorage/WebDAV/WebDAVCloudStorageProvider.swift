//
//  WebDAVCloudStorageProvider.swift
//  ExcalidrawZ
//

import Foundation
import Logging

struct WebDAVCloudStorageProvider: CloudStorageProvider {
    let descriptor = CloudStorageProviderDescriptor(
        id: .webDAV,
        displayName: "WebDAV",
        capabilities: .readWrite,
        connectionMethod: .serverCredentials
    )

    private let authenticator: any WebDAVAuthenticating
    private let logger = Logger(label: "WebDAVCloudStorageProvider")

    init(authenticator: any WebDAVAuthenticating) {
        self.authenticator = authenticator
    }

    func authorizationStatus() async -> CloudStorageAuthorizationStatus {
        do {
            let accounts = try await authenticator.accounts()
            return accounts.isEmpty ? .signedOut : .signedIn(accounts: accounts)
        } catch {
            logger.error("Unable to restore WebDAV authorization status: \(error)")
            return .unknown
        }
    }

    func authorize() async throws -> CloudStorageAccount {
        throw CloudStorageError.authenticationRequired
    }

    func authorize(
        using connectionInput: CloudStorageConnectionInput?
    ) async throws -> CloudStorageAccount {
        guard case .serverCredentials(let credentials) = connectionInput else {
            throw CloudStorageError.authenticationRequired
        }
        return try await authenticator.authorize(with: credentials)
    }

    func makeSession(for account: CloudStorageAccount) async throws -> any CloudStorageSession {
        guard account.providerID == descriptor.id else {
            throw CloudStorageError.accountUnavailable(account.id)
        }
        let credential = try await authenticator.credential(for: account.id)
        return WebDAVCloudStorageSession(
            account: account,
            credential: credential
        )
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        try await authenticator.signOut(accountID: accountID)
    }
}

