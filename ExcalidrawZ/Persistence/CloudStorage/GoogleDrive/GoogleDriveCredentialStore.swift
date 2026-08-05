//
//  GoogleDriveCredentialStore.swift
//  ExcalidrawZ
//

import Foundation
import Security

struct GoogleDriveCredential: Codable, Sendable {
    let accountID: String
    let displayName: String
    let emailAddress: String?
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    /// Nil identifies credentials created before ExcalidrawZ requested full
    /// Drive access. Those credentials must be upgraded interactively.
    let grantedScopes: Set<String>?

    var hasRequiredScope: Bool {
        grantedScopes?.contains(GoogleDriveConfiguration.driveScope) == true
    }

    var cloudStorageAccount: CloudStorageAccount {
        CloudStorageAccount(
            providerID: .googleDrive,
            id: CloudStorageAccountID(rawValue: accountID),
            displayName: displayName,
            emailAddress: emailAddress
        )
    }
}

struct GoogleDriveCredentialStore: Sendable {
    private let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.chocoford.excalidraw") {
        self.service = "\(bundleIdentifier).cloud-storage.google-drive"
    }

    func credentials() throws -> [GoogleDriveCredential] {
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
        do {
            return try entries
                .compactMap { $0[kSecValueData as String] as? Data }
                .map { try JSONDecoder().decode(GoogleDriveCredential.self, from: $0) }
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode stored Google Drive credentials: \(error.localizedDescription)"
            )
        }
    }

    func credential(for accountID: CloudStorageAccountID) throws -> GoogleDriveCredential? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(baseQuery(accountID: accountID).merging([
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]) { _, new in new } as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }
        return try JSONDecoder().decode(GoogleDriveCredential.self, from: data)
    }

    func save(_ credential: GoogleDriveCredential) throws {
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
