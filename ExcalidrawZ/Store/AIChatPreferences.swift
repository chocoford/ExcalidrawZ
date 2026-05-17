//
//  AIChatPreferences.swift
//  ExcalidrawZ
//
//  Single source of truth for AI-chat user preferences:
//   - `defaultTier`: the model tier used when a conversation has no
//     explicit pick yet. Mutated from the Settings tab's picker.
//   - `conversationTierOverrides`: per-conversation tier assignments.
//     Set when the user opens a conversation's picker; survives across
//     launches so reopening a conversation always picks back up with the
//     tier the user last chose for it.
//
//  Both are persisted to `UserDefaults` rather than Core Data — they're
//  small (a single string + a flat dict), and don't need iCloud sync (a
//  per-device pick is the right default; syncing a model setting between
//  devices the user might've configured differently would surprise more
//  than help).
//

import Foundation
import LLMCore

@MainActor
final class AIChatPreferences: ObservableObject {
    static let shared = AIChatPreferences()

    /// Tier used for a fresh conversation that has no explicit pick yet,
    /// and as the fallback shown in the picker when no conversation is
    /// active. User-controlled via Settings → AI.
    @Published var defaultTier: ExcalidrawModelTier {
        didSet { saveDefaultTier() }
    }

    /// Per-conversation tier picks, keyed by conversation id. Updated
    /// from `PromptInputView`'s inline picker; the side-effect goes
    /// through `setTier(_:for:)` so persistence stays in one place.
    @Published private(set) var conversationTierOverrides: [String: ExcalidrawModelTier]

    private let defaultTierKey = "AIChat.defaultModelTier"
    private let overridesTierKey = "AIChat.conversationModelTierOverrides"

    /// Legacy concrete-model keys. Kept only for one-way migration from
    /// versions that persisted a specific upstream model instead of a tier.
    private let legacyDefaultModelKey = "AIChat.defaultModel"
    private let legacyOverridesKey = "AIChat.conversationModelOverrides"

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: defaultTierKey),
           let tier = ExcalidrawModelTier(rawValue: raw) {
            self.defaultTier = tier
        } else if let raw = defaults.string(forKey: legacyDefaultModelKey),
                  let tier = Self.tier(forLegacyStoredModelRawValue: raw) {
            self.defaultTier = tier
        } else {
            self.defaultTier = .medium
        }

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

    /// Drop the override for a removed conversation. Called from anywhere
    /// that deletes / clears a conversation so the dict doesn't grow
    /// indefinitely with dead keys.
    func forgetConversation(_ conversationID: String) {
        if conversationTierOverrides[conversationID] != nil {
            conversationTierOverrides.removeValue(forKey: conversationID)
            saveTierOverrides()
        }
    }

    private func saveDefaultTier() {
        UserDefaults.standard.set(defaultTier.rawValue, forKey: defaultTierKey)
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
