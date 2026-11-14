import Foundation
import Combine
import LLMKit
import LLMCore

enum AIInferenceBillingMode: String, CaseIterable, Identifiable, Sendable {
    case platform
    case byok

    var id: Self { self }
}

enum AIInferenceIntegrationMode: String, CaseIterable, Identifiable, Sendable {
    case basic
    case optimized

    var id: Self { self }
}

enum AIInferenceBillingError: LocalizedError {
    case missingConnection
    case missingKey
    case invalidKey
    case settingsBusy
    case selectionChanged
    case invalidBillingMode
    case invalidConfiguration
    case incompatibleModel
    case missingModel
    case managedInferenceUnavailable
    case keychain(Int32)

    var errorDescription: String? {
        switch self {
            case .missingConnection:
                String(localizable: .aiBYOKSelectConnection)
            case .missingKey:
                String(localizable: .aiBYOKMissingKey)
            case .invalidKey:
                String(localizable: .aiBYOKInvalidKey)
            case .settingsBusy:
                String(localizable: .aiBYOKSettingsBusy)
            case .selectionChanged:
                String(localizable: .aiBYOKSelectionChanged)
            case .invalidBillingMode:
                String(localizable: .aiBYOKBillingSelectionRequired)
            case .invalidConfiguration:
                String(localizable: .aiBYOKInvalidConfiguration)
            case .incompatibleModel:
                String(localizable: .aiBYOKIncompatibleModel)
            case .missingModel:
                String(localizable: .aiBYOKMissingModel)
            case .managedInferenceUnavailable:
                String(localizable: .aiBYOKManagedServiceAppStoreOnly)
            case .keychain:
                String(localizable: .aiBYOKKeychainError)
        }
    }
}

@MainActor
final class AIInferenceBillingState: ObservableObject {
    static let shared = AIInferenceBillingState()
    nonisolated static let modeDefaultsKey = "AIChat.inferenceBillingMode"
    static let profilesDefaultsKey = "AIChat.byokConnectionProfiles"
    static let modelOverridesDefaultsKey = "AIChat.byokConversationModels"
    nonisolated static let integrationModeDefaultsKey = "AIChat.byokIntegrationMode"
    // Read only when migrating the original single-connection settings.
    static let connectionDefaultsKey = "AIChat.byokConnection"
    static let configurationsDefaultsKey = "AIChat.byokConfigurations"

    private struct SavedConnections: Codable {
        var profiles: [AIInferenceConnectionProfile]
        var selectedID: String?
    }

    @Published private(set) var mode: AIInferenceBillingMode
    @Published private(set) var integrationMode: AIInferenceIntegrationMode
    @Published private(set) var profiles: [AIInferenceConnectionProfile]
    @Published private(set) var selectedProfileID: String?
    @Published private(set) var hasStoredKey = false
    @Published private(set) var isKeychainUnavailable = false
    @Published private(set) var keyRevision = 0
    @Published private(set) var modelCatalogRevision = 0
    @Published private(set) var activeOperationCount = 0
    @Published private(set) var requiresBillingSelection: Bool
    @Published private(set) var configurationLoadFailed: Bool
    @Published private(set) var conversationModels: [String: [String: String]]

    var usesBYOK: Bool { mode == .byok }
    var isBusy: Bool { activeOperationCount > 0 }
    var selectedProfile: AIInferenceConnectionProfile? { profiles.first { $0.id == selectedProfileID } }
    var configuration: LLMBYOKConfiguration? {
        configurationLoadFailed ? nil : selectedProfile?.configuration
    }

    private let defaults: UserDefaults
    private let keyStore: any AIInferenceKeyStoring
    private let supportsManagedInference: Bool

