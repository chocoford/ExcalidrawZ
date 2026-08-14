//
//  WebDAVCredentialStore.swift
//  ExcalidrawZ
//

import Foundation
import Security

struct WebDAVCredential: Codable, Sendable {
    let accountID: String
    let displayName: String
    let serverURL: URL
    let username: String
    let password: String
    let service: WebDAVService?

    init(
        accountID: String,
        displayName: String,
        serverURL: URL,
        username: String,
        password: String,
        service: WebDAVService? = nil
    ) {
        self.accountID = accountID
        self.displayName = displayName
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.service = service
    }

    var cloudStorageAccount: CloudStorageAccount {
        CloudStorageAccount(
            providerID: .webDAV,
            id: CloudStorageAccountID(rawValue: accountID),
            displayName: WebDAVServiceIdentity.accountDisplayName(
                serverURL: serverURL,
                username: username,
                detectedService: service
            ),
            emailAddress: nil
        )
    }
}

struct WebDAVCredentialStore: Sendable {
    private let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.chocoford.excalidraw") {
        self.service = "\(bundleIdentifier).cloud-storage.webdav"
    }

    func credentials() throws -> [WebDAVCredential] {
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
                .map { try JSONDecoder().decode(WebDAVCredential.self, from: $0) }
        } catch {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to decode stored WebDAV credentials: \(error.localizedDescription)"
            )
        }
    }

    func credential(for accountID: CloudStorageAccountID) throws -> WebDAVCredential? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(baseQuery(accountID: accountID).merging([
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]) { _, new in new } as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }
        return try JSONDecoder().decode(WebDAVCredential.self, from: data)
    }

    func save(_ credential: WebDAVCredential) throws {
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
