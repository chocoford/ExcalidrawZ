import Observation
import Foundation
import SwiftUI
import SwiftyAlert
import ChocofordUI
import LLMCore
import LLMKit

@MainActor
@Observable
final class AIChatInferenceSessions {
    static let shared = AIChatInferenceSessions()

    struct Session {
        let client: LLMClient
        let state: LLMStateObject
    }
    private struct DirectEntry {
        let connectionID: String
        let configuration: LLMBYOKConfiguration
        let session: Session
    }

    private(set) var directRecords: [String: AIDirectConversationRecord] = [:]
    private(set) var serverConversationIDs: Set<String> = []
    private(set) var serverSchemeBindings: [String: LLMSchemeConversationBinding] = [:]
    private(set) var updatingConversationIDs: Set<String> = []
    @ObservationIgnored private var transportTasks: [String: Task<Void, Error>] = [:]
    @ObservationIgnored private var transportErrors: [String: Error] = [:]
    @ObservationIgnored private var transportIntents: [String: AIInferenceIntegrationMode] = [:]
    @ObservationIgnored private var server: Session?
    @ObservationIgnored private var directEntries: [DirectEntry] = []
    @ObservationIgnored private var metadataTask: Task<Void, Error>?
    @ObservationIgnored private var metadataLoaded = false
    private(set) var metadataRevision = 0
    @ObservationIgnored private var localRevisions: [String: Int] = [:]
    @ObservationIgnored private var disableObserver: ObservationSubscription?

    func configure(serverState: LLMStateObject) {
        server = Session(client: .shared, state: serverState)
        disableObserver?.cancel()
        disableObserver = ObservationSubscription(initial: false, {
            AIChatPreferences.shared.isAIEnabled
        }) { [weak self] enabled in
            guard !enabled else { return }
            self?.cancelAll()
        }
    }

    func session(for conversationID: String?) -> Session {
        guard let server else { preconditionFailure("Configure AI sessions at App startup") }
        if let conversationID {
            if let record = directRecords[conversationID] {
                let configuration = AIInferenceBillingState.shared.directConfiguration(
                    connectionID: record.connectionID, bound: record.binding.configuration)
                return directSession(connectionID: record.connectionID, configuration: configuration)
            }
            if serverConversationIDs.contains(conversationID), AIChatAvailability.supportsManagedInference { return server }
        }
        let billing = AIInferenceBillingState.shared
        if AIChatAvailability.supportsManagedInference,
           !billing.usesBYOK || billing.integrationMode != .basic { return server }
        // An unconfigured Direct client fails locally; it never substitutes the server client.
        return directSession(connectionID: billing.selectedProfileID ?? "unconfigured",
                             configuration: billing.configuration ?? .openAI)
    }

    private func directSession(connectionID: String, configuration: LLMBYOKConfiguration) -> Session {
        if let entry = directEntries.first(where: { $0.connectionID == connectionID && $0.configuration == configuration }) {
            return entry.session
        }
        guard let server else { preconditionFailure("Configure AI sessions at App startup") }
        let client = AIInferenceBillingState.makeDirectClient(connectionID: connectionID, configuration: configuration)
        let state = LLMStateObject(llmClient: client, toolRegistry: server.state.toolRegistry,
            persistenceProvider: LLMPersistenceProvider(directConnectionID: connectionID), streamPublishStrategy: .throttled(0.33))
        let session = Session(client: client, state: state)
        directEntries.append(.init(connectionID: connectionID, configuration: configuration, session: session))
        return session
    }

    func setWebSearch(_ enabled: Bool, connectionID: String) async throws {
        try await AIInferenceBillingState.shared.setWebSearch(enabled, connectionID: connectionID) { configuration in
            guard self.directEntries.contains(where: { $0.connectionID == connectionID }) else { return }
            let destination = self.directSession(connectionID: connectionID, configuration: configuration)
            // Refresh even when returning to a cached option: another state may have added turns.
            await destination.state.refreshConversations()
            guard destination.state.conversations.value != nil else { throw AIChatRoutingError.invalidRoute }
        }
    }

