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
    /// DEBUG builds expose the upstream `displayName` for unmapped models
    /// so newly added cases are easy to spot during development. Release
    /// builds keep the picker on stable tier vocabulary.
    var excalidrawTierName: String {
        switch self {
            case .hy3Preview:
                return String(localizable: .aiChatModelTierLow)
            case .claudeHaiku4_5:
                return String(localizable: .aiChatModelTierMedium)
            case .claudeSonnet4_6:
                return String(localizable: .aiChatModelTierHigh)
            case .claudeOpus4_7:
                return String(localizable: .aiChatModelTierExtraHigh)
            default:
#if DEBUG
                return displayName
#else
                return "Experimental"
#endif
        }
    }

    /// Extra High is reserved for Max plan users. Keep this separate from
    /// the display string so entitlement checks do not depend on UI text.
    var requiresMaxAIPlan: Bool {
        switch self {
            case .claudeOpus4_7, .claudeOpus4_6:
                return true
            default:
                return false
        }
    }

    var supportsExcalidrawImageInput: Bool {
        supportsImageInput
    }

    /// Internal ordering used for automatic capability fallback.
    ///
    /// Only models with an explicit Excalidraw tier get a rank. Models
    /// that fall through to provider names / "Experimental" are left
    /// unranked so they do not influence tier-based fallback.
    var excalidrawSelectionRank: Int? {
        switch self {
            case .hy3Preview:
                return 0
            case .claudeHaiku4_5:
                return 1
            case .claudeSonnet4_6:
                return 2
            case .claudeOpus4_7:
                return 3
            default:
                return nil
        }
    }

    /// Model picker visibility. Release builds only expose models that
    /// have an explicit Excalidraw tier mapping; DEBUG builds keep
    /// unmapped upstream models visible so new backend options are easy
    /// to notice during development.
    var isVisibleInExcalidrawModelPicker: Bool {
#if DEBUG
        return true
#else
        return excalidrawSelectionRank != nil
#endif
    }

    static func nearestExcalidrawFallback(
        to selected: SupportedModel,
        from candidates: [SupportedModel]
    ) -> SupportedModel? {
        guard !candidates.isEmpty else { return nil }
        guard let selectedRank = selected.excalidrawSelectionRank else {
            return candidates.first
        }

        let rankedCandidates = candidates.enumerated().compactMap { index, model in
            model.excalidrawSelectionRank.map { rank in
                (index: index, model: model, rank: rank)
            }
        }
        guard !rankedCandidates.isEmpty else {
            return candidates.first
        }

        return rankedCandidates.min { lhs, rhs in
            let lhsDistance = abs(lhs.rank - selectedRank)
            let rhsDistance = abs(rhs.rank - selectedRank)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            // When two candidates are equally far away, prefer a same-or-
            // higher capability move over a downgrade. This keeps "missing
            // image input" as an upgrade path while still allowing downgrade
            // fallback when Extra High is unavailable on the current plan.
            let lhsIsDowngrade = lhs.rank < selectedRank
            let rhsIsDowngrade = rhs.rank < selectedRank
            if lhsIsDowngrade != rhsIsDowngrade {
                return !lhsIsDowngrade
            }

            return lhs.index < rhs.index
        }?.model
    }
}
