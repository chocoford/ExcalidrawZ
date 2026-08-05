//
//  CloudStorageConnectionStore.swift
//  ExcalidrawZ
//
//  Persists device-local remote roots while providers keep credentials in Keychain.
//

import Combine
import Foundation
import Logging

@MainActor
final class CloudStorageConnectionStore: ObservableObject {
    static let shared = CloudStorageConnectionStore()

    @Published private(set) var providerDescriptors: [CloudStorageProviderDescriptor] = []
    @Published private(set) var accountsByProvider: [CloudStorageProviderID: [CloudStorageAccount]] = [:]
    @Published private(set) var locations: [CloudStorageLocation]
    @Published private(set) var connectingProviderIDs: Set<CloudStorageProviderID> = []
    @Published private(set) var authenticationRequiredLocationIDs: Set<UUID> = []

    private var missingAccountLocationIDs: Set<UUID> = []
    private var accessFailureLocationIDs: Set<UUID> = []

    private let registry: CloudStorageProviderRegistry
    private let userDefaults: UserDefaults
    private let locationsDefaultsKey = "CloudStorageLocations.v1"
    private let logger = Logger(label: "CloudStorageConnectionStore")
    private var accountRefreshTask: Task<Void, Never>?
    private var accountRefreshTaskID: UUID?
    private var authorizationTasks: [
        CloudStorageProviderID: Task<CloudStorageAccount, Error>
    ] = [:]

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
        if let accountRefreshTask {
            await accountRefreshTask.value
            return
        }

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        accountRefreshTask = task
        accountRefreshTaskID = taskID
        await task.value

