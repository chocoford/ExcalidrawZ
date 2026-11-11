import Foundation
import Logging
import LLMCore
import LLMKit

/// Request-only secret. Never Codable, persisted, or included in a log/transaction.
struct AIDirectCredentialSnapshot: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let connectionID: String
    let configuration: LLMBYOKConfiguration
    let modelID: String?
    private let apiKey: String

    init(connectionID: String, configuration: LLMBYOKConfiguration, modelID: String?, apiKey: String) {
        self.connectionID = connectionID
        self.configuration = configuration
        self.modelID = modelID
        self.apiKey = apiKey
    }

    func key(for connectionID: String, configuration: LLMBYOKConfiguration) throws -> String {
        guard self.connectionID == connectionID, self.configuration == configuration else {
            throw LLMDirectError.conversationConnectionMismatch
        }
        return apiKey
    }
    var credentials: LLMBYOKCredentials { .init(configuration: configuration, apiKey: apiKey) }
    var description: String { "AIDirectCredentialSnapshot(apiKey: <redacted>)" }
    var debugDescription: String { description }
}

extension AIInferenceBillingState {
    private static let directLogger = Logger(label: "AIDirectInference")

    func directSnapshot(connectionID: String, configuration: LLMBYOKConfiguration? = nil,
                        modelID: String? = nil) throws -> AIDirectCredentialSnapshot {
        guard let profile = profiles.first(where: { $0.id == connectionID }), let saved = profile.configuration else {
            throw AIInferenceBillingError.missingConnection
        }
        if let configuration, !saved.hasSameConnection(as: configuration) { throw LLMDirectError.conversationConnectionMismatch }
        try saved.validate()
        let key = try Self.validatedKey(keyForEditing(profileID: connectionID))
        return .init(connectionID: connectionID, configuration: saved,
                     modelID: modelID ?? profile.lastModelID, apiKey: key)
    }

    /// Restore only the current request option onto a historical connection binding.
    /// Changes to endpoint, mapping or other identity fields still fail closed on send.
    func directConfiguration(connectionID: String, bound: LLMBYOKConfiguration) -> LLMBYOKConfiguration {
        guard let saved = profiles.first(where: { $0.id == connectionID })?.configuration,
              saved.hasSameConnection(as: bound) else { return bound }
        var configuration = bound
        configuration.webSearch = saved.webSearch
        return configuration
    }

    func withDirectBilling<Result>(_ snapshot: AIDirectCredentialSnapshot,
        operation: @MainActor @Sendable () async throws -> Result) async throws -> Result {
        try await withBillingSnapshot(.byok(snapshot.credentials)) {
            let search = snapshot.configuration.webSearch
            Self.directLogger.debug("Starting Basic BYOK generation webSearchOptIn=\(search?.isEnabled ?? false) adapter=\(search?.adapter.rawValue ?? "none")")
            return try await AIInferenceBilling.$directSnapshot.withValue(snapshot, operation: operation)
        }
    }

    static func makeDirectClient(connectionID: String, configuration: LLMBYOKConfiguration,
                                 session: URLSession? = nil) -> LLMClient {
        LLMClient(directBYOK: .init(configuration: configuration, apiKeyProvider: {
            if let snapshot = AIInferenceBilling.directSnapshot {
                return try snapshot.key(for: connectionID, configuration: configuration)
            }
            let snapshot = try await AIInferenceBillingState.shared.directSnapshot(
                connectionID: connectionID, configuration: configuration
            )
            return try snapshot.key(for: connectionID, configuration: configuration)
        }), options: .init(systemPrompt: ExcalidrawAgentConfig.basicWebSearchPrompt(for: configuration)), session: session)
    }

    func selectedInferenceClient() throws -> LLMClient {
        guard usesBYOK, integrationMode == .basic else { return .shared }
        guard let profile = selectedProfile, let configuration = profile.configuration else {
            throw AIInferenceBillingError.missingConnection
        }
        return Self.makeDirectClient(connectionID: profile.id, configuration: configuration)
    }
}
