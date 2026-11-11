import Foundation
import LLMCore
import LLMKit

/// App-owned migration between the local Direct client and the server Scheme client.
/// Only the generated system prompt changes; user/assistant/tool history keeps its IDs and order.
struct AIChatBYOKTransportMigration: Sendable {
    let conversationID: String
    let routeData: Data
    let toolsData: Data?
    let systemMessage: ChatMessageContent
    let directRecord: AIDirectConversationRecord?
    let schemeBinding: LLMSchemeConversationBinding?

    @MainActor
    static func prepare(conversation: Conversation, connectionID: String, model: SupportedModel,
                        mode: AIInferenceIntegrationMode, billing: AIInferenceBillingState,
                        consent: AIServiceConsentState, registry: ToolRegistry) async throws -> Self {
        guard consent.hasAccepted(.byok) else { throw AIChatRoutingError.consentRequired }
        _ = try billing.credentials(connectionID: connectionID, model: model)
        guard let configuration = billing.profiles.first(where: { $0.id == connectionID })?.configuration else {
            throw AIInferenceBillingError.missingConnection
        }
        let isDirect = mode == .basic
        let config = isDirect
            ? ExcalidrawAgentConfig.basicConfig(tools: conversation.agentConfig.tools)
            : ExcalidrawAgentConfig.defaultConfig(tools: conversation.agentConfig.tools.filter { $0 != "read_me" })
        let description = await registry.generateToolsDescription(for: config.tools, nativeToolCalls: isDirect)
        let prompt = [config.prompt, description].filter { !$0.isEmpty }.joined(separator: "\n\n")
        // Compaction summaries are conversation history, even when their role is system.
        let generatedSystem = conversation.messages.compactMap { message -> ChatMessageContent? in
            guard case .content(let content) = message, content.role == .system, !content.isCompactSummary else { return nil }
            return content
        }.first
        var systemMessage = generatedSystem ?? .init(role: .system)
        systemMessage.content = prompt
        systemMessage.isCompactedOut = false
        let direct = isDirect ? AIDirectConversationRecord(connectionID: connectionID,
            binding: .init(configuration: configuration, chatModel: SupportedModel(rawValue: model.rawValue))) : nil
        let scheme: LLMSchemeConversationBinding? = isDirect ? nil : .init(
            selection: .init(schemeID: AIChatSchemeCatalog.schemeID),
            billing: .byok(model: SupportedModel(rawValue: model.rawValue)), connectionID: connectionID)
        // Validate without persisting the request credential (which contains auxiliary hints).
        let routeData: Data
        if let direct { routeData = try AIChatRouteStorage.encodeDirect(direct) }
        else if let data = try AIChatRouteStorage.encode(scheme) { routeData = data }
        else { throw AIChatRoutingError.invalidRoute }
        return .init(conversationID: conversation.id,
            routeData: routeData,
            toolsData: ExcalidrawAgentConfig.encodeToolNames(config.tools), systemMessage: systemMessage,
            directRecord: direct, schemeBinding: scheme)
    }
}
