//
//  BoxAuthentication.swift
//  ExcalidrawZ
//

import Foundation

protocol BoxAccessTokenProviding: Sendable {
    func accessToken(for accountID: CloudStorageAccountID) async throws -> String
}

protocol BoxAuthenticating: BoxAccessTokenProviding {
    func accounts() async throws -> [CloudStorageAccount]
    func authorize() async throws -> CloudStorageAccount
    func signOut(accountID: CloudStorageAccountID) async throws
}
