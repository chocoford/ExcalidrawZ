//
//  ExcalidrawCore+UserSettings.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/04.
//

import Foundation
import WebKit

extension ExcalidrawCore {
    /// Apply user drawing settings to Excalidraw
    /// This method should be called after file load is complete
    @MainActor
    func applyUserSettings() async throws {
        guard let appPreference = self.parent?.appPreference,
              appPreference.useCustomDrawingSettings else {
            logger.debug("Custom drawing settings not enabled, skipping apply")
            return
        }
        
        let settings = appPreference.customDrawingSettings
        
        guard let jsonString = settings.toJSONString() else {
            logger.error("Failed to convert settings to JSON string")
            return
        }
        
        let js = "window.excalidrawZHelper?.applyUserSettings(\(jsonString)); 0;"
        _ = try await self.webView.evaluateJavaScript(js)
        self.logger.info("User settings applied successfully: \(jsonString)")
    }
    
    /// Fetch current drawing settings from Excalidraw
    /// Returns the current user drawing settings from the web view
    @MainActor
    func fetchCurrentUserSettings() async throws -> UserDrawingSettings {
        let js = "window.excalidrawZHelper?.getUserSettings()"
        let result = try await self.webView.evaluateJavaScript(js)
        guard let settingsDict = result as? [String: Any] else {
            throw UserSettingsError.invalidResponse
        }
        let settings = UserDrawingSettings.from(dict: settingsDict)
        return settings
    }
}

enum UserSettingsError: LocalizedError {
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
            case .invalidResponse:
                return "Invalid response when fetching user settings"
        }
    }
}
