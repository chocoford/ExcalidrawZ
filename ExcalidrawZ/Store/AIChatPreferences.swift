//
//  AIChatPreferences.swift
//  ExcalidrawZ
//
//  Device-local AI activation and per-file visibility preferences.
//  New conversation defaults live in AIChatRoutingState; LLMKit owns saved Scheme routes.
//

import Observation
import Foundation
import LLMCore

enum AIChatInteractionMode: String, Codable, Sendable {
    case ask
    case agent

    var usesMutationSession: Bool {
        self == .agent
    }
}

@MainActor
@Observable
final class AIChatPreferences {
    static let shared = AIChatPreferences()
    nonisolated static let isAIEnabledDefaultsKey = "AIChat.isEnabled"

    /// Master switch for AI features. When off, AI chat surfaces show
    /// an opt-in screen and no AI network refresh should be triggered.
    var isAIEnabled: Bool {
        didSet {
            saveIsAIEnabled()
            guard oldValue != isAIEnabled else { return }
            let isAIEnabled = isAIEnabled
            Task {
                await LLMServiceActivationCoordinator.shared.handleAIEnabledChanged(isAIEnabled)
            }
        }
    }

    /// Legacy storage values: `.agent` means AI can access and edit the
    /// current file, while `.ask` means no current-file access and edits
    /// go through a proposal canvas.
    var interactionMode: AIChatInteractionMode {
        didSet { saveInteractionMode() }
    }

    var allowsFileAccess: Bool {
        get { interactionMode == .agent }
        set { interactionMode = newValue ? .agent : .ask }
    }

    /// Per-file AI visibility overrides. Missing value means "use the safe
    /// default": unlocked files are visible to AI, locked files are forced
    /// invisible by the caller's lock-state check.
    private(set) var fileAccessOverrides: [String: Bool]

    private let interactionModeKey = "AIChat.interactionMode"
    private let fileAccessOverridesKey = "AIChat.fileAccessOverrides"

    private init() {
        let defaults = UserDefaults.standard
        self.isAIEnabled = defaults.object(forKey: Self.isAIEnabledDefaultsKey) as? Bool ?? false

        if let raw = defaults.string(forKey: interactionModeKey),
           let mode = AIChatInteractionMode(rawValue: raw) {
            self.interactionMode = mode
        } else {
            self.interactionMode = .agent
        }

        let rawFileAccessOverrides = defaults.dictionary(forKey: fileAccessOverridesKey) ?? [:]
        self.fileAccessOverrides = rawFileAccessOverrides.compactMapValues { $0 as? Bool }

        // A previously enabled BYOK session must obtain its own permission before
        // activation or account/model refresh can resume on this device.
        if isAIEnabled, !AIServiceConsentState.shared.hasAcceptedSelectedMode {
            isAIEnabled = false
            defaults.set(false, forKey: Self.isAIEnabledDefaultsKey)
        }
    }

    func allowsFileAccess(for activeFile: FileState.ActiveFile?) -> Bool {
        guard let activeFile else { return false }
        return fileAccessOverrides[fileAccessKey(for: activeFile.aiConversationFileScope)] ?? true
    }

    func effectiveAllowsFileAccess(
        for activeFile: FileState.ActiveFile?,
        lockState: FileContentLockState
    ) -> Bool {
        guard lockState == .plaintext else { return false }
        return allowsFileAccess(for: activeFile)
    }

    func interactionMode(for activeFile: FileState.ActiveFile?) -> AIChatInteractionMode {
        allowsFileAccess(for: activeFile) ? .agent : .ask
    }

    func setAllowsFileAccess(_ allowsFileAccess: Bool, for activeFile: FileState.ActiveFile?) {
        guard let activeFile else { return }
        fileAccessOverrides[fileAccessKey(for: activeFile.aiConversationFileScope)] = allowsFileAccess
        saveFileAccessOverrides()
    }

    func rebindFileAccessOverride(
        from oldScope: AIConversationFileScope,
        to newScope: AIConversationFileScope
    ) {
        let oldKey = fileAccessKey(for: oldScope)
        guard let value = fileAccessOverrides.removeValue(forKey: oldKey) else { return }
        fileAccessOverrides[fileAccessKey(for: newScope)] = value
        saveFileAccessOverrides()
    }

    func deleteFileAccessOverride(for scope: AIConversationFileScope) {
        guard fileAccessOverrides.removeValue(forKey: fileAccessKey(for: scope)) != nil else { return }
        saveFileAccessOverrides()
    }

    /// Drop the override for a removed conversation. Called from anywhere
    /// that deletes / clears a conversation so the dict doesn't grow
    /// indefinitely with dead keys.
    func forgetConversation(_ conversationID: String) {
            AIInferenceBillingState.shared.forgetConversation(conversationID)
    }

    private func saveIsAIEnabled() {
        UserDefaults.standard.set(isAIEnabled, forKey: Self.isAIEnabledDefaultsKey)
    }

    private func saveInteractionMode() {
        UserDefaults.standard.set(interactionMode.rawValue, forKey: interactionModeKey)
    }

    private func saveFileAccessOverrides() {
        UserDefaults.standard.set(fileAccessOverrides, forKey: fileAccessOverridesKey)
    }

    private func fileAccessKey(for scope: AIConversationFileScope) -> String {
        "\(scope.kind.rawValue):\(scope.id)"
    }

}
