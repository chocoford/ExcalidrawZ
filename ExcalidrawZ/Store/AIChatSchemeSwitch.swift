import Foundation
import LLMCore
import LLMKit

/// A user-selected change to an existing conversation, independent of new-chat defaults.
enum AIChatSchemeSwitch {
    @MainActor
    static func apply(_ route: AIChatConversationRoute, in conversationID: String,
                      expectedRoute: AIChatConversationRoute,
                      state: LLMStateObject, billing: AIInferenceBillingState,
                      consent: AIServiceConsentState) async throws {
        guard !billing.isBusy, !state.isRunning(conversationID: conversationID) else {
            throw LLMSchemeStateError.generationInProgress
        }
        guard let conversation = state.getConversation(by: conversationID),
              conversation.directConnection == nil,
              let previous = conversation.schemeConnection,
              try AIChatConversationRoute(binding: previous) == expectedRoute else {
            throw AIInferenceBillingError.selectionChanged
        }
        guard let binding = route.binding, binding.selection.schemeID == previous.selection.schemeID else {
            throw LLMSchemeStateError.connectionMismatch
        }
        guard consent.hasAccepted(route.usesBYOK ? .byok : .platform) else {
            throw AIChatRoutingError.consentRequired
        }
        // Resolve the exact destination before saving. A missing key leaves the old route intact.
        // Access remains authoritative on the server when the next request executes.
        _ = try billing.resolveSelection(for: binding)
        try await billing.withInferenceOperation {
            try await state.updateSchemeConnection(binding, in: conversationID)
        }
    }
}

/// Freeze the sheet's destination; editing defaults or changing files cannot retarget its Save.
struct AIChatBYOKPickerTarget: Identifiable {
    let id = UUID()
    let conversationID: String?
    let draftKey: String
    let expectedRoute: AIChatConversationRoute?
    let connectionID: String
    let integrationMode: AIInferenceIntegrationMode
    let selectedModelID: String
    let billingRevision: Int
}
