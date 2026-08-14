//
//  GoogleDriveAuthentication.swift
//  ExcalidrawZ
//

import Foundation

protocol GoogleDriveAccessTokenProviding: Sendable {
    func accessToken(for accountID: CloudStorageAccountID) async throws -> String
}

protocol GoogleDriveAuthenticating: GoogleDriveAccessTokenProviding {
    func accounts() async throws -> [CloudStorageAccount]
    func authorize() async throws -> CloudStorageAccount
    func accountWithRequiredScope(
        accountHint: CloudStorageAccount?
    ) async throws -> CloudStorageAccount
    func signOut(accountID: CloudStorageAccountID) async throws
}