    init(
        defaults: UserDefaults = .standard,
        keyStore: any AIInferenceKeyStoring = AIInferenceCredentialStore(),
        supportsManagedInference: Bool = AIChatAvailability.supportsManagedInference
    ) {
        self.defaults = defaults
        self.keyStore = keyStore
        self.supportsManagedInference = supportsManagedInference
        let storedMode = defaults.string(forKey: Self.modeDefaultsKey)
        // Existing BYOK connections keep their backend route until explicitly changed.
        let initialIntegration: AIInferenceIntegrationMode
        if !supportsManagedInference {
            initialIntegration = .basic
        } else if let savedIntegration = defaults.string(forKey: Self.integrationModeDefaultsKey) {
            // Unknown routes must not opt a connection into the backend transport.
            initialIntegration = AIInferenceIntegrationMode(rawValue: savedIntegration) ?? .basic
        } else {
            let hasLegacyConnection = storedMode == "byok" || storedMode == "openRouter"
                || defaults.object(forKey: Self.profilesDefaultsKey) != nil
                || defaults.object(forKey: Self.configurationsDefaultsKey) != nil
                || defaults.string(forKey: Self.connectionDefaultsKey) != nil
            initialIntegration = hasLegacyConnection ? .optimized : .basic
        }
        integrationMode = initialIntegration
        defaults.set(initialIntegration.rawValue, forKey: Self.integrationModeDefaultsKey)
        let decodedMode: AIInferenceBillingMode? = storedMode == "openRouter"
            ? .byok : storedMode.flatMap(AIInferenceBillingMode.init(rawValue:))
        let initialMode = decodedMode ?? .platform
        mode = initialMode
        requiresBillingSelection = (storedMode != nil && decodedMode == nil)
            || (!supportsManagedInference && initialMode != .byok)
        conversationModels = defaults.dictionary(forKey: Self.modelOverridesDefaultsKey) as? [String: [String: String]] ?? [:]
        profiles = []
        configurationLoadFailed = false
        if let stored = defaults.object(forKey: Self.profilesDefaultsKey) {
            if let data = stored as? Data,
               let saved = try? JSONDecoder().decode(SavedConnections.self, from: data),
               Set(saved.profiles.map(\.id)).count == saved.profiles.count,
               saved.profiles.allSatisfy({ !$0.id.isEmpty }),
               saved.selectedID == nil || saved.profiles.contains(where: { $0.id == saved.selectedID }) {
                profiles = saved.profiles
                selectedProfileID = saved.selectedID
            } else {
                configurationLoadFailed = true
            }
        } else {
            migrateLegacyConnections(storedMode: storedMode)
        }
        upgradeMiniMaxModelDiscovery()
        refreshKeyStatus()
    }

    func setMode(_ mode: AIInferenceBillingMode) throws {
        guard mode != .platform || supportsManagedInference else {
            throw AIInferenceBillingError.managedInferenceUnavailable
        }
        guard mode != self.mode || requiresBillingSelection else { return }
        try requireIdle()
        defaults.set(mode.rawValue, forKey: Self.modeDefaultsKey)
        self.mode = mode
        requiresBillingSelection = false
        modelCatalogRevision += 1
    }

    func setIntegrationMode(_ integrationMode: AIInferenceIntegrationMode) throws {
        guard integrationMode != .optimized || supportsManagedInference else {
            throw AIInferenceBillingError.managedInferenceUnavailable
        }
        guard integrationMode != self.integrationMode else { return }
        try requireIdle()
        defaults.set(integrationMode.rawValue, forKey: Self.integrationModeDefaultsKey)
        self.integrationMode = integrationMode
        modelCatalogRevision += 1
    }

    /// A request option on this saved connection; never changes its key or model.
    func setWebSearch(_ enabled: Bool, connectionID: String,
                      prepare: @MainActor (LLMBYOKConfiguration) async throws -> Void = { _ in }) async throws {
        try requireIdle()
        let profile = try profile(for: connectionID)
        guard let previous = profile.configuration, let supported = profile.webSearchConfiguration else {
            throw AIInferenceBillingError.invalidConfiguration
        }
        let configuration = try supported.withWebSearch(enabled: enabled)
        try configuration.validate()
        guard configuration != previous else { return }
        try await withInferenceOperation {
            // A Direct state's client has immutable options. Restore its replacement before
            // publishing the preference so the visible chat never loses its history.
            try await prepare(configuration)
            var updated = profiles
            guard let index = updated.firstIndex(where: { $0.id == connectionID }),
                  updated[index].configuration == previous else { throw AIInferenceBillingError.selectionChanged }
            updated[index].configuration = configuration
            try persistProfiles(updated, selectedID: selectedProfileID)
            modelCatalogRevision += 1
        }
    }

