//
//  WebDAVAuthenticator.swift
//  ExcalidrawZ
//

import CryptoKit
import Foundation

actor WebDAVAuthenticator: WebDAVAuthenticating {
    private let credentialStore: WebDAVCredentialStore

    init(credentialStore: WebDAVCredentialStore = WebDAVCredentialStore()) {
        self.credentialStore = credentialStore
    }

    func accounts() async throws -> [CloudStorageAccount] {
        try credentialStore.credentials().map(\.cloudStorageAccount)
    }

    func authorize(
        with credentials: CloudStorageServerCredentials
    ) async throws -> CloudStorageAccount {
        let suppliedServerURL = try WebDAVURL.normalizedServerURL(credentials.serverURL)
        let username = credentials.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !credentials.password.isEmpty else {
            throw CloudStorageError.invalidProviderResponse(
                "Enter a WebDAV username and password."
            )
        }

        let provisionalAccountID = Self.accountID(
            serverURL: suppliedServerURL,
            username: username
        )
        let knownService = WebDAVServiceIdentity.service(for: suppliedServerURL)
        let provisionalCredential = WebDAVCredential(
            accountID: provisionalAccountID.rawValue,
            displayName: Self.displayName(
                serverURL: suppliedServerURL,
                username: username,
                service: knownService
            ),
            serverURL: suppliedServerURL,
            username: username,
            password: credentials.password,
            service: knownService
        )

        let client = WebDAVClient(credential: provisionalCredential)
        let resolution = try await client.resolveEndpoint(from: suppliedServerURL)
        let serverURL = resolution.serverURL
        let accountID = Self.accountID(serverURL: serverURL, username: username)
        let detectedService = await client.detectService(
            at: serverURL,
            webDAVResponse: resolution.inspection.response
        )
        let credential = WebDAVCredential(
            accountID: accountID.rawValue,
            displayName: Self.displayName(
                serverURL: serverURL,
                username: username,
                service: detectedService
            ),
            serverURL: serverURL,
            username: username,
            password: credentials.password,
            service: detectedService
        )
        try credentialStore.save(credential)
        return credential.cloudStorageAccount
    }

    func credential(for accountID: CloudStorageAccountID) async throws -> WebDAVCredential {
        guard let credential = try credentialStore.credential(for: accountID) else {
            throw CloudStorageError.authenticationRequired
        }
        return credential
    }

    func signOut(accountID: CloudStorageAccountID) async throws {
        try credentialStore.remove(accountID: accountID)
    }

    private static func accountID(serverURL: URL, username: String) -> CloudStorageAccountID {
        let source = Data("\(serverURL.absoluteString)\n\(username.lowercased())".utf8)
        let digest = SHA256.hash(data: source)
        return CloudStorageAccountID(rawValue: digest.map { String(format: "%02x", $0) }.joined())
    }

    private static func displayName(
        serverURL: URL,
        username: String,
        service: WebDAVService?
    ) -> String {
        WebDAVServiceIdentity.accountDisplayName(
            serverURL: serverURL,
            username: username,
            detectedService: service
        )
    }
}
