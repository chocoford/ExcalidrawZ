//
//  OneDriveAuthentication.swift
//  ExcalidrawZ
//

import Foundation

protocol OneDriveAccessTokenProviding: Sendable {
    func accessToken(for accountID: CloudStorageAccountID) async throws -> String
}

protocol OneDriveAuthenticating: OneDriveAccessTokenProviding {
    func accounts() async throws -> [CloudStorageAccount]
    func authorize() async throws -> CloudStorageAccount
    func signOut(accountID: CloudStorageAccountID) async throws
}