    @discardableResult
    func addConnection(
        _ provider: AIInferenceConnection,
        name: String = "",
        configuration: LLMBYOKConfiguration? = nil,
        apiKey: String? = nil
    ) throws -> AIInferenceConnectionProfile {
        try requireIdle()
        let configuration = configuration ?? provider.presetConfiguration
        try configuration?.validate()
        let key = try apiKey.map(Self.validatedKey)
        if key != nil, configuration == nil { throw AIInferenceBillingError.invalidConfiguration }
        let names = Set(profiles.map(\.displayName))
        let requestedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = requestedName.isEmpty ? provider.title : requestedName
        var suffix = 2
        while requestedName.isEmpty, names.contains(name) {
            name = "\(provider.title) \(suffix)"
            suffix += 1
        }
        let profile = AIInferenceConnectionProfile(
            id: UUID().uuidString, name: name, provider: provider,
            configuration: configuration
        )
        let updated = profiles + [profile]
        let data = try JSONEncoder().encode(SavedConnections(profiles: updated, selectedID: profile.id))
        // Publish the connection only after its key has been stored successfully.
        if let key { try keyStore.saveKey(key, for: profile.id) }
        defaults.set(data, forKey: Self.profilesDefaultsKey)
        profiles = updated
        selectedProfileID = profile.id
        configurationLoadFailed = false
        refreshKeyStatus()
        modelCatalogRevision += 1
        return profile
    }

    func selectConnection(_ id: String) throws {
        try requireIdle()
        guard profiles.contains(where: { $0.id == id }) else { throw AIInferenceBillingError.missingConnection }
        guard id != selectedProfileID else { return }
        try persistProfiles(profiles, selectedID: id)
        refreshKeyStatus()
        keyRevision += 1
        modelCatalogRevision += 1
    }

