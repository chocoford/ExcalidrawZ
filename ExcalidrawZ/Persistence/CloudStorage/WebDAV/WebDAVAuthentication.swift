//
//  WebDAVAuthentication.swift
//  ExcalidrawZ
//

import Foundation

protocol WebDAVAuthenticating: Sendable {
    func accounts() async throws -> [CloudStorageAccount]
    func authorize(
        with credentials: CloudStorageServerCredentials
    ) async throws -> CloudStorageAccount
    func credential(for accountID: CloudStorageAccountID) async throws -> WebDAVCredential
    func signOut(accountID: CloudStorageAccountID) async throws
}

