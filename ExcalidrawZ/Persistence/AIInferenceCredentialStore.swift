import Foundation
import Security

protocol AIInferenceKeyStoring {
    func readKey(for account: String) throws -> String?
    func saveKey(_ key: String, for account: String) throws
    func removeKey(for account: String) throws
}

/// Device-local storage, separate from synced preferences and conversation persistence.
struct AIInferenceCredentialStore: AIInferenceKeyStoring {
    private let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.chocoford.excalidraw") {
        service = "\(bundleIdentifier).ai-inference"
    }

    func readKey(for account: String) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(account: account).merging([
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]) { _, new in new } as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw AIInferenceBillingError.keychain(status)
        }
        return key
    }

    func saveKey(_ key: String, for account: String) throws {
        let data = Data(key.utf8)
        let query = query(account: account)
        let status = SecItemAdd(query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw AIInferenceBillingError.keychain(updateStatus)
            }
        } else if status != errSecSuccess {
            throw AIInferenceBillingError.keychain(status)
        }
    }

    func removeKey(for account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIInferenceBillingError.keychain(status)
        }
    }

    private func query(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
#if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
#endif
        return query
    }
}
