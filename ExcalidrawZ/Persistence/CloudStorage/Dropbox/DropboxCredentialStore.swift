//
//  DropboxCredentialStore.swift
//  ExcalidrawZ
//

import Foundation
import Security

struct DropboxCredential: Codable, Sendable {
    let accountID: String
    let displayName: String
    let emailAddress: String?
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var cloudStorageAccount: CloudStorageAccount {
        CloudStorageAccount(
            providerID: .dropbox,
            id: CloudStorageAccountID(rawValue: accountID),
            displayName: displayName,
            emailAddress: emailAddress
        )
    }
}

struct DropboxCredentialStore: Sendable {
    private let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.chocoford.excalidraw") {
        self.service = "\(bundleIdentifier).cloud-storage.dropbox"
    }

    func credentials() throws -> [DropboxCredential] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(serviceQuery.merging([
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
        ]) { _, new in new } as CFDictionary, &result)

        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw keychainError(status) }

        let entries: [[String: Any]]
        if let entry = result as? [String: Any] {
            entries = [entry]
        } else {
            entries = result as? [[String: Any]] ?? []
        }
        let values = entries.compactMap {
            $0[kSecValueData as String] as? Data
        }
        do {
            return try values.map { try JSONDecoder().decode(DropboxCredential.self, from: $0) }
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode stored Dropbox credentials: \(error.localizedDescription)"
            )
        }
    }

    func credential(for accountID: CloudStorageAccountID) throws -> DropboxCredential? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(baseQuery(accountID: accountID).merging([
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]) { _, new in new } as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }
        return try JSONDecoder().decode(DropboxCredential.self, from: data)
    }

    func save(_ credential: DropboxCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(accountID: credential.cloudStorageAccount.id)
        let status = SecItemAdd(query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, new in new } as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else { throw keychainError(updateStatus) }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }
    }

    func remove(accountID: CloudStorageAccountID) throws {
        let status = SecItemDelete(baseQuery(accountID: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func baseQuery(accountID: CloudStorageAccountID) -> [String: Any] {
        serviceQuery.merging([
            kSecAttrAccount as String: accountID.rawValue,
        ]) { _, new in new }
    }

    private var serviceQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
#if os(macOS)
        // kSecAttrAccessible-backed items use the data protection keychain on macOS.
        query[kSecUseDataProtectionKeychain as String] = true
#endif
        return query
    }

    private func keychainError(_ status: OSStatus) -> CloudStorageError {
        let message = SecCopyErrorMessageString(status, nil) as String?
            ?? "Keychain error \(status)"
        return .transport("\(message) (OSStatus \(status))")
    }
}
