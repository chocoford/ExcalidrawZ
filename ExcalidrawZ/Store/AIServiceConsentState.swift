import Foundation
import Combine

/// Device-local, versioned permission for each AI service mode.
@MainActor
final class AIServiceConsentState: ObservableObject {
    static let shared = AIServiceConsentState()
    static let defaultsKey = "AIChat.serviceConsentVersions"
    private static let currentVersion = 1

    @Published private(set) var acceptedVersions: [String: Int]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        acceptedVersions = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
        // Existing releases asked for permission before enabling the platform service.
        // That permission must not be inferred for BYOK.
        if defaults.object(forKey: Self.defaultsKey) == nil,
           defaults.object(forKey: AIChatPreferences.isAIEnabledDefaultsKey) as? Bool == true,
           Self.selectedMode(in: defaults) == .platform {
            acceptedVersions[AIInferenceBillingMode.platform.rawValue] = Self.currentVersion
            defaults.set(acceptedVersions, forKey: Self.defaultsKey)
        }
    }

    func hasAccepted(_ mode: AIInferenceBillingMode) -> Bool {
        acceptedVersions[mode.rawValue] == Self.currentVersion
    }

    var hasAcceptedSelectedMode: Bool {
        guard let mode = Self.selectedMode(in: defaults) else { return false }
        return hasAccepted(mode)
    }

    func accept(_ mode: AIInferenceBillingMode) {
        acceptedVersions[mode.rawValue] = Self.currentVersion
        defaults.set(acceptedVersions, forKey: Self.defaultsKey)
    }

    static func selectedMode(in defaults: UserDefaults = .standard) -> AIInferenceBillingMode? {
        guard let raw = defaults.string(forKey: AIInferenceBillingState.modeDefaultsKey) else { return .platform }
        return raw == "openRouter" ? .byok : AIInferenceBillingMode(rawValue: raw)
    }
}
