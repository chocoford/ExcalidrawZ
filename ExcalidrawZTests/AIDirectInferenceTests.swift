import Foundation
import LLMCore
import LLMKit
import XCTest
@testable import ExcalidrawZ

final class AIDirectInferenceTests: XCTestCase {
    @MainActor
    func testDirectStateUsesFrozenCredentialsAndLocalTools() async throws {
        try await DirectAppIntegrationFixture.validate()
    }

    @MainActor
    func testUpstreamSearchRetainsNativeToolsAndSkipsAuxiliaryOptIn() async throws {
        try await DirectAppIntegrationFixture.validateSearch()
    }
}

/// Uses synthetic credentials and URLProtocol; no provider or App backend is contacted.
enum DirectAppIntegrationFixture {
    @MainActor
    static func validateSearch() async throws {
        let options = URLSessionConfiguration.ephemeral
        options.protocolClasses = [AppDirectProtocol.self]
        let session = URLSession(configuration: options)
        defer { session.invalidateAndCancel(); AppDirectProtocol.store.reset() }
        for (preset, modelID) in [(LLMBYOKPreset.openRouter, "xiaomi/mimo-v2.6-pro"), (.openAI, "gpt-4o-search-preview"),
                                  (.dashScope, "qwen-max"), (.groq, "groq/compound")] {
            AppDirectProtocol.store.reset()
            var saved = preset.configuration
            saved.defaultModel = nil
            saved.options.auxiliaryModel = nil
            let configuration = try AIInferenceConnection.preset(preset)
                .configurationWithWebSearchSupport(saved).withWebSearch(enabled: true)
            let snapshot = AIDirectCredentialSnapshot(connectionID: "search-test", configuration: configuration,
                modelID: modelID, apiKey: "synthetic-search-key")
            let client = AIInferenceBillingState.makeDirectClient(connectionID: snapshot.connectionID,
                configuration: configuration, session: session)
            let registry = ToolRegistry()
            let probe = AppDirectToolProbe()
            await registry.register(AppDirectTool(probe: probe))
            let state = LLMStateObject(llmClient: client, toolRegistry: registry, persistenceProvider: nil)
            await state.refreshConversations()
            try await AIInferenceBilling.$directSnapshot.withValue(snapshot) {
                try await state.createConversation(id: "search-chat", model: .other(modelID),
                    agentConfig: ExcalidrawAgentConfig.basicConfig(tools: ["draw"]),
                    messages: [.content(.init(role: .user, content: "Draw using upstream information"))])
            }
            try require(await probe.calls == 1, "Only the registered local tool is executed in the App")
            let requests = AppDirectProtocol.store.requests
            let streamed = requests.filter { $0.body["stream"] as? Bool == true }
            try require(streamed.count == 2)
            for request in requests {
                try require(request.request.url?.host == configuration.baseURL.host)
                try require(request.request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-search-key")
                try require(request.request.value(forHTTPHeaderField: "X-LLM-BYOK-Key") == nil)
            }
            for request in streamed {
                let body = request.body
                let tools = body["tools"] as? [[String: Any]] ?? []
                try require(tools.contains { $0["type"] as? String == "function" })
                try require(body["tool_choice"] == nil && body["plugins"] == nil)
                try require(body["model"] as? String == configuration.modelMapping.resolve(modelID))
                let messages = body["messages"] as? [[String: Any]] ?? []
                try require(messages.first?["role"] as? String == "system")
                try require((messages.first?["content"] as? String)?.contains("Provider-hosted web search is enabled for this request.") == true,
                            "Every tool round describes the currently enabled upstream capability")
                switch preset {
                case .openRouter: try require(tools.filter { $0["type"] as? String == "openrouter:web_search" }.count == 1)
                case .openAI: try require(body["web_search_options"] as? [String: Any] != nil)
                case .dashScope: try require(body["enable_search"] as? Bool == true)
                case .groq: try require(tools.filter { $0["type"] as? String == "browser_search" }.count == 1)
                default: throw Failure.invalidResult
                }
            }
            let auxiliary = requests.filter { $0.request.httpMethod == "POST" && $0.body["stream"] as? Bool != true }
            try require(!auxiliary.isEmpty)
            for request in auxiliary {
                let tools = request.body["tools"] as? [[String: Any]] ?? []
                try require(request.body["enable_search"] == nil && request.body["web_search_options"] == nil)
                try require(!tools.contains { ["browser_search", "openrouter:web_search"].contains($0["type"] as? String ?? "") })
                let messages = request.body["messages"] as? [[String: Any]] ?? []
                try require(!messages.contains { ($0["content"] as? String)?.contains("Provider-hosted web search is enabled for this request.") == true },
                            "Auxiliary requests do not claim search is enabled")
            }
        }
    }

    @MainActor
    static func validate() async throws {
        let configuration = LLMBYOKConfiguration(baseURL: URL(string: "https://direct-app-test.invalid/v1/")!)
        let snapshot = AIDirectCredentialSnapshot(connectionID: "test-connection", configuration: configuration,
                                                  modelID: "manual-model", apiKey: "synthetic-direct-key")
        let options = URLSessionConfiguration.ephemeral
        options.protocolClasses = [AppDirectProtocol.self]
        let session = URLSession(configuration: options)
        defer { session.invalidateAndCancel(); AppDirectProtocol.store.reset() }
        let client = AIInferenceBillingState.makeDirectClient(connectionID: snapshot.connectionID,
                                                              configuration: configuration, session: session)
        let probe = AppDirectToolProbe()
        let registry = ToolRegistry()
        await registry.register(AppDirectTool(probe: probe))
        let state = LLMStateObject(llmClient: client, toolRegistry: registry, persistenceProvider: nil)
        await state.refreshConversations()
        try await AIInferenceBilling.$directSnapshot.withValue(snapshot) {
            let models = try await client.listBYOKModels()
            try require(models.map(\.id) == ["manual-model"])
            try await state.createConversation(id: "direct-chat", model: .other("manual-model"),
                agentConfig: ExcalidrawAgentConfig.basicConfig(tools: ["draw"]),
                messages: [.content(.init(role: .user, content: "Draw"))])
            try require(await probe.calls == 1)
            guard let conversation = state.getConversation(by: "direct-chat") else { throw Failure.invalidResult }
            try require(conversation.directConnection?.configuration == configuration)
            try require(conversation.schemeConnection == nil && conversation.agentConfig.agentID == nil)
            try require(conversation.messages.contains { $0.content == "Drawn" })
            try require(!conversation.messages.contains { $0.content?.contains("Provider-hosted web search is enabled for this request.") == true })
            guard let reply = conversation.messages.last(where: { $0.content == "Drawn" }) else { throw Failure.invalidResult }
            let usage = conversation.usageSummary(forMessageID: reply.id)
            try require(usage.tokens == .init(promptTokens: 30, completionTokens: 10, totalTokens: 40))
            try require(usage.requestCount == 2 && usage.isComplete)
            try require(usage.providerToolUsage?["web_search_requests"] == 3)
            try require(reply.citations == [.init(url: URL(string: "https://sources.example/direct")!, title: "Upstream source")])
            try require(state.creditsInfo == nil)
            let data = try AIChatRouteStorage.encodeDirect(.init(connectionID: snapshot.connectionID,
                                                                 binding: conversation.directConnection!))
            let restored = try AIChatRouteStorage.decodeDirect(data)
            try require(restored?.connectionID == snapshot.connectionID)
            try require(restored?.binding == conversation.directConnection)
            try require(try AIChatRouteStorage.decode(data) == nil)
            try require(!String(decoding: data, as: UTF8.self).contains("synthetic-direct-key"))
            // New UI selection / a different client must never reuse this in-flight request's key.
            let mismatch = AIInferenceBillingState.makeDirectClient(connectionID: "different-connection",
                                                                  configuration: configuration, session: session)
            do {
                _ = try await mismatch.listBYOKModels()
                throw Failure.expectedRejection
            } catch LLMDirectError.conversationConnectionMismatch {}
        }
        let requests = AppDirectProtocol.store.requests
        let streamed = requests.filter { $0.body["stream"] as? Bool == true }
        try require(streamed.count == 2)
        for item in requests {
            try require(item.request.url?.host == "direct-app-test.invalid")
            try require(["/v1/models", "/v1/chat/completions"].contains(item.request.url?.path ?? ""))
            try require(item.request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-direct-key")
            try require(item.request.value(forHTTPHeaderField: "X-LLM-BYOK-Key") == nil)
            try require(item.body["agentID"] == nil && item.body["metadata"] == nil)
            try require(item.body["plugins"] == nil && item.body["web_search_options"] == nil)
            let tools = item.body["tools"] as? [[String: Any]] ?? []
            try require(tools.allSatisfy { $0["type"] as? String == "function" }, "No hosted search declaration is added")
        }
        let messages = streamed.last?.body["messages"] as? [[String: Any]]
        try require(messages?.contains { $0["role"] as? String == "tool" && $0["tool_call_id"] as? String == "call-1" } == true)
        let tools = ExcalidrawAgentConfig.basicConfig(tools: nil).tools
        try require(tools.contains("read_me") && !tools.contains("web_search") && !tools.contains("web_fetch"))

        // An unfinished response must not execute its partially streamed tool call.
        AppDirectProtocol.store.reset(truncated: true)
        let executor = AgentExecutor(llmProvider: client, toolRegistry: registry)
        do {
            try await AIInferenceBilling.$directSnapshot.withValue(snapshot) {
                let stream = try await executor.execute(conversationID: "truncated", agentConfig: .withTools(["draw"]),
                    contextMessages: [.init(role: .user, content: "Draw")], model: .other("manual-model"))
                for try await _ in stream {}
            }
            throw Failure.expectedRejection
        } catch is LLMChatCompletionsError {}
        try require(await probe.calls == 1)
    }

    private static func require(_ condition: Bool, _ message: String = "Direct regression", line: UInt = #line) throws {
        if !condition { throw Failure.assertion("\(message) at line \(line)") }
    }
    private enum Failure: Error { case invalidResult, expectedRejection, assertion(String) }
}

private actor AppDirectToolProbe { var calls = 0; func record() { calls += 1 } }
private struct AppDirectTool: Tool {
    let probe: AppDirectToolProbe
    let name = "draw"
    let description = "Draw locally"
    var inputSchema: ToolInputSchema { .parameters(.init(properties: [:])) }
    func execute(_ input: String, context: (any ChatInvocationContext)?) async throws -> ToolResult {
        await probe.record()
        return .text("drawn")
    }
}

private final class AppDirectProtocol: URLProtocol, @unchecked Sendable {
    struct Request { let request: URLRequest; let body: [String: Any] }
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Request] = []
        private var round = 0
        private var truncated = false
        var requests: [Request] { lock.lock(); defer { lock.unlock() }; return values }
        func reset(truncated: Bool = false) {
            lock.lock(); defer { lock.unlock() }
            values = []; round = 0; self.truncated = truncated
        }
        func response(for request: URLRequest) throws -> (body: String, sse: Bool) {
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
            let body = data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            lock.lock(); defer { lock.unlock() }
            values.append(.init(request: request, body: body))
            if request.httpMethod == "GET" { return (#"{"data":[{"id":"manual-model"}]}"#, false) }
            if body["stream"] as? Bool != true {
                return (#"{"id":"title","choices":[{"index":0,"message":{"role":"assistant","content":"Local Drawing"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1000,"completion_tokens":100,"total_tokens":1100}}"#, false)
            }
            round += 1
            let delta = round == 1
                ? #"{"tool_calls":[{"index":0,"id":"call-1","type":"function","function":{"name":"draw","arguments":"{}"}}]}"#
                : #"{"content":"Drawn"}"#
            let reason = round == 1 ? "tool_calls" : "stop"
            let responseID = "round-\(round)"
            let sources = round == 2 ? #","citations":[{"url":"https://sources.example/direct","title":"Upstream source"}]"# : ""
            let stats = "data: {\"id\":\"\(responseID)\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\",\"role\":\"assistant\"},\"finish_reason\":\"\(reason)\"}],\"usage\":{\"prompt_tokens\":\(round * 10),\"completion_tokens\":5,\"total_tokens\":\(round * 10 + 5),\"server_tool_use\":{\"web_search_requests\":\(round)}}\(sources)}\n\n"
            return ("data: {\"id\":\"\(responseID)\",\"choices\":[{\"index\":0,\"delta\":\(delta),\"finish_reason\":\"\(reason)\"}]}\n\n" + stats + stats + (truncated ? "" : "data: [DONE]\n\n"), true)
        }
    }
    static let store = Store()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let result = try Self.store.response(for: request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": result.sse ? "text/event-stream" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(result.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