    func updateConnection(
        _ id: String,
        name: String,
        configuration: LLMBYOKConfiguration,
        apiKey: String
    ) throws {
        try requireIdle()
        try configuration.validate()
        let key = try Self.validatedKey(apiKey)
        var updated = profiles
        guard let index = updated.firstIndex(where: { $0.id == id }) else {
            throw AIInferenceBillingError.missingConnection
        }
        let endpointChanged = updated[index].configuration?.baseURL != configuration.baseURL
        updated[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated[index].configuration = configuration
        if endpointChanged { updated[index].lastModelID = nil }
        let data = try JSONEncoder().encode(SavedConnections(profiles: updated, selectedID: selectedProfileID))
        try keyStore.saveKey(key, for: id)
        defaults.set(data, forKey: Self.profilesDefaultsKey)
        profiles = updated
        if endpointChanged {
            conversationModels[id] = nil
            defaults.set(conversationModels, forKey: Self.modelOverridesDefaultsKey)
        }
        didChangeKey()
    }

    func removeConnection(_ id: String) throws {
        try requireIdle()
        guard profiles.contains(where: { $0.id == id }) else { throw AIInferenceBillingError.missingConnection }
        try keyStore.removeKey(for: id)
        // Removing an active account requires another explicit choice, never a billing fallback.
        try persistProfiles(profiles.filter { $0.id != id }, selectedID: selectedProfileID == id ? nil : selectedProfileID)
        conversationModels[id] = nil
        defaults.set(conversationModels, forKey: Self.modelOverridesDefaultsKey)
        refreshKeyStatus()
        keyRevision += 1
        modelCatalogRevision += 1
    }

    func saveKey(_ value: String, profileID: String? = nil) throws {
        try requireIdle()
        let profile = try profile(for: profileID)
        guard let configuration = profile.configuration else { throw AIInferenceBillingError.invalidConfiguration }
        try configuration.validate()
        try keyStore.saveKey(Self.validatedKey(value), for: profile.id)
        didChangeKey()
    }

    func removeKey(profileID: String? = nil) throws {
        try requireIdle()
        try keyStore.removeKey(for: profile(for: profileID).id)
        didChangeKey()
    }

    func refreshKeyStatus() {
        guard let selectedProfileID else {
            hasStoredKey = false
            isKeychainUnavailable = false
            return
        }
        do {
            hasStoredKey = try keyStore.readKey(for: selectedProfileID) != nil
            isKeychainUnavailable = false
        } catch {
            hasStoredKey = false
            isKeychainUnavailable = true
        }
    }

    func keyForEditing(profileID: String? = nil) throws -> String {
        try keyStore.readKey(for: profile(for: profileID).id) ?? ""
    }

    func resolveSelection() throws -> AIInferenceBillingSelection {
        guard !requiresBillingSelection else { throw AIInferenceBillingError.invalidBillingMode }
        guard usesBYOK else { return .platform }
        guard !configurationLoadFailed else { throw AIInferenceBillingError.invalidConfiguration }
        let profile = try profile()
        guard var configuration = profile.configuration else { throw AIInferenceBillingError.invalidConfiguration }
        try configuration.validate()
        guard let storedKey = try keyStore.readKey(for: profile.id) else { throw AIInferenceBillingError.missingKey }
        // Snapshot the most recently chosen chat model for independent child requests.
        configuration.defaultModel = profile.lastModelID
        configuration.options.auxiliaryModel = nil
        // The saved search switch belongs to Basic Direct, not server-enhanced calls.
        configuration.webSearch?.isEnabled = false
        return .byok(LLMBYOKCredentials(configuration: configuration, apiKey: try Self.validatedKey(storedKey)))
    }

    func saveConfiguration(_ configuration: LLMCore.LLMBYOKConfiguration, profileID: String? = nil) throws {
        try requireIdle()
        try configuration.validate()
        let profile = try profile(for: profileID)
        var updated = profiles
        guard let index = updated.firstIndex(where: { $0.id == profile.id }) else { throw AIInferenceBillingError.missingConnection }
        var configuration = configuration
        configuration.defaultModel = nil
        configuration.options.auxiliaryModel = nil
        updated[index].configuration = configuration
        if profile.configuration?.baseURL != configuration.baseURL {
            // A key saved for one endpoint must never be reused for a changed endpoint.
            try removeKey(profileID: profile.id)
            updated[index].lastModelID = nil
            conversationModels[profile.id] = nil
            defaults.set(conversationModels, forKey: Self.modelOverridesDefaultsKey)
        }
        try persistProfiles(updated, selectedID: selectedProfileID)
        if profile.configuration != configuration { modelCatalogRevision += 1 }
    }

    func modelDiscoveryProvider(profileID: String? = nil) throws -> LLMBYOKProvider {
        guard !configurationLoadFailed else { throw AIInferenceBillingError.invalidConfiguration }
        if profileID == nil {
            guard !requiresBillingSelection, usesBYOK else { throw AIInferenceBillingError.invalidConfiguration }
        }
        let profile = try profile(for: profileID)
        guard let configuration = profile.configuration else { throw AIInferenceBillingError.invalidConfiguration }
        try configuration.validate()
        guard configuration.modelDiscovery != nil else { throw LLMBYOKConfigurationError.modelDiscoveryUnsupported }
        guard let storedKey = try keyStore.readKey(for: profile.id) else { throw AIInferenceBillingError.missingKey }
        let key = try Self.validatedKey(storedKey)
        return LLMBYOKProvider(configuration: configuration, apiKeyProvider: { key })
    }

    func modelID(for conversationID: String?) -> String? {
        guard let profile = selectedProfile else { return nil }
        if let conversationID, let model = conversationModels[profile.id]?[conversationID] { return model }
        return profile.lastModelID
    }

    var savedModelIDs: [String] { savedModelIDs(profileID: selectedProfileID) }

    func savedModelIDs(profileID: String?) -> [String] {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return [] }
        return Array(Set(Array(conversationModels[profile.id, default: [:]].values)
            + [profile.lastModelID].compactMap { $0 })).sorted()
    }

    func modelForChat(conversationID: String? = nil, overridingModelID: String? = nil,
                      profileID: String? = nil) throws -> SupportedModel {
        let profile = try profile(for: profileID)
        let saved = conversationID.flatMap { conversationModels[profile.id]?[$0] }
        guard let id = overridingModelID ?? saved ?? profile.lastModelID else { throw AIInferenceBillingError.missingModel }
        return try modelForRoute(connectionID: profile.id, modelID: id)
    }