    func ensureMetadataLoaded() async throws {
        if metadataLoaded { return }
        if let metadataTask { try await metadataTask.value; return }
        let task = Task { @MainActor in
            let revision = metadataRevision
            let values = try await PersistenceController.shared.aiConversationRepository.fetchInferenceRoutes()
            try register(values, readRevision: revision)
            metadataLoaded = true
        }
        metadataTask = task
        defer { metadataTask = nil }
        try await task.value
    }

    func register(_ values: [(id: String, data: Data?)], readRevision: Int) throws {
        var direct = directRecords.filter { localRevisions[$0.key, default: 0] > readRevision }
        var backend = serverConversationIDs.filter { localRevisions[$0, default: 0] > readRevision }
        var bindings = serverSchemeBindings.filter { localRevisions[$0.key, default: 0] > readRevision }
        for value in values {
            guard localRevisions[value.id, default: 0] <= readRevision else { continue }
            if let record = try AIChatRouteStorage.decodeDirect(value.data) { direct[value.id] = record }
            else {
                backend.insert(value.id)
                bindings[value.id] = try AIChatRouteStorage.decode(value.data)
            }
        }
        if directRecords != direct { directRecords = direct }
        if serverConversationIDs != backend { serverConversationIDs = backend }
        if serverSchemeBindings != bindings { serverSchemeBindings = bindings }
    }

    func inserted(_ id: String, direct: AIDirectConversationRecord?, scheme: LLMSchemeConversationBinding? = nil) {
        metadataRevision += 1
        localRevisions[id] = metadataRevision
        directRecords[id] = direct
        serverSchemeBindings[id] = scheme
        if direct != nil { serverConversationIDs.remove(id) }
        else { serverConversationIDs.insert(id) }
    }

    func removed(_ id: String) {
        metadataRevision += 1
        localRevisions[id] = metadataRevision
        directRecords[id] = nil
        serverSchemeBindings[id] = nil
        serverConversationIDs.remove(id)
    }

    private func needsTransportMigration(_ id: String) -> Bool {
        let billing = AIInferenceBillingState.shared
        guard billing.usesBYOK else { return false }
        let requestedMode = transportIntents[id]
        if directRecords[id] != nil { return requestedMode == .optimized }
        guard serverConversationIDs.contains(id) else { return false }
        if let binding = serverSchemeBindings[id], case .platform = binding.billing { return false }
        if serverSchemeBindings[id] != nil { return requestedMode == .basic }
        // Legacy chats have no recorded transport. Adopt the user's Basic selection before sending.
        return (requestedMode ?? billing.integrationMode) == .basic
    }

    func requireTransportReady(_ id: String) throws {
        if let error = transportErrors[id] { throw error }
        guard !updatingConversationIDs.contains(id), !needsTransportMigration(id) else {
            throw LLMSchemeStateError.generationInProgress
        }
    }

    /// Settings choose the BYOK transport; migrate the active chat before giving it to a client.
    /// Unstructured work finishes an already committed migration even if SwiftUI replaces its task.
    func prepareTransport(for id: String, mode: AIInferenceIntegrationMode? = nil) async throws {
        try await ensureMetadataLoaded()
        if let mode { transportIntents[id] = mode }
        if let task = transportTasks[id] { try await task.value; return }
        guard needsTransportMigration(id) else { transportErrors[id] = nil; transportIntents[id] = nil; return }
        let mode = transportIntents[id] ?? AIInferenceBillingState.shared.integrationMode
        let task = Task { @MainActor in try await migrateTransport(for: id, mode: mode) }
        transportTasks[id] = task
        defer { transportTasks[id] = nil }
        do {
            try await task.value
            transportErrors[id] = nil
            transportIntents[id] = nil
        } catch {
            transportErrors[id] = error
            throw error
        }
    }

