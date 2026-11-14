import Foundation
import Combine
import LLMCore
import LLMKit

/// A view of SDK-owned routing. This value is never separately persisted.
enum AIChatConversationRoute: Equatable, Sendable {
    case platformScheme(schemeID: String, profileID: String)
    case optimizedBYOK(schemeID: String, connectionID: String, modelID: String)
    case basicBYOK(connectionID: String, modelID: String)
    case legacy

    init(binding: LLMSchemeConversationBinding?) throws {
        guard let binding else { self = .legacy; return }
        try binding.validate()
        switch binding.billing {
        case .platform:
            guard let id = binding.selection.profileID else { throw AIChatRoutingError.invalidRoute }
            self = .platformScheme(schemeID: binding.selection.schemeID, profileID: id)
        case .byok(let model):
            guard let id = binding.connectionID else { throw AIChatRoutingError.invalidRoute }
            self = .optimizedBYOK(schemeID: binding.selection.schemeID, connectionID: id, modelID: model.rawValue)
        }
    }

    var binding: LLMSchemeConversationBinding? {
        switch self {
        case .platformScheme(let schemeID, let profileID):
            .init(selection: .init(schemeID: schemeID, profileID: profileID), billing: .platform)
        case .optimizedBYOK(let schemeID, let connectionID, let modelID):
            .init(selection: .init(schemeID: schemeID), billing: .byok(model: SupportedModel(rawValue: modelID)), connectionID: connectionID)
        case .basicBYOK, .legacy: nil
        }
    }

    var usesBYOK: Bool {
        switch self {
        case .optimizedBYOK, .basicBYOK: true
        default: false
        }
    }

    var isDirect: Bool {
        if case .basicBYOK = self { return true }
        return false
    }

    var profileID: String? { binding?.selection.profileID }
    var byokModelID: String? {
        switch self {
        case .optimizedBYOK(_, _, let id), .basicBYOK(_, let id): id
        default: nil
        }
    }
}

enum AIChatRoutingError: LocalizedError {
    case profileUnavailable(String)
    case invalidRoute
    case consentRequired
    case catalog(String)

    var errorDescription: String? {
        switch self {
        case .profileUnavailable(let id):
            String(localizable: .aISchemeProfileUnavailable(id))
        case .invalidRoute: String(localizable: .aISchemeInvalidRoute)
        case .consentRequired: String(localizable: .aISchemeConsentRequired)
        case .catalog(let message): message
        }
    }
}

@MainActor
final class AIChatRoutingState: ObservableObject {
    static let shared = AIChatRoutingState()
    private static let defaultProfileKey = "AIChat.defaultSchemeProfileID"
    @Published var defaultProfileID: String? {
        didSet { UserDefaults.standard.set(defaultProfileID, forKey: Self.defaultProfileKey) }
    }
    // Capability hints for unbound old conversations; not new Scheme bindings.
    @Published private(set) var legacySelections: [String: AIChatModelSelection] = [:]
    @Published private(set) var updatingConversationIDs: Set<String> = []

    init() { defaultProfileID = UserDefaults.standard.string(forKey: Self.defaultProfileKey) }

    func route(for conversation: Conversation) throws -> AIChatConversationRoute {
        if let binding = conversation.directConnection {
            guard conversation.schemeConnection == nil,
                  let record = AIChatInferenceSessions.shared.directRecords[conversation.id],
                  record.binding.configuration == binding.configuration else { throw AIChatRoutingError.invalidRoute }
            return .basicBYOK(connectionID: record.connectionID, modelID: binding.chatModel.rawValue)
        }
        return try .init(binding: conversation.schemeConnection)
    }

    func select(_ route: AIChatConversationRoute, for conversationID: String, state: LLMStateObject) async throws {
        guard let conversation = state.getConversation(by: conversationID) else { throw AIChatRoutingError.invalidRoute }
        let expectedRoute = try self.route(for: conversation)
        guard !updatingConversationIDs.contains(conversationID) else { throw LLMSchemeStateError.generationInProgress }
        updatingConversationIDs.insert(conversationID)
        defer { updatingConversationIDs.remove(conversationID) }
        try await AIChatSchemeSwitch.apply(route, in: conversationID, expectedRoute: expectedRoute,
            state: state, billing: .shared, consent: .shared)
    }

    func newRoute(profileID: String? = nil) throws -> AIChatConversationRoute {
        let billing = AIInferenceBillingState.shared
        if billing.usesBYOK {
            guard let connectionID = billing.selectedProfileID else { throw AIInferenceBillingError.missingConnection }
            if billing.integrationMode == .basic {
                return .basicBYOK(connectionID: connectionID, modelID: try billing.modelForChat().rawValue)
            }
            return .optimizedBYOK(schemeID: AIChatSchemeCatalog.schemeID, connectionID: connectionID,
                                  modelID: try billing.modelForChat().rawValue)
        }
        guard let id = profileID ?? defaultProfileID ?? AIChatSchemeCatalog.shared.scheme?.defaultProfileID else {
            throw AIChatRoutingError.catalog(AIChatSchemeCatalog.shared.errorMessage
                ?? String(localizable: .aISchemeProfilesNotLoaded))
        }
        return .platformScheme(schemeID: AIChatSchemeCatalog.schemeID, profileID: id)
    }