    /// Chat is the only model picker; remember its last choice per saved connection.
    func setModel(_ id: String, for conversationID: String? = nil) throws {
        try requireIdle()
        let model = try validatedModel(id)
        let profile = try profile()
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.id == profile.id }) { updated[index].lastModelID = model.rawValue }
        try persistProfiles(updated, selectedID: selectedProfileID)
        if let conversationID {
            conversationModels[profile.id, default: [:]][conversationID] = model.rawValue
            defaults.set(conversationModels, forKey: Self.modelOverridesDefaultsKey)
        }
    }

    func forgetConversation(_ id: String) {
        for profileID in Array(conversationModels.keys) { conversationModels[profileID]?[id] = nil }
        defaults.set(conversationModels, forKey: Self.modelOverridesDefaultsKey)
    }

    private func validatedModel(_ id: String) throws -> SupportedModel {
        guard !id.isEmpty, id.utf8.count <= 512,
              id.utf8.allSatisfy({ (33...126).contains($0) }), let configuration else {
            throw AIInferenceBillingError.incompatibleModel
        }
        _ = try configuration.modelMapping.resolve(id)
        return .other(id)
    }

    /// Titles and summaries use the conversation model; standalone calls use the last chat choice.
    func modelForAuxiliaryRequest(fallback: SupportedModel, conversationModel: SupportedModel? = nil) throws -> SupportedModel {
        let selection = try AIInferenceBilling.selection ?? resolveSelection()
        guard let configuration = selection.credentials?.configuration else { return fallback }
        guard let id = conversationModel?.rawValue ?? AIInferenceBilling.directSnapshot?.modelID ?? configuration.defaultModel else { throw AIInferenceBillingError.missingModel }
        guard !id.isEmpty, id.utf8.count <= 512, id.utf8.allSatisfy({ (33...126).contains($0) }),
              (try? configuration.modelMapping.resolve(id)) != nil else { throw AIInferenceBillingError.incompatibleModel }
        return .other(id)
    }

    /// Preparation can suspend before the request holds a billing snapshot.
    func validateSelection(expectedRevision: Int) throws {
        guard expectedRevision == modelCatalogRevision else { throw AIInferenceBillingError.selectionChanged }
    }

    func withSelectedBilling<Result>(
        expectedRevision: Int? = nil,
        _ operation: @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        if let expectedRevision { try validateSelection(expectedRevision: expectedRevision) }
        if usesBYOK, integrationMode == .basic, AIInferenceBilling.selection == nil {
            guard let connectionID = selectedProfileID else { throw AIInferenceBillingError.missingConnection }
            let snapshot = try directSnapshot(connectionID: connectionID)
            return try await withDirectBilling(snapshot, operation: operation)
        }
        let selection = try AIInferenceBilling.selection ?? resolveSelection()
        return try await withBillingSnapshot(selection, operation)
    }

    func withBillingSnapshot<Result>(
        _ selection: AIInferenceBillingSelection,
        _ operation: @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        return try await withInferenceOperation {
            try await AIInferenceBilling.$selection.withValue(selection) { try await operation() }
        }
    }

    func withInferenceOperation<Result>(_ operation: @MainActor @Sendable () async throws -> Result) async throws -> Result {
        activeOperationCount += 1
        defer { activeOperationCount -= 1 }
        return try await operation()
    }

    func resolveSelection(for binding: LLMSchemeConversationBinding) throws -> AIInferenceBillingSelection {
        guard supportsManagedInference else {
            throw AIInferenceBillingError.managedInferenceUnavailable
        }
        try binding.validate()
        switch binding.billing {
        case .platform: return .platform
        case .byok(let model):
            guard let connectionID = binding.connectionID else { throw AIInferenceBillingError.missingConnection }
            return .byok(try credentials(connectionID: connectionID, model: model))
        }
    }

    /// Server/Scheme restoration uses the saved connection ID, never the global selection.
    func credentials(connectionID: String, model: SupportedModel) throws -> LLMBYOKCredentials {
        _ = try modelForRoute(connectionID: connectionID, modelID: model.rawValue)
        guard var configuration = try profile(for: connectionID).configuration else {
            throw AIInferenceBillingError.invalidConfiguration
        }
        guard let key = try keyStore.readKey(for: connectionID) else { throw AIInferenceBillingError.missingKey }
        configuration.defaultModel = model.rawValue
        configuration.webSearch?.isEnabled = false
        return .init(configuration: configuration, apiKey: try Self.validatedKey(key))
    }

    func modelForRoute(connectionID: String, modelID: String) throws -> SupportedModel {
        guard let configuration = try profile(for: connectionID).configuration else {
            throw AIInferenceBillingError.invalidConfiguration
        }
        try configuration.validate()
        guard !modelID.isEmpty, modelID.utf8.count <= 512,
              modelID.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw AIInferenceBillingError.incompatibleModel
        }
        _ = try configuration.modelMapping.resolve(modelID)
        return .other(modelID)
    }

    private func profile(for id: String? = nil) throws -> AIInferenceConnectionProfile {
        guard let profile = profiles.first(where: { $0.id == (id ?? selectedProfileID) }) else {
            throw AIInferenceBillingError.missingConnection
        }
        return profile
    }

    private func persistProfiles(_ profiles: [AIInferenceConnectionProfile], selectedID: String?) throws {
        let data = try JSONEncoder().encode(SavedConnections(profiles: profiles, selectedID: selectedID))
        defaults.set(data, forKey: Self.profilesDefaultsKey)
        self.profiles = profiles
        self.selectedProfileID = selectedID
    }

    private func didChangeKey() {
        refreshKeyStatus()
        keyRevision += 1
        modelCatalogRevision += 1
    }

    private func upgradeMiniMaxModelDiscovery() {
        guard !configurationLoadFailed else { return }
        var updated = profiles
        var changed = false
        for index in updated.indices {
            let profile = updated[index]
            guard [AIInferenceConnection.preset(.miniMax), .preset(.miniMaxChina)].contains(profile.provider),
                  let configuration = profile.configuration,
                  let preset = profile.provider.presetConfiguration,
                  preset.modelDiscovery != nil else { continue }
            var previousPreset = preset
            previousPreset.modelDiscovery = nil
            // Upgrade only the old default; retain explicitly customized configurations.
            guard configuration == previousPreset else { continue }
            updated[index].configuration = preset
            changed = true
        }
        if changed {
            do { try persistProfiles(updated, selectedID: selectedProfileID) }
            catch { configurationLoadFailed = true }
        }
    }

    private func migrateLegacyConnections(storedMode: String?) {
        let storedConnection = defaults.string(forKey: Self.connectionDefaultsKey)
        let storedConfigurations = defaults.object(forKey: Self.configurationsDefaultsKey)
        guard storedConnection != nil || storedConfigurations != nil || storedMode == "byok" || storedMode == "openRouter" else { return }
        let connection = storedConnection.flatMap(AIInferenceConnection.init(rawValue:)) ?? .openRouter
        do {
            if let storedConnection, AIInferenceConnection(rawValue: storedConnection) == nil {
                throw AIInferenceBillingError.invalidConfiguration
            }
            let configurations: [String: LLMBYOKConfiguration]
            if let storedConfigurations {
                guard let data = storedConfigurations as? Data else { throw AIInferenceBillingError.invalidConfiguration }
                configurations = try JSONDecoder().decode([String: LLMCore.LLMBYOKConfiguration].self, from: data)
            } else { configurations = [:] }
            var migrated: [AIInferenceConnectionProfile] = []
            for provider in AIInferenceConnection.allCases {
                let hasKey = try keyStore.readKey(for: provider.rawValue) != nil
                guard provider == connection || configurations[provider.rawValue] != nil || hasKey else { continue }
                var configuration = configurations[provider.rawValue] ?? provider.presetConfiguration
                let lastModel = configuration?.defaultModel
                configuration?.defaultModel = nil
                configuration?.options.auxiliaryModel = nil
                migrated.append(.init(id: provider.rawValue, name: provider.title, provider: provider,
                                      configuration: configuration, lastModelID: lastModel))
            }
            // Preserve legacy Keychain account names without copying credentials to preferences.
            try persistProfiles(migrated, selectedID: connection.rawValue)
        } catch {
            configurationLoadFailed = true
        }
    }

    private func requireIdle() throws {
        guard !isBusy else { throw AIInferenceBillingError.settingsBusy }
    }

    static func validatedKey(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 4096, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw AIInferenceBillingError.invalidKey
        }
        return key
    }
}
