import Foundation
import LLMKit
import LLMCore

/// Only known, credential-free SDK/server errors receive BYOK-specific presentation.
@MainActor
enum AIInferenceErrorMessage {
    struct Message: LocalizedError {
        let text: String
        var errorDescription: String? { text }
    }

    static func localizedError(for error: Error) -> (any Error)? {
        if let error = error as? AIInferenceBillingError {
            return Message(text: error.localizedDescription)
        }
        if error is LLMBYOKWebSearchError {
            return Message(text: String(localizable: .aIWebSearchUnsupported))
        }
        if let error = error as? LLMBYOKConfigurationValidationError {
            switch error {
                case .invalidEndpoint:
                    return Message(text: String(localizable: .aiBYOKInvalidEndpoint))
                case .invalidModel:
                    return Message(text: String(localizable: .aiBYOKIncompatibleModel))
                case .invalidConfiguration, .unsupportedVersion:
                    return Message(text: String(localizable: .aiBYOKInvalidConfiguration))
                @unknown default:
                    return Message(text: String(localizable: .aiBYOKInvalidConfiguration))
            }
        }
        if let error = error as? LLMBYOKConfigurationError {
            switch error {
                case .invalidAPIKey:
                    return Message(text: String(localizable: .aiBYOKInvalidKey))
                case .insecureConnection:
                    return Message(text: String(localizable: .aiBYOKSecureConnectionRequired))
                case .unsupportedEndpoint:
                    return Message(text: String(localizable: .aiBYOKServiceUnavailable))
                case .providerRequired:
                    return Message(text: String(localizable: .aiBYOKInvalidConfiguration))
                case .modelDiscoveryUnsupported:
                    return Message(text: String(localizable: .aiBYOKModelListDisabled))
                case .invalidModelList:
                    return Message(text: String(localizable: .aiBYOKModelListFailed))
                @unknown default:
                    return Message(text: String(localizable: .aiBYOKProviderFailed))
            }
        }
        guard let error = error as? LLMError else { return nil }
        switch error {
            case .network(let underlying), .decoding(let underlying):
                if [
                    "LLMServer returned an invalid BYOK stream frame.",
                    "The BYOK stream ended before its completion marker. Please retry.",
                ].contains(underlying.localizedDescription) {
                    return Message(text: String(localizable: .aiBYOKProviderFailed))
                }
            default: break
        }
        if case .forbidden(let reason) = error,
           reason == "This custom BYOK endpoint must be approved by the server before using a Domain Agent." {
            return Message(text: String(localizable: .aiBYOKUntrustedAgentHost))
        }
        guard case .server(let status, let message) = error else { return nil }
        if status == 501, message == "This LLMServer version did not acknowledge upstream web search. The request may already have incurred upstream charges. No fallback was attempted." {
            return Message(text: String(localizable: .aIWebSearchServerUnsupported))
        }
        if status == 404, AIInferenceBillingState.shared.usesBYOK {
            return Message(text: String(localizable: .aiBYOKServiceUnavailable))
        }
        guard let message else { return nil }
        if status == 400 {
            switch message {
                case "This model is not supported by the selected BYOK provider. Select a matching chat model.":
                    return Message(text: String(localizable: .aiBYOKIncompatibleModel))
                case "The BYOK endpoint must resolve only to public IP addresses.":
                    return Message(text: String(localizable: .aiBYOKInvalidEndpoint))
                case "The BYOK connection configuration is invalid or unsupported.":
                    return Message(text: String(localizable: .aiBYOKInvalidConfiguration))
                case "The BYOK API key is missing or invalid.":
                    return Message(text: String(localizable: .aiBYOKInvalidKey))
                default: return nil
            }
        }
        guard status == 502 else { return nil }
        switch message {
            case "BYOK provider authentication failed. Check your API key and its permissions.",
                 "BYOK OpenRouter authentication failed. Check your API key and its permissions.":
                return Message(text: String(localizable: .aiBYOKProviderAuthenticationFailed))
            case "Your BYOK provider account has insufficient credits.",
                 "Your BYOK OpenRouter account has insufficient credits.":
                return Message(text: String(localizable: .aiBYOKProviderInsufficientCredits))
            case "Your BYOK provider account is rate limited. Try again later.",
                 "Your BYOK OpenRouter account is rate limited. Try again later.":
                return Message(text: String(localizable: .aiBYOKProviderRateLimited))
            default:
                guard message.hasPrefix("BYOK OpenRouter ")
                    || message.hasPrefix("The BYOK provider ")
                    || message == "The provider returned an invalid BYOK response."
                    || message == "Could not complete the BYOK provider connection. Please retry."
                    || message.hasPrefix("OpenRouter returned ")
                    || message.hasPrefix("The BYOK OpenRouter ")
                    || message == "Could not complete the BYOK OpenRouter connection. Please retry." else {
                    return nil
                }
                return Message(text: String(localizable: .aiBYOKProviderFailed))
        }
    }
}
