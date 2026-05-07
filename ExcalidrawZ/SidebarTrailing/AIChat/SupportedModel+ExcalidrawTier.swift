//
//  SupportedModel+ExcalidrawTier.swift
//  ExcalidrawZ
//
//  Maps the upstream `SupportedModel` cases to ExcalidrawZ's
//  user-facing tier vocabulary (Low / Medium / High / Extra High).
//
//  Rationale: the model picker in the chat input shouldn't expose
//  vendor / version names like "Claude Sonnet 4.6" — most users
//  don't have a frame of reference for those, and the lineup will
//  rotate over time as we upgrade. Tier labels stay stable and
//  communicate the cost / capability tradeoff directly.
//
//  We deliberately don't extend `SupportedModel.displayName` itself
//  (it's defined upstream in LLMCore and Swift extensions can't
//  override existing methods on imported types). Instead the chat UI
//  reaches for `excalidrawTierName`; everything else (settings, raw
//  identifiers, server-bound config) keeps using the upstream
//  `displayName` / `rawValue`.
//
//  Adding a new tier or remapping is safe: this is the only place
//  that the chat picker's labels live.
//

import Foundation
import LLMCore

extension SupportedModel {
    /// User-facing tier label used by the chat input's model picker.
    /// Falls back to the upstream `displayName` when a model isn't
    /// covered by the tier scheme (e.g. legacy / experimental cases
    /// that show up in `allowedModels` but aren't part of the
    /// curated tier ladder).
    var excalidrawTierName: String {
        switch self {
            case .gpt4oMini:
                return "Low"
            case .claudeHaiku4_5:
                return "Medium"
            case .claudeSonnet4_6:
                return "High"
            case .claudeOpus4_7, .claudeOpus4_6:
                return "Extra High"
            default:
                return displayName
        }
    }

    /// Approximate context window (in tokens) for the model. Used by the
    /// chat input's `ContextUsageRing` to draw "how full is the context."
    /// Numbers are vendor-published values; we treat them as soft caps for
    /// the indicator only — the actual server may apply a smaller cap.
    /// Unknown models return a 128k floor so the ring still draws something.
    var approximateContextWindowTokens: Int {
        switch self {
            case .claudeOpus4_7, .claudeOpus4_6,
                 .claudeSonnet4_6, .claudeHaiku4_5:
                return 200_000
            case .gpt4o, .gpt4oMini, .gpt4oLatest, .gpt5_5, .gpt5_4:
                return 128_000
            case .gpt35Turbo:
                return 16_000
            case .gemini15Pro, .gemini15Flash:
                return 1_000_000
            default:
                return 128_000
        }
    }
}
