//
//  DropboxAuthentication.swift
//  ExcalidrawZ
//

import Foundation

protocol DropboxAccessTokenProviding: Sendable {
    func accessToken(for accountID: CloudStorageAccountID) async throws -> String
}

protocol DropboxAuthenticating: DropboxAccessTokenProviding {
    func accounts() async throws -> [CloudStorageAccount]
    func authorize() async throws -> CloudStorageAccount
    func signOut(accountID: CloudStorageAccountID) async throws
}
