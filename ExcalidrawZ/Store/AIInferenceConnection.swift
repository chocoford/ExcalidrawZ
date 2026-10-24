import Foundation
import LLMCore

enum AIInferenceConnection: RawRepresentable, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case preset(LLMBYOKPreset)
    case custom

    static let openAI = Self.preset(.openAI)
    static let anthropic = Self.preset(.anthropic)
    static let gemini = Self.preset(.gemini)
    static let openRouter = Self.preset(.openRouter)

    static var allCases: [Self] {
        let preferred: [LLMBYOKPreset] = [.openAI, .anthropic, .gemini, .openRouter]
        let remaining = LLMBYOKPreset.allCases.filter { !preferred.contains($0) }
        return (preferred + remaining).map(Self.preset) + [.custom]
    }

    var id: Self { self }

    var rawValue: String {
        switch self {
            case .preset(let preset): preset.rawValue
            case .custom: "custom"
        }
    }

    init?(rawValue: String) {
        if rawValue == "custom" {
            self = .custom
        } else if let preset = LLMBYOKPreset(rawValue: rawValue) {
            self = .preset(preset)
        } else if ["fireworks", "zai", "zhipu", "volcengine"].contains(rawValue) {
            // Removed presets retain their saved configuration and account identity as Custom.
            self = .custom
        } else {
            return nil
        }
    }

    // Preserve the provider strings already stored in connection profiles and Keychain IDs.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let connection = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown BYOK provider.")
        }
        self = connection
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var title: String {
        switch self {
            case .preset(let preset): preset.displayName
            case .custom: String(localizable: .aiBYOKCustomConnection)
        }
    }

    var presetConfiguration: LLMBYOKConfiguration? {
        switch self {
            case .preset(let preset): preset.configuration
            case .custom: nil
        }
    }
}

/// A saved account or endpoint. Credentials use this identity as their Keychain account.
struct AIInferenceConnectionProfile: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    let provider: AIInferenceConnection
    var configuration: LLMBYOKConfiguration?
    var lastModelID: String?

    var displayName: String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? provider.title : name
    }
}
