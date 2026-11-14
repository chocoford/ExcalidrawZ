import Foundation
import LLMCore
import LLMKit

/// A snapshot inherited by SDK Agent rounds, title generation and automatic compaction.
/// Never encode this value or attach it to conversation/transaction metadata.
enum AIInferenceBillingSelection: Sendable {
    case platform
    case byok(LLMBYOKCredentials)

    var credentials: LLMBYOKCredentials? {
        switch self {
            case .platform: nil
            case .byok(let credentials): credentials
        }
    }
}

enum AIInferenceBilling {
    @TaskLocal static var selection: AIInferenceBillingSelection?
    @TaskLocal static var directSnapshot: AIDirectCredentialSnapshot?

    static func credentialsForRequest(for model: SupportedModel) async throws -> LLMBYOKCredentials? {
        guard directSnapshot == nil else { throw LLMDirectError.unsupportedCapability("backend inference in Basic mode") }
        let selected: AIInferenceBillingSelection
        if let selection {
            selected = selection
        } else {
            guard !AIChatAvailability.usesDirectInference else {
                throw LLMDirectError.unsupportedCapability("backend inference in Basic mode")
            }
            selected = try await AIInferenceBillingState.shared.resolveSelection()
        }
        if let configuration = selected.credentials?.configuration {
            _ = try configuration.modelMapping.resolve(model.rawValue)
        }
        return selected.credentials
    }
}
