import Foundation
import LLMCore
import LLMKit
import XCTest
@testable import ExcalidrawZ

final class AIChatSchemeSwitchTests: XCTestCase {
    @MainActor
    func testBasicSearchSettingsPreserveHistoryAndStayOutOfOptimizedRequests() async throws {
        try await AppSchemeSwitchFixture.validateSearch()
    }
    @MainActor
    func testExplicitSwitchPreservesHistoryAndUsesDestinationBilling() async throws {
        try await AppSchemeSwitchFixture.validate()
    }

    @MainActor
    func testLegacyChatCanSendAndRetryAcrossBasicAndOptimized() async throws {
        try await AppSchemeSwitchFixture.validateTransports()
    }
}

/// Exercises the App switch preflight and SDK persistence/HTTP path without real services.
enum AppSchemeSwitchFixture {
    @MainActor
    static func validateSearch() async throws {
        try await validateSavedSearchCapability()
        let defaults = SwitchMemoryDefaults()
        let keys = SwitchMemoryKeys()
        let billing = AIInferenceBillingState(defaults: defaults, keyStore: keys)
        let profile = try billing.addConnection(.openAI, apiKey: "synthetic-search-key")
        let model = SupportedModel.other("gpt-4o-search-preview")
        let original = profile.configuration!
        let keyRevision = billing.keyRevision
        try await billing.setWebSearch(true, connectionID: profile.id) { configuration in
            try require(billing.isBusy && configuration.webSearch?.isEnabled == true)
            try require(billing.configuration?.webSearch?.isEnabled != true)
        }
        try require(billing.keyRevision == keyRevision && billing.selectedProfileID == profile.id)
        let restoredBilling = AIInferenceBillingState(defaults: defaults, keyStore: keys)
        try require(restoredBilling.configuration?.webSearch?.isEnabled == true)
        try require(try billing.directSnapshot(connectionID: profile.id, configuration: original).configuration.webSearch?.isEnabled == true)
        let snapshot = try billing.directSnapshot(connectionID: profile.id, modelID: model.rawValue)
        try await billing.withDirectBilling(snapshot) {
            do { try await billing.setWebSearch(false, connectionID: profile.id); throw Failure.expectedRejection }
            catch AIInferenceBillingError.settingsBusy {}
            try require(AIInferenceBilling.directSnapshot?.configuration.webSearch?.isEnabled == true)
        }
        do {
            try await billing.setWebSearch(false, connectionID: profile.id) { _ in throw Failure.write }
            throw Failure.expectedRejection
        } catch Failure.write {}
        try require(billing.configuration?.webSearch?.isEnabled == true && !billing.isBusy)
        let unsupported = try billing.addConnection(.anthropic, apiKey: "synthetic-other-key")
        do { try await billing.setWebSearch(true, connectionID: unsupported.id); throw Failure.expectedRejection }
        catch LLMBYOKWebSearchError.unsupportedProtocol {}
        try require(billing.profiles.first { $0.id == unsupported.id }?.configuration?.webSearch == nil)

        let options = URLSessionConfiguration.ephemeral
        options.protocolClasses = [SwitchProtocol.self]
        let session = URLSession(configuration: options)
        defer { session.invalidateAndCancel(); SwitchProtocol.store.reset() }
        let user = ChatMessageContent(id: "before-search", role: .user, content: "Keep this history")
        let oldPrompt = ChatMessageContent(id: "old-basic-prompt", role: .system,
            content: "Do not claim App-provided web-search, web-fetch or server-agent capabilities.")
        let pastAnswer = ChatMessageContent(id: "before-enabling-search", role: .assistant,
            content: "I have no web search tool.")
        let seed = Conversation(id: "direct-search", type: .regular, title: "History",
            messages: [.content(oldPrompt), .content(user), .content(pastAnswer)], createdAt: .now, lastChatAt: .now,
            directConnection: .init(configuration: original, chatModel: model))
        let directRecord = AIDirectConversationRecord(connectionID: profile.id, binding: seed.directConnection!)
        let persistence = SwitchPersistence(seed, directRecord: directRecord)
        for enabled in [true, false, true] {
            try await billing.setWebSearch(enabled, connectionID: profile.id)
            let configuration = billing.directConfiguration(connectionID: profile.id, bound: original)
            let client = AIInferenceBillingState.makeDirectClient(connectionID: profile.id, configuration: configuration, session: session)
            let state = LLMStateObject(llmClient: client, persistenceProvider: persistence)
            await state.refreshConversations()
            try await billing.withDirectBilling(billing.directSnapshot(connectionID: profile.id, configuration: original, modelID: model.rawValue)) {
                try await state.sendMessage(to: seed.id, model: model, message: .content(.init(role: .user, content: "Continue")))
            }
            try require(state.getConversation(by: seed.id)?.messages.contains(.content(user)) == true)
            try require(state.getConversation(by: seed.id)?.messages.contains(.content(oldPrompt)) == true)
            try require(state.getConversation(by: seed.id)?.messages.contains(.content(pastAnswer)) == true)
            try require(state.getConversation(by: seed.id)?.directConnection?.configuration == original)
            let request = SwitchProtocol.store.requests.last!
            let body = try payload(request)
            try require((body["web_search_options"] != nil) == enabled)
            let messages = body["messages"] as? [[String: Any]] ?? []
            try require(messages.contains { $0["content"] as? String == oldPrompt.content })
            try require(messages.contains { $0["content"] as? String == pastAnswer.content })
            let currentCapability = messages.filter { ($0["content"] as? String)?.contains("Provider-hosted web search is enabled for this request.") == true }
            // A restored chat follows the current setting, not historical search failures.
            try require(currentCapability.count == (enabled ? 1 : 0))
            try require(request.url?.host == original.baseURL.host)
            try require(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-search-key")
        }

        let binding = LLMSchemeConversationBinding(selection: .init(schemeID: "excalidraw-canvas"),
            billing: .byok(model: model), connectionID: profile.id)
        try billing.selectConnection(profile.id)
        try billing.setMode(.byok)
        try billing.setIntegrationMode(.optimized)
        try require(try billing.resolveSelection().credentials?.configuration.webSearch?.isEnabled == false)
        let serverSeed = Conversation(id: "server-search", type: .regular, title: "History",
            messages: [.content(user)], createdAt: .now, lastChatAt: .now, schemeConnection: binding)
        let server = LLMClient(authProvider: SwitchAuthProvider(), baseURL: URL(string: "https://app-switch-test.invalid")!, session: session)
        let state = LLMStateObject(llmClient: server, persistenceProvider: SwitchPersistence(serverSeed),
            schemeCredentialsProvider: { id, model in try await billing.credentials(connectionID: id, model: model) })
        await state.refreshConversations()
        try await state.sendMessage(to: serverSeed.id, model: model, message: .content(.init(role: .user, content: "Search")))
        let request = SwitchProtocol.store.requests.last!
        let data = Data(base64Encoded: request.value(forHTTPHeaderField: "X-LLM-BYOK-Configuration")!)!
        let configuration = try JSONDecoder().decode(LLMBYOKConfiguration.self, from: data)
        try require(request.url?.path == "/schemes/byok/stream" && configuration.webSearch?.isEnabled == false)
        try require(request.value(forHTTPHeaderField: "X-LLM-BYOK-Key") == "synthetic-search-key")
        // Hiding the Basic setting must not erase it, nor leak it into Optimized requests.
        try require(billing.selectedProfile?.configuration?.webSearch?.isEnabled == true)
        try require(try billing.directSnapshot(connectionID: profile.id, configuration: original).configuration.webSearch?.isEnabled == true)
        let before = SwitchProtocol.store.requests.count
        SwitchProtocol.store.setAcknowledgesSearch(false)
        try await state.sendMessage(to: serverSeed.id, model: model, message: .content(.init(role: .user, content: "Again")))
        let sent = SwitchProtocol.store.requests.dropFirst(before).filter { $0.url?.path.hasSuffix("/stream") == true }
        try require(sent.count == 1 && sent.first?.url?.path == "/schemes/byok/stream")
    }

    @MainActor
    private static func validateSavedSearchCapability() async throws {
        let defaults = SwitchMemoryDefaults()
        let keys = SwitchMemoryKeys()
        let billing = AIInferenceBillingState(defaults: defaults, keyStore: keys)
        var original = LLMBYOKConfiguration.openRouter
        // This is the configuration written by the connection editor before search existed.
        original.defaultModel = nil
        original.options.auxiliaryModel = nil
        let profile = try billing.addConnection(.openRouter, configuration: original, apiKey: "synthetic-legacy-router")
        try require(profile.webSearchConfiguration?.webSearchAdapter == .openRouter)
        try require(profile.webSearchConfiguration?.webSearch?.isEnabled == false)
        try require(profile.configuration?.webSearch == nil)
        try require(profile.webSearchConfiguration?.hasSameConnection(as: original) == true)
        let snapshot = try billing.directSnapshot(connectionID: profile.id, modelID: "xiaomi/mimo-v2.6-pro")
        try await billing.setWebSearch(true, connectionID: profile.id)
        let enabled = try billing.directSnapshot(connectionID: profile.id, configuration: original, modelID: snapshot.modelID)
        try require(enabled.configuration.webSearch?.adapter == .openRouter && enabled.configuration.webSearch?.isEnabled == true)
        try require(enabled.configuration.options.auxiliaryModel == nil)
        try require(enabled.configuration.defaultModel == original.defaultModel && enabled.modelID == snapshot.modelID)
        try require(try enabled.key(for: profile.id, configuration: enabled.configuration) == "synthetic-legacy-router")
        let restored = AIInferenceBillingState(defaults: defaults, keyStore: keys)
        try require(restored.selectedProfile?.webSearchConfiguration?.webSearch?.isEnabled == true)

        var customized = LLMBYOKConfiguration.openAI
        customized.defaultModel = "own-model"
        customized.modelDiscovery = nil
        customized.options.outputTokenLimit = 8192
        let supported = AIInferenceConnection.openAI.configurationWithWebSearchSupport(customized)
        try require(supported.webSearchAdapter == .openAI && supported.hasSameConnection(as: customized))

        // A named preset must not implicitly enable its protocol on an overridden host/root.
        customized.baseURL = URL(string: "https://gateway.example/v1/")!
        try require(AIInferenceConnection.openAI.configurationWithWebSearchSupport(customized).webSearch == nil)
        customized.baseURL = URL(string: "https://api.openai.com/another-root/")!
        try require(AIInferenceConnection.openAI.configurationWithWebSearchSupport(customized).webSearch == nil)
        try require(AIInferenceConnection.custom.configurationWithWebSearchSupport(original).webSearch == nil)
        customized.webSearch = .init(adapter: .dashScope, isEnabled: true)
        try require(AIInferenceConnection.custom.configurationWithWebSearchSupport(customized) == customized)
        try require(AIInferenceConnection.anthropic.configurationWithWebSearchSupport(.anthropic).webSearchAdapter == nil)
    }

    @MainActor
    static func validateTransports() async throws {
        let defaults = SwitchMemoryDefaults()
        let keys = SwitchMemoryKeys()
        let billing = AIInferenceBillingState(defaults: defaults, keyStore: keys)
        let connection = try billing.addConnection(.openAI, apiKey: "synthetic-direct-key")
        try billing.setMode(.byok)
        try billing.setModel("manual-model")
        let consent = AIServiceConsentState(defaults: defaults)
        consent.accept(.byok)
        let registry = ToolRegistry()
        let user = ChatMessageContent(id: "original-user", role: .user, content: "Original question")
        let summary = ChatMessageContent(role: .system, content: "Keep this summary", isCompactSummary: true)
        let legacy = Conversation(id: "transport-chat", type: .regular,
            agentConfig: ExcalidrawAgentConfig.defaultConfig(tools: ["web_search", "calculator"]), title: "Keep Me",
            messages: [.content(.init(id: "generated-system", role: .system, content: "Old generated prompt")),
                       .content(summary), .content(user), .content(.init(role: .assistant, content: "Original answer"))],
            createdAt: .now, lastChatAt: .now)
        let persistence = SwitchPersistence(legacy)
        let options = URLSessionConfiguration.ephemeral
        options.protocolClasses = [SwitchProtocol.self]
        let session = URLSession(configuration: options)
        defer { session.invalidateAndCancel(); SwitchProtocol.store.reset() }
        var previous = legacy
        for mode in [AIInferenceIntegrationMode.basic, .optimized, .basic] {
            try billing.setIntegrationMode(mode)
            let migration = try await AIChatBYOKTransportMigration.prepare(conversation: previous,
                connectionID: connection.id, model: .other("manual-model"), mode: mode, billing: billing,
                consent: consent, registry: registry)
            try require(migration.systemMessage.id == "generated-system")
            try require(!String(decoding: migration.routeData, as: UTF8.self).contains("synthetic-direct-key"))
            try await persistence.migrate(migration)
            let client = mode == .basic
                ? AIInferenceBillingState.makeDirectClient(connectionID: connection.id, configuration: .openAI, session: session)
                : LLMClient(authProvider: SwitchAuthProvider(), baseURL: URL(string: "https://app-switch-test.invalid")!, session: session)
            let state = LLMStateObject(llmClient: client, toolRegistry: registry, persistenceProvider: persistence,
                schemeCredentialsProvider: { id, model in try await billing.credentials(connectionID: id, model: model) })
            await state.refreshConversations()
            guard let restored = state.getConversation(by: legacy.id) else { throw Failure.invalidResult }
            let restoredContents = restored.messages.compactMap { message -> ChatMessageContent? in
                if case .content(let content) = message { return content }; return nil
            }
            try require(restoredContents.contains(user) && restoredContents.contains(summary))
            try require(restored.id == legacy.id && restored.title == legacy.title)
            try require((restored.directConnection != nil) == (mode == .basic))
            try require((restored.agentConfig.agentID == nil) == (mode == .basic))
            let send: @MainActor @Sendable () async throws -> Void = {
                try await state.sendMessage(to: legacy.id, model: .other("manual-model"),
                    message: .content(.init(role: .user, content: "Continue")))
                guard let answer = state.getConversation(by: legacy.id)?.messages.last(where: {
                    if case .content(let content) = $0 { return content.role == .assistant }; return false
                }) else { throw Failure.invalidResult }
                try await state.regenerateMessage(in: legacy.id, fromMessageID: answer.id, model: .other("manual-model"))
            }
            if mode == .basic {
                try await billing.withDirectBilling(billing.directSnapshot(connectionID: connection.id, modelID: "manual-model"), operation: send)
            } else { try await send() }
            let request = SwitchProtocol.store.requests.last!
            try require(request.url?.path == (mode == .basic ? "/v1/chat/completions" : "/schemes/byok/stream"))
            try require(request.value(forHTTPHeaderField: mode == .basic ? "Authorization" : "X-LLM-BYOK-Key")
                        == (mode == .basic ? "Bearer synthetic-direct-key" : "synthetic-direct-key"))
            previous = state.getConversation(by: legacy.id)!
            try require(previous.messages.contains { $0.id == user.id })
        }
    }

    @MainActor
    static func validate() async throws {
        let defaults = SwitchMemoryDefaults()
        let keys = SwitchMemoryKeys()
        let billing = AIInferenceBillingState(defaults: defaults, keyStore: keys)
        let first = try billing.addConnection(.openAI, apiKey: "synthetic-first")
        let second = try billing.addConnection(.openRouter, apiKey: "synthetic-second")
        let consent = AIServiceConsentState(defaults: defaults)
        consent.accept(.platform)
        consent.accept(.byok)
        let platform = AIChatConversationRoute.platformScheme(schemeID: "excalidraw-canvas", profileID: "quality")
        let byok = AIChatConversationRoute.optimizedBYOK(schemeID: "excalidraw-canvas", connectionID: first.id, modelID: "manual-a")
        let other = AIChatConversationRoute.optimizedBYOK(schemeID: "excalidraw-canvas", connectionID: second.id, modelID: "manual-b")
        let seed = Conversation(id: "switch-chat", type: .regular, title: "Keep Me",
            messages: [.content(.init(role: .user, content: "Original question")),
                       .content(.init(role: .assistant, content: "Original answer"))],
            createdAt: .now, lastChatAt: .now, schemeConnection: platform.binding)
        let persistence = SwitchPersistence(seed)
        let options = URLSessionConfiguration.ephemeral
        options.protocolClasses = [SwitchProtocol.self]
        let session = URLSession(configuration: options)
        defer { session.invalidateAndCancel(); SwitchProtocol.store.reset() }
        let client = LLMClient(authProvider: SwitchAuthProvider(), baseURL: URL(string: "https://app-switch-test.invalid")!, session: session)
        let state = LLMStateObject(llmClient: client, persistenceProvider: persistence,
            schemeCredentialsProvider: { id, model in try await billing.credentials(connectionID: id, model: model) })
        await state.refreshConversations()
        var expected = platform
        for target in [byok, other, platform] {
            let before = state.getConversation(by: seed.id)!.messages
            try await AIChatSchemeSwitch.apply(target, in: seed.id, expectedRoute: expected,
                state: state, billing: billing, consent: consent)
            try require(state.getConversation(by: seed.id)?.messages == before)
            try require(state.getConversation(by: seed.id)?.title == "Keep Me")
            try require(try await persistence.binding() == target.binding)
            try await state.sendMessage(to: seed.id, model: .other("hint-only"),
                message: .content(.init(role: .user, content: "Continue")))
            let request = SwitchProtocol.store.requests.last!
            let body = try payload(request)
            let messages = body["messages"] as? [[String: Any]]
            try require(messages?.contains { $0["content"] as? String == "Original question" } == true)
            try require(messages?.contains { $0["content"] as? String == "Original answer" } == true)
            if target.usesBYOK {
                try require(request.url?.path == "/schemes/byok/stream")
                try require(request.value(forHTTPHeaderField: "X-LLM-BYOK-Key") == (target == byok ? "synthetic-first" : "synthetic-second"))
                try require(body["byokModelID"] as? String == target.byokModelID)
            } else {
                try require(request.url?.path == "/schemes/stream")
                try require(request.value(forHTTPHeaderField: "X-LLM-BYOK-Key") == nil)
                try require((body["scheme"] as? [String: Any])?["profileID"] as? String == "quality")
            }
            expected = target
        }
        // Saving a switch must not silently change the defaults for other conversations.
        try require(billing.mode == .platform && billing.selectedProfileID == second.id)
        let history = state.getConversation(by: seed.id)!.messages
        await state.refreshConversations()
        try require(state.getConversation(by: seed.id)?.messages == history)

        let requestsBeforeFailure = SwitchProtocol.store.requests.count
        keys.values[first.id] = nil
        do {
            try await AIChatSchemeSwitch.apply(byok, in: seed.id, expectedRoute: platform,
                state: state, billing: billing, consent: consent)
            throw Failure.expectedRejection
        } catch AIInferenceBillingError.missingKey {}
        try require(state.getConversation(by: seed.id)?.schemeConnection == platform.binding)
        try require(SwitchProtocol.store.requests.count == requestsBeforeFailure)

        await persistence.failUpdates()
        do {
            try await AIChatSchemeSwitch.apply(other, in: seed.id, expectedRoute: platform,
                state: state, billing: billing, consent: consent)
            throw Failure.expectedRejection
        } catch Failure.write {}
        try require(state.getConversation(by: seed.id)?.schemeConnection == platform.binding)
        try require(try await persistence.binding() == platform.binding)
        try require(state.getConversation(by: seed.id)?.messages == history)
        try require(!billing.isBusy)
    }

    private static func require(_ condition: Bool) throws { if !condition { throw Failure.invalidResult } }
    fileprivate enum Failure: Error { case invalidResult, expectedRejection, write }

    fileprivate static func payload(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let input = request.httpBodyStream {
            input.open(); defer { input.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while input.hasBytesAvailable {
                let count = input.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                data.append(contentsOf: bytes.prefix(count))
            }
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

private final class SwitchMemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}
private final class SwitchMemoryKeys: AIInferenceKeyStoring {
    var values: [String: String] = [:]
    func readKey(for account: String) throws -> String? { values[account] }
    func saveKey(_ key: String, for account: String) throws { values[account] = key }
    func removeKey(for account: String) throws { values[account] = nil }
}
private struct SwitchAuthProvider: LLMAuthProvider {
    let networking = LLMNetworking()
    func restoreAuth() async throws -> String { "synthetic-app-token" }
    func handlePurchase(transactionJWS: String) async throws -> CreditsInfo { .init(balance: 0, purchasedCredits: 0) }
}
private actor SwitchPersistence: LLMSchemeConversationPersistenceProvider {
    private var saved: Conversation
    private var route: Data?
    private var fail = false
    init(_ conversation: Conversation, directRecord: AIDirectConversationRecord? = nil) {
        saved = conversation
        route = try! directRecord.map(AIChatRouteStorage.encodeDirect) ?? AIChatRouteStorage.encode(conversation.schemeConnection)
    }
    func binding() throws -> LLMSchemeConversationBinding? { try AIChatRouteStorage.decode(route) }
    func failUpdates() { fail = true }
    func restoreConversations() throws -> [Conversation] {
        saved.schemeConnection = try binding()
        saved.directConnection = try AIChatRouteStorage.decodeDirect(route)?.binding
        return [saved]
    }
    func migrate(_ migration: AIChatBYOKTransportMigration) throws {
        route = migration.routeData
        saved.schemeConnection = migration.schemeBinding
        saved.directConnection = migration.directRecord?.binding
        let tools = ExcalidrawAgentConfig.decodeToolNames(migration.toolsData)
        saved.agentConfig = migration.directRecord != nil
            ? ExcalidrawAgentConfig.basicConfig(tools: tools) : ExcalidrawAgentConfig.defaultConfig(tools: tools)
        if let index = saved.messages.firstIndex(where: { $0.id == migration.systemMessage.id }) {
            saved.messages[index] = .content(migration.systemMessage)
        } else { saved.messages.insert(.content(migration.systemMessage), at: 0) }
    }
    func updateSchemeConnection(_ binding: LLMSchemeConversationBinding, in conversationID: String) throws {
        if fail { throw AppSchemeSwitchFixture.Failure.write }
        route = try AIChatRouteStorage.encode(binding)
        saved.schemeConnection = binding
    }
    func updateConversation(action: ConversationUpdateAction) {
        guard case .update(_, let change) = action else { return }
        switch change {
        case .insert(let messages):
            for message in messages {
                if let index = saved.messages.firstIndex(where: { $0.id == message.id }) { saved.messages[index] = message }
                else { saved.messages.append(message) }
            }
        case .update(let message):
            if let index = saved.messages.firstIndex(where: { $0.id == message.id }) { saved.messages[index] = message }
        case .updateTitle(let title): saved.title = title
        case .delete(let ids): saved.messages.removeAll { ids.contains($0.id) }
        }
    }
}

private final class SwitchProtocol: URLProtocol, @unchecked Sendable {
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [URLRequest] = []
        private var acknowledges = true
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return values }
        var acknowledgesSearch: Bool { lock.lock(); defer { lock.unlock() }; return acknowledges }
        func setAcknowledgesSearch(_ value: Bool) { lock.lock(); defer { lock.unlock() }; acknowledges = value }
        func reset() { lock.lock(); defer { lock.unlock() }; values = []; acknowledges = true }
        func record(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; values.append(request) }
    }
    static let store = Store()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.store.record(request)
            let isDirect = request.url?.path == "/v1/chat/completions"
            let isStream = isDirect || request.url?.path.hasSuffix("/stream") == true
            let body: Data
            if request.url?.path == "/access/evaluate" {
                body = try JSONEncoder().encode(LLMAccessDecision(allowed: true, requirementIDs: [], missingRequirementIDs: []))
            } else if isDirect {
                body = Data("data: {\"id\":\"direct\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Answer\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8)
            } else if isStream {
                body = Data("data: ".utf8) + (try JSONEncoder().encode(ChatMessageContent(role: .assistant, content: "Answer")))
                    + Data("\n\ndata: [DONE]\n\n".utf8)
            } else {
                let scheme = LLMSchemeDescriptor(id: "excalidraw-canvas", name: "Canvas", summary: "", kind: .conversation,
                    defaultProfileID: "quality", profiles: [.init(id: "quality", name: "Quality", rank: 0, modelID: "platform/model")])
                body = try JSONEncoder().encode(scheme)
            }
            var headers = ["Content-Type": isStream ? "text/event-stream" : "application/json"]
            if Self.store.acknowledgesSearch,
               let encoded = request.value(forHTTPHeaderField: "X-LLM-BYOK-Configuration"),
               let data = Data(base64Encoded: encoded),
               let configuration = try? JSONDecoder().decode(LLMBYOKConfiguration.self, from: data),
               let search = configuration.webSearch, search.isEnabled {
                headers[LLMBYOKWebSearch.acknowledgementHeader] = search.adapter.rawValue
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
