//
//  AIChatPreferences.swift
//  ExcalidrawZ
//
//  Single source of truth for AI-chat user preferences:
//   - `defaultModel`: the model used when a conversation has no explicit
//     pick yet. Mutated from the Settings tab's "Default Model" picker.
//   - `conversationOverrides`: per-conversation model assignments. Set
//     when the user opens a conversation's model picker; survives across
//     launches so reopening a conversation always picks back up with the
//     model the user last chose for it.
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

    /// Model used for a fresh conversation that has no explicit pick yet,
    /// and as the fallback shown in the picker when no conversation is
    /// active. User-controlled via Settings → AI.
    @Published var defaultModel: SupportedModel {
        didSet { saveDefaultModel() }
    }

    /// Per-conversation model picks, keyed by conversation id. Updated
    /// from `PromptInputView`'s inline picker; the side-effect goes
    /// through `setModel(_:for:)` so persistence stays in one place.
    @Published private(set) var conversationOverrides: [String: SupportedModel]

    private let defaultModelKey = "AIChat.defaultModel"
    private let overridesKey = "AIChat.conversationModelOverrides"
    /// "Medium" tier. The user-facing default for new conversations
    /// and the fallback when no per-conversation override is stored.
    /// Picked Haiku rather than Sonnet so first-time users don't burn
    /// credits at the higher tier without knowing — they can opt up
    /// from Settings → AI or per-conversation in the picker.
    private let fallbackModel: SupportedModel = .claudeHaiku4_5

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: defaultModelKey) {
            self.defaultModel = SupportedModel(rawValue: raw)
        } else {
            self.defaultModel = .claudeHaiku4_5
        }

        let dict = defaults.dictionary(forKey: overridesKey) as? [String: String] ?? [:]
        self.conversationOverrides = dict.mapValues { SupportedModel(rawValue: $0) }
    }

    /// Returns the model picked for `conversationID`, or nil if the
    /// conversation has no override (caller falls back to `defaultModel`).
    func model(for conversationID: String?) -> SupportedModel? {
        guard let id = conversationID else { return nil }
        return conversationOverrides[id]
    }

    func setModel(_ model: SupportedModel, for conversationID: String) {
        conversationOverrides[conversationID] = model
        saveOverrides()
    }

    /// Drop the override for a removed conversation. Called from anywhere
    /// that deletes / clears a conversation so the dict doesn't grow
    /// indefinitely with dead keys.
    func forgetConversation(_ conversationID: String) {
        guard conversationOverrides[conversationID] != nil else { return }
        conversationOverrides.removeValue(forKey: conversationID)
        saveOverrides()
    }

    private func saveDefaultModel() {
        UserDefaults.standard.set(defaultModel.rawValue, forKey: defaultModelKey)
    }

    private func saveOverrides() {
        let raw = conversationOverrides.mapValues { $0.rawValue }
        UserDefaults.standard.set(raw, forKey: overridesKey)
    }
}