        if accountRefreshTaskID == taskID {
            accountRefreshTask = nil
            accountRefreshTaskID = nil
        }
    }

    private func performRefresh() async {
        let descriptors = await registry.registeredProviderDescriptors()
        let registeredProviderIDs = Set(descriptors.map(\.id))
        var refreshedAccounts = accountsByProvider.filter {
            registeredProviderIDs.contains($0.key)
        }

        for descriptor in descriptors {
            guard let provider = try? await registry.provider(withID: descriptor.id) else {
                continue
            }
            switch await provider.authorizationStatus() {
                case .signedIn(let accounts):
                    refreshedAccounts[descriptor.id] = accounts
#if DEBUG
                    logger.debug(
                        "Restored cloud storage accounts provider=\(descriptor.id.rawValue) count=\(accounts.count)"
                    )
#endif
                case .signedOut:
                    refreshedAccounts[descriptor.id] = nil
                    let locationCount = locations(for: descriptor.id).count
                    if locationCount > 0 {
                        logger.warning(
                            "Cloud storage provider has persisted locations but no restored account provider=\(descriptor.id.rawValue) locations=\(locationCount)"
                        )
                    }
                case .unknown:
                    logger.warning(
                        "Unable to determine cloud storage authorization status provider=\(descriptor.id.rawValue)"
                    )
                case .authorizing:
                    break
            }
        }

        providerDescriptors = descriptors
        accountsByProvider = refreshedAccounts

        missingAccountLocationIDs = locations.reduce(into: Set<UUID>()) { result, location in
            let hasMatchingAccount = refreshedAccounts[location.providerID]?.contains {
                $0.id == location.accountID
            } == true
            if !hasMatchingAccount {
                result.insert(location.id)
            }
        }
        publishAuthenticationRequirements()
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
        if let authorizationTask = authorizationTasks[providerID] {
            let account = try await authorizationTask.value
            storeConnectedAccount(account)
            return account
        }

        let provider = try await registry.provider(withID: providerID)
        let authorizationTask = Task { @MainActor in
            try await provider.authorize()
        }
        authorizationTasks[providerID] = authorizationTask
        connectingProviderIDs.insert(providerID)
        defer {
            authorizationTasks[providerID] = nil
            connectingProviderIDs.remove(providerID)
        }

        let account = try await authorizationTask.value
        storeConnectedAccount(account)
        return account
    }

    func selectLocation(
        with providerID: CloudStorageProviderID,
        account: CloudStorageAccount?
    ) async throws -> CloudStorageLocationSelection {
        let provider = try await registry.provider(withID: providerID)
        connectingProviderIDs.insert(providerID)
        defer { connectingProviderIDs.remove(providerID) }

        let selection = try await provider.selectLocation(for: account)
        switch selection {
            case .browse(let account), .selected(let account, _):
                storeConnectedAccount(account)
        }
        return selection
    }

    /// Validates a persisted location before a user-initiated operation. A
    /// missing account or an expired token starts the provider's interactive
    /// authorization flow, while background synchronization remains silent.
    func ensureAccess(to location: CloudStorageLocation) async throws -> CloudStorageAccount {
        await refresh()

        if let account = account(for: location) {
            do {
                _ = try await makeSession(
                    providerID: location.providerID,
                    account: account
                )
                clearAuthenticationRequirement(for: location)
                return account
            } catch where !Self.requiresInteractiveAuthorization(error) {
                throw error
            } catch {
                recordAccessFailure(error, for: location)
            }
        }

        let account = try await connect(to: location.providerID)
        guard account.id == location.accountID else {
            accessFailureLocationIDs.insert(location.id)
            publishAuthenticationRequirements()
            throw CloudStorageError.invalidProviderResponse(
                "Sign in to the account originally used for this linked storage location."
            )
        }
        clearAuthenticationRequirement(for: location)
        return account
    }

    func requiresAuthentication(for location: CloudStorageLocation) -> Bool {
        authenticationRequiredLocationIDs.contains(location.id)
    }

    func recordAccessFailure(_ error: Error, for location: CloudStorageLocation) {
        guard Self.requiresInteractiveAuthorization(error) else { return }
        accessFailureLocationIDs.insert(location.id)
        publishAuthenticationRequirements()
    }

    func clearAuthenticationRequirement(for location: CloudStorageLocation) {
        missingAccountLocationIDs.remove(location.id)
        accessFailureLocationIDs.remove(location.id)
        publishAuthenticationRequirements()
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

        let existingIndex = locations.firstIndex {
            $0.providerID == providerID
                && $0.accountID == account.id
                && $0.rootItemID == folder.id
        }
        let existingLocation = existingIndex.map { locations[$0] }
        let location = CloudStorageLocation(
            id: existingLocation?.id ?? UUID(),
            providerID: providerID,
            accountID: account.id,
            rootItemID: folder.id,
            displayName: folder.parentID == nil || folder.name.isEmpty || folder.name == "root"
                ? providerDescriptors.first(where: { $0.id == providerID })?.displayName
                    ?? "Cloud Storage"
                : folder.name,
            createdAt: existingLocation?.createdAt ?? Date(),
            rootCapabilities: folder.capabilities
        )

        if let index = existingIndex {
            locations[index] = location
        } else {
            locations.append(location)
        }
        persistLocations()
    }

    func removeLocation(_ location: CloudStorageLocation) {
        locations.removeAll { $0.id == location.id }
        missingAccountLocationIDs.remove(location.id)
        accessFailureLocationIDs.remove(location.id)
        publishAuthenticationRequirements()
        persistLocations()
    }

    func disconnect(_ account: CloudStorageAccount) async throws {
        let provider = try await registry.provider(withID: account.providerID)
        try await provider.signOut(accountID: account.id)
        let removedLocationIDs = Set(
            locations
                .filter {
                    $0.providerID == account.providerID && $0.accountID == account.id
                }
                .map(\.id)
        )
        locations.removeAll {
            $0.providerID == account.providerID && $0.accountID == account.id
        }
        accountsByProvider[account.providerID]?.removeAll { $0.id == account.id }
        missingAccountLocationIDs.subtract(removedLocationIDs)
        accessFailureLocationIDs.subtract(removedLocationIDs)
        publishAuthenticationRequirements()
        persistLocations()
    }

    private func persistLocations() {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        userDefaults.set(data, forKey: locationsDefaultsKey)
    }

    private func storeConnectedAccount(_ account: CloudStorageAccount) {
        var accounts = accounts(for: account.providerID)
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        accountsByProvider[account.providerID] = accounts
        let restoredLocationIDs = Set(
            locations
                .filter {
                    $0.providerID == account.providerID && $0.accountID == account.id
                }
                .map(\.id)
        )
        missingAccountLocationIDs.subtract(restoredLocationIDs)
        accessFailureLocationIDs.subtract(restoredLocationIDs)
        publishAuthenticationRequirements()
    }

    private func publishAuthenticationRequirements() {
        authenticationRequiredLocationIDs = missingAccountLocationIDs
            .union(accessFailureLocationIDs)
    }

    private static func requiresInteractiveAuthorization(_ error: Error) -> Bool {
        guard let cloudStorageError = error as? CloudStorageError else {
            return false
        }
        switch cloudStorageError {
            case .authenticationRequired, .accountUnavailable:
                return true
            default:
                return false
        }
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
