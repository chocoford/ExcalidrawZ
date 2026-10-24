//
//  AIChatPreferences.swift
//  ExcalidrawZ
//
//  Single source of truth for AI-chat user preferences:
//   - `isAIEnabled`: master switch for all AI-facing UI and network
//     activity. Defaults to off so users explicitly opt in before any
//     AI request or account/credits refresh is made.
//   - `defaultTier`: the model tier used when a conversation has no
//     explicit pick yet. Mutated from the Settings tab's picker.
//   - `fileAccessOverrides`: per-file AI visibility overrides. Missing
//     values use the default: unlocked files are visible to AI; locked
//     files remain invisible through the lock-state guard.
//   - `conversationTierOverrides`: per-conversation tier assignments.
//     Set when the user opens a conversation's picker; survives across
//     launches so reopening a conversation always picks back up with the
//     tier the user last chose for it.
//
//  These are persisted to `UserDefaults` rather than Core Data — they're
//  small (simple strings + flat dicts), and don't need iCloud sync (a
//  per-device pick is the right default; syncing a model setting between
//  devices the user might've configured differently would surprise more
//  than help).
//

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
final class AIChatPreferences: ObservableObject {
    static let shared = AIChatPreferences()
    nonisolated static let isAIEnabledDefaultsKey = "AIChat.isEnabled"

    /// Master switch for AI features. When off, AI chat surfaces show
    /// an opt-in screen and no AI network refresh should be triggered.
    @Published var isAIEnabled: Bool {
        didSet {
            saveIsAIEnabled()
            guard oldValue != isAIEnabled else { return }
            let isAIEnabled = isAIEnabled
            Task {
                await LLMServiceActivationCoordinator.shared.handleAIEnabledChanged(isAIEnabled)
            }
        }
    }

    /// Tier used for a fresh conversation that has no explicit pick yet,
    /// and as the fallback shown in the picker when no conversation is
    /// active. User-controlled via Settings → AI.
    @Published var defaultTier: ExcalidrawModelTier {
        didSet { saveDefaultTier() }
    }

    /// Legacy storage values: `.agent` means AI can access and edit the
    /// current file, while `.ask` means no current-file access and edits
    /// go through a proposal canvas.
    @Published var interactionMode: AIChatInteractionMode {
        didSet { saveInteractionMode() }
    }

    var allowsFileAccess: Bool {
        get { interactionMode == .agent }
        set { interactionMode = newValue ? .agent : .ask }
    }

    /// Per-file AI visibility overrides. Missing value means "use the safe
    /// default": unlocked files are visible to AI, locked files are forced
    /// invisible by the caller's lock-state check.
    @Published private(set) var fileAccessOverrides: [String: Bool]

    /// Per-conversation tier picks, keyed by conversation id. Updated
    /// from `PromptInputView`'s inline picker; the side-effect goes
    /// through `setTier(_:for:)` so persistence stays in one place.
    @Published private(set) var conversationTierOverrides: [String: ExcalidrawModelTier]

    private let defaultTierKey = "AIChat.defaultModelTier"
    private let overridesTierKey = "AIChat.conversationModelTierOverrides"
    private let interactionModeKey = "AIChat.interactionMode"
    private let fileAccessOverridesKey = "AIChat.fileAccessOverrides"

    /// Legacy concrete-model keys. Kept only for one-way migration from
    /// versions that persisted a specific upstream model instead of a tier.
    private let legacyDefaultModelKey = "AIChat.defaultModel"
    private let legacyOverridesKey = "AIChat.conversationModelOverrides"

    private init() {
        let defaults = UserDefaults.standard
        self.isAIEnabled = defaults.object(forKey: Self.isAIEnabledDefaultsKey) as? Bool ?? false

        if let raw = defaults.string(forKey: defaultTierKey),
           let tier = ExcalidrawModelTier(rawValue: raw) {
            self.defaultTier = tier
        } else if let raw = defaults.string(forKey: legacyDefaultModelKey),
                  let tier = Self.tier(forLegacyStoredModelRawValue: raw) {
            self.defaultTier = tier
        } else {
            self.defaultTier = .medium
        }

        if let raw = defaults.string(forKey: interactionModeKey),
           let mode = AIChatInteractionMode(rawValue: raw) {
            self.interactionMode = mode
        } else {
            self.interactionMode = .agent
        }

        let rawFileAccessOverrides = defaults.dictionary(forKey: fileAccessOverridesKey) ?? [:]
        self.fileAccessOverrides = rawFileAccessOverrides.compactMapValues { $0 as? Bool }

        if let dict = defaults.dictionary(forKey: overridesTierKey) as? [String: String] {
            self.conversationTierOverrides = dict.compactMapValues {
                ExcalidrawModelTier(rawValue: $0)
            }
        } else {
            let dict = defaults.dictionary(forKey: legacyOverridesKey) as? [String: String] ?? [:]
            self.conversationTierOverrides = dict.compactMapValues {
                Self.tier(forLegacyStoredModelRawValue: $0)
            }
        }

        // A previously enabled BYOK session must obtain its own permission before
        // activation or account/model refresh can resume on this device.
        if isAIEnabled, !AIServiceConsentState.shared.hasAcceptedSelectedMode {
            isAIEnabled = false
            defaults.set(false, forKey: Self.isAIEnabledDefaultsKey)
        }
    }

    /// Returns the tier picked for `conversationID`, or nil if the
    /// conversation has no override (caller falls back to `defaultTier`).
    func tier(for conversationID: String?) -> ExcalidrawModelTier? {
        guard let id = conversationID else { return nil }
        return conversationTierOverrides[id]
    }

    func setTier(_ tier: ExcalidrawModelTier, for conversationID: String) {
        conversationTierOverrides[conversationID] = tier
        saveTierOverrides()
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
        if conversationTierOverrides[conversationID] != nil {
            conversationTierOverrides.removeValue(forKey: conversationID)
            saveTierOverrides()
        }
    }

    private func saveIsAIEnabled() {
        UserDefaults.standard.set(isAIEnabled, forKey: Self.isAIEnabledDefaultsKey)
    }

    private func saveDefaultTier() {
        UserDefaults.standard.set(defaultTier.rawValue, forKey: defaultTierKey)
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

    private func saveTierOverrides() {
        let raw = conversationTierOverrides.mapValues { $0.rawValue }
        UserDefaults.standard.set(raw, forKey: overridesTierKey)
    }

    private static func tier(forLegacyStoredModelRawValue rawValue: String) -> ExcalidrawModelTier? {
        let model = SupportedModel(rawValue: rawValue)
        if model == .claudeHaiku4_5 {
            return .medium
        }
        return model.excalidrawTier
    }
}
