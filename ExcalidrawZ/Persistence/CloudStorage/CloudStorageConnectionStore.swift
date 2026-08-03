//
//  CloudStorageConnectionStore.swift
//  ExcalidrawZ
//
//  Persists device-local remote roots while providers keep credentials in Keychain.
//

import Combine
import Foundation

@MainActor
final class CloudStorageConnectionStore: ObservableObject {
    static let shared = CloudStorageConnectionStore()

    @Published private(set) var providerDescriptors: [CloudStorageProviderDescriptor] = []
    @Published private(set) var accountsByProvider: [CloudStorageProviderID: [CloudStorageAccount]] = [:]
    @Published private(set) var locations: [CloudStorageLocation]
    @Published private(set) var connectingProviderIDs: Set<CloudStorageProviderID> = []

    private let registry: CloudStorageProviderRegistry
    private let userDefaults: UserDefaults
    private let locationsDefaultsKey = "CloudStorageLocations.v1"

    init(
        registry: CloudStorageProviderRegistry = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.registry = registry
        self.userDefaults = userDefaults
        self.locations = Self.loadLocations(
            from: userDefaults,
            key: locationsDefaultsKey
        )
    }

    func refresh() async {
        let descriptors = await registry.registeredProviderDescriptors()
        var refreshedAccounts: [CloudStorageProviderID: [CloudStorageAccount]] = [:]

        for descriptor in descriptors {
            guard let provider = try? await registry.provider(withID: descriptor.id) else {
                continue
            }
            if case .signedIn(let accounts) = await provider.authorizationStatus() {
                refreshedAccounts[descriptor.id] = accounts
            }
        }

        providerDescriptors = descriptors
        accountsByProvider = refreshedAccounts
    }

    func accounts(for providerID: CloudStorageProviderID) -> [CloudStorageAccount] {
        accountsByProvider[providerID] ?? []
    }

    func locations(for providerID: CloudStorageProviderID) -> [CloudStorageLocation] {
        locations
            .filter { $0.providerID == providerID }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    func account(for location: CloudStorageLocation) -> CloudStorageAccount? {
        accounts(for: location.providerID).first { $0.id == location.accountID }
    }

    func connect(to providerID: CloudStorageProviderID) async throws -> CloudStorageAccount {
        let provider = try await registry.provider(withID: providerID)
        connectingProviderIDs.insert(providerID)
        defer { connectingProviderIDs.remove(providerID) }

        let account = try await provider.authorize()
        var accounts = accounts(for: providerID)
        if !accounts.contains(where: { $0.id == account.id }) {
            accounts.append(account)
        }
        accountsByProvider[providerID] = accounts
        return account
    }

    func makeSession(
        providerID: CloudStorageProviderID,
        account: CloudStorageAccount
    ) async throws -> any CloudStorageSession {
        let provider = try await registry.provider(withID: providerID)
        return try await provider.makeSession(for: account)
    }

    func saveLocation(
        providerID: CloudStorageProviderID,
        account: CloudStorageAccount,
        folder: CloudStorageItem
    ) {
        guard folder.kind == .folder else { return }

        let location = CloudStorageLocation(
            providerID: providerID,
            accountID: account.id,
            rootItemID: folder.id,
            displayName: folder.parentID == nil || folder.name.isEmpty || folder.name == "root"
                ? providerDescriptors.first(where: { $0.id == providerID })?.displayName
                    ?? "Cloud Storage"
                : folder.name
        )

        if let index = locations.firstIndex(where: {
            $0.providerID == providerID
                && $0.accountID == account.id
                && $0.rootItemID == folder.id
        }) {
            locations[index] = location
        } else {
            locations.append(location)
        }
        persistLocations()
    }

    func removeLocation(_ location: CloudStorageLocation) {
        locations.removeAll { $0.id == location.id }
        persistLocations()
    }

    func disconnect(_ account: CloudStorageAccount) async throws {
        let provider = try await registry.provider(withID: account.providerID)
        try await provider.signOut(accountID: account.id)
        locations.removeAll {
            $0.providerID == account.providerID && $0.accountID == account.id
        }
        accountsByProvider[account.providerID]?.removeAll { $0.id == account.id }
        persistLocations()
    }

    private func persistLocations() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        userDefaults.set(data, forKey: locationsDefaultsKey)
    }

    private static func loadLocations(
        from userDefaults: UserDefaults,
        key: String
    ) -> [CloudStorageLocation] {
        guard let data = userDefaults.data(forKey: key),
              let locations = try? JSONDecoder().decode([CloudStorageLocation].self, from: data) else {
            return []
        }
        return locations
    }
}
