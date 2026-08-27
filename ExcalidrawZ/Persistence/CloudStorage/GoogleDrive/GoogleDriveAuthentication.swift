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
    func authorizeAndSelectFolder(
        accountHint: CloudStorageAccount?,
        folderIDHint: CloudStorageItemID?
    ) async throws -> GoogleDriveFolderAuthorization
    func signOut(accountID: CloudStorageAccountID) async throws
}

struct GoogleDriveFolderAuthorization: Sendable {
    let account: CloudStorageAccount
    let folderID: CloudStorageItemID
}