    private func migrateTransport(for id: String, mode: AIInferenceIntegrationMode) async throws {
        let billing = AIInferenceBillingState.shared
        let source = session(for: id)
        guard !billing.isBusy, !source.state.isRunning(conversationID: id), !updatingConversationIDs.contains(id) else {
            throw LLMSchemeStateError.generationInProgress
        }
        updatingConversationIDs.insert(id)
        defer { updatingConversationIDs.remove(id) }
        try await billing.withInferenceOperation {
            if source.state.getConversation(by: id) == nil { await source.state.refreshConversations() }
            guard let conversation = source.state.getConversation(by: id) else { throw AIChatRoutingError.invalidRoute }
            let connectionID = directRecords[id]?.connectionID ?? conversation.schemeConnection?.connectionID
                ?? billing.selectedProfileID
            guard let connectionID else { throw AIInferenceBillingError.missingConnection }
            let model: SupportedModel
            if let direct = conversation.directConnection { model = direct.chatModel }
            else if case .byok(let selected) = conversation.schemeConnection?.billing { model = selected }
            else { model = try billing.modelForChat(conversationID: id, profileID: connectionID) }
            let migration = try await AIChatBYOKTransportMigration.prepare(conversation: conversation,
                connectionID: connectionID, model: model, mode: mode, billing: billing,
                consent: .shared, registry: source.state.toolRegistry)
            try await PersistenceController.shared.aiConversationRepository.migrateInferenceTransport(migration)
            inserted(id, direct: migration.directRecord, scheme: migration.schemeBinding)
            let destination = session(for: id)
            await destination.state.refreshConversations()
            guard let restored = destination.state.getConversation(by: id),
                  restored.directConnection == migration.directRecord?.binding,
                  restored.schemeConnection == migration.schemeBinding else { throw AIChatRoutingError.invalidRoute }
        }
    }

    func updateDirectModel(_ model: SupportedModel, in conversation: Conversation, state: LLMStateObject) async throws {
        guard !AIInferenceBillingState.shared.isBusy, !state.isRunning(conversationID: conversation.id),
              !updatingConversationIDs.contains(conversation.id),
              var record = directRecords[conversation.id],
              conversation.directConnection?.configuration == record.binding.configuration else {
            throw LLMDirectError.conversationConnectionMismatch
        }
        record.binding.chatModel = SupportedModel(rawValue: model.rawValue)
        try record.validate()
        updatingConversationIDs.insert(conversation.id)
        defer { updatingConversationIDs.remove(conversation.id) }
        try await PersistenceController.shared.aiConversationRepository.updateInferenceRoute(
            conversationID: conversation.id, data: try AIChatRouteStorage.encodeDirect(record))
        inserted(conversation.id, direct: record)
        await state.refreshConversations()
    }

    private func cancelAll() {
        for state in [server?.state].compactMap({ $0 }) + directEntries.map({ $0.session.state }) {
            for conversation in state.conversations.value ?? [] { state.cancelGeneration(conversationID: conversation.id) }
        }
    }
}

struct AIChatInferenceEnvironment: ViewModifier {
    @Environment(FileState.self) private var fileState
    @Environment(\.alertToast) private var alertToast
    @Bindable private var sessions = AIChatInferenceSessions.shared
    @Bindable private var billing = AIInferenceBillingState.shared

    func body(content: Content) -> some View {
        let session = sessions.session(for: fileState.aiChatConversationID)
        content
            .llmProvider(state: session.state, client: session.client)
            .watch(value: billing.integrationMode) { _, mode in
                guard AIChatAvailability.canUseAI, billing.usesBYOK, let id = fileState.aiChatConversationID else { return }
                Task { @MainActor in
                    do { try await sessions.prepareTransport(for: id, mode: mode) }
                    catch { alertToast.presentAIChatError(error) }
                }
            }
            .task(id: "\(ObjectIdentifier(session.state)):\(fileState.aiChatConversationID ?? "new"):\(billing.modelCatalogRevision)") {
                guard AIChatAvailability.canUseAI else { return }
                do {
                    try await sessions.ensureMetadataLoaded()
                    if let id = fileState.aiChatConversationID { try await sessions.prepareTransport(for: id) }
                    guard !Task.isCancelled else { return }
                    let resolved = sessions.session(for: fileState.aiChatConversationID)
                    if !resolved.client.isDirectBYOK {
                        await LLMServiceActivationCoordinator.shared.restoreIfAIEnabled(reason: .savedServerConversation)
                    }
                } catch {
                    if !Task.isCancelled { alertToast.presentAIChatError(error) }
                }
            }
    }
}
