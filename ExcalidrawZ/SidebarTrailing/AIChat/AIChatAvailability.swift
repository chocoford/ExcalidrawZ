//
//  AIChatAvailability.swift
//  ExcalidrawZ
//

import Foundation

// Build-flavor and user-preference gates for AI chat surfaces.

enum AIChatAvailability {
    static var isAvailable: Bool {
        true
    }

    static var supportsManagedInference: Bool {
        #if APP_STORE || DEBUG
        true
        #else
        false
        #endif
    }

    static var isUserEnabled: Bool {
        UserDefaults.standard.object(forKey: AIChatPreferences.isAIEnabledDefaultsKey) as? Bool ?? false
    }

    static var usesDirectInference: Bool {
        guard supportsManagedInference else { return true }
        let mode = UserDefaults.standard.string(forKey: AIInferenceBillingState.modeDefaultsKey)
        guard mode == "byok" || mode == "openRouter",
              let integration = UserDefaults.standard.string(forKey: AIInferenceBillingState.integrationModeDefaultsKey) else { return false }
        return integration != "optimized"
    }

    static var canUseAI: Bool {
        guard isAvailable, isUserEnabled else { return false }
        if supportsManagedInference { return true }
        let mode = UserDefaults.standard.string(forKey: AIInferenceBillingState.modeDefaultsKey)
        return mode == "byok" || mode == "openRouter"
    }
}