    func modelSelection(for route: AIChatConversationRoute, conversationID: String? = nil) throws -> AIChatModelSelection {
        try requireSupportedTransport(route)
        switch route {
        case .platformScheme(let schemeID, let profileID):
            guard schemeID == AIChatSchemeCatalog.schemeID else { throw AIChatRoutingError.invalidRoute }
            return AIChatModelSelection(platform: try AIChatSchemeCatalog.shared.requireProfile(profileID))
        case .optimizedBYOK(let schemeID, let connectionID, let modelID):
            guard schemeID == AIChatSchemeCatalog.schemeID else { throw AIChatRoutingError.invalidRoute }
            return AIChatModelSelection(byok: try AIInferenceBillingState.shared.modelForRoute(
                connectionID: connectionID, modelID: modelID
            ))
        case .basicBYOK(let connectionID, let modelID):
            return AIChatModelSelection(byok: try AIInferenceBillingState.shared.modelForRoute(connectionID: connectionID, modelID: modelID))
        case .legacy:
            if AIInferenceBillingState.shared.usesBYOK {
                return AIChatModelSelection(byok: try AIInferenceBillingState.shared.modelForChat(conversationID: conversationID))
            }
            guard let conversationID, let selection = legacySelections[conversationID] else {
                throw AIChatRoutingError.profileUnavailable("")
            }
            return selection
        }
    }

    /// Old conversations retain /chat and their historical preferences; no automatic Scheme binding.
    func loadLegacySelection(conversationID: String) async throws {
        let billing = AIInferenceBillingState.shared
        if billing.usesBYOK { return }
        let defaults = UserDefaults.standard
        let profileID = (defaults.dictionary(forKey: "AIChat.conversationModelTierOverrides") as? [String: String])?[conversationID]
            ?? defaults.string(forKey: "AIChat.defaultModelTier")
        if profileID == nil,
           let modelID = (defaults.dictionary(forKey: "AIChat.conversationModelOverrides") as? [String: String])?[conversationID]
                ?? defaults.string(forKey: "AIChat.defaultModel") {
            legacySelections[conversationID] = AIChatModelSelection(legacy: SupportedModel(rawValue: modelID))
            return
        }
        let id = profileID ?? "medium"
        let config = try await LLMClient.shared.getDomainAgentConfig(agentID: ExcalidrawAgentConfig.agentID)
        guard let profile = config.modelProfiles?.first(where: { $0.id == id }) else {
            throw AIChatRoutingError.profileUnavailable(id)
        }
        legacySelections[conversationID] = AIChatModelSelection(legacy: profile.model, profileID: profile.id,
            supportsImageInput: profile.capabilities.supportsImageInput,
            maxContextTokens: profile.capabilities.maxContextTokens)
    }

    /// Only a new conversation opens a Scheme scope. Bound conversations resolve from SDK state.
    func withRequest<Result>(
        route: AIChatConversationRoute,
        conversationID: String? = nil,
        state: LLMStateObject,
        expectedBillingRevision: Int? = nil,
        operation: @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        try requireSupportedTransport(route)
        let billing = AIInferenceBillingState.shared
        guard AIChatInferenceSessions.shared.session(for: conversationID).state === state else {
            throw AIInferenceBillingError.selectionChanged
        }
        let usesBYOK = route == .legacy ? billing.usesBYOK : route.usesBYOK
        guard AIServiceConsentState.shared.hasAccepted(usesBYOK ? .byok : .platform) else {
            throw AIChatRoutingError.consentRequired
        }
        if let conversationID {
            try AIChatInferenceSessions.shared.requireTransportReady(conversationID)
            guard !updatingConversationIDs.contains(conversationID),
                  !AIChatInferenceSessions.shared.updatingConversationIDs.contains(conversationID) else {
                throw LLMSchemeStateError.generationInProgress
            }
            guard let conversation = state.getConversation(by: conversationID),
                  try self.route(for: conversation) == route else { throw AIInferenceBillingError.selectionChanged }
            if case .basicBYOK(let connectionID, let modelID) = route {
                let snapshot = try billing.directSnapshot(connectionID: connectionID,
                    configuration: conversation.directConnection?.configuration, modelID: modelID)
                return try await billing.withDirectBilling(snapshot, operation: operation)
            }
            if route == .legacy {
                return try await billing.withSelectedBilling(expectedRevision: expectedBillingRevision, operation)
            }
            return try await billing.withInferenceOperation(operation)
        }
        if case .basicBYOK(let connectionID, let modelID) = route {
            if let expectedBillingRevision { try billing.validateSelection(expectedRevision: expectedBillingRevision) }
            return try await billing.withDirectBilling(try billing.directSnapshot(connectionID: connectionID, modelID: modelID), operation: operation)
        }
        guard let binding = route.binding else { throw AIChatRoutingError.invalidRoute }
        if let expectedBillingRevision { try billing.validateSelection(expectedRevision: expectedBillingRevision) }
        let snapshot = try billing.resolveSelection(for: binding)
        return try await billing.withBillingSnapshot(snapshot) {
            try await LLMClient.shared.withScheme(binding.selection, billing: binding.billing,
                                                  connectionID: binding.connectionID, operation: operation)
        }
    }

    private func requireSupportedTransport(_ route: AIChatConversationRoute) throws {
        guard !AIChatAvailability.supportsManagedInference else { return }
        guard case .basicBYOK = route else { throw AIInferenceBillingError.managedInferenceUnavailable }
    }
}
