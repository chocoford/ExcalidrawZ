//
//  AISettingsView+ModelPicker.swift
//  ExcalidrawZ
//
//  Created by Codex on 5/13/26.
//

import SwiftUI
import ChocofordUI
import LLMKit
import LLMCore

extension AISettingsView {
    /// Picker for `prefs.defaultTier`. The concrete model is resolved at
    /// send time from the current backend-allowed model list, so backend
    /// model rotation does not rewrite the user's preferred capability tier.
    @MainActor @ViewBuilder
    var defaultModelPicker: some View {
        let visibleModels = availableModels.filter { canShowModelInPicker($0) }
        let selectableModels = visibleModels.filter { canSelectModel($0) }
        let visibleTiers = ExcalidrawModelTier.pickerOrder.filter { tier in
            visibleModels.contains { $0.excalidrawTier == tier }
        }
        let selectableTiers = ExcalidrawModelTier.pickerOrder.filter { tier in
            selectableModels.contains { $0.excalidrawTier == tier }
        }
        let current = fallbackTierIfNeeded(prefs.defaultTier, from: selectableTiers)
        let mergedTiers: [ExcalidrawModelTier] = {
            if visibleTiers.isEmpty {
                return [current]
            }
            if visibleTiers.contains(current) {
                return visibleTiers
            }
            return [current] + visibleTiers
        }()

        Picker(.localizable(.settingsAIDefaultModelTitle), selection: Binding(
            get: { current.rawValue },
            set: { rawValue in
                guard let tier = ExcalidrawModelTier(rawValue: rawValue),
                      canSelectTier(tier, from: selectableModels)
                else { return }
                prefs.defaultTier = tier
            }
        )) {
            ForEach(mergedTiers) { tier in
                Text(tier.name)
                    .tag(tier.rawValue)
                    .disabled(!canSelectTier(tier, from: selectableModels))
            }
        }
        .help(.localizable(.settingsAIDefaultModelHelp))
    }

    @MainActor
    func canShowModelInPicker(_ model: SupportedModel) -> Bool {
        model.isVisibleInExcalidrawModelPicker
    }

    @MainActor
    func canSelectModel(_ model: SupportedModel) -> Bool {
        canShowModelInPicker(model)
            && (!model.requiresMaxAIPlan || store.canUseExtraHighAIModel)
    }

    @MainActor
    func canSelectTier(
        _ tier: ExcalidrawModelTier,
        from availableModels: [SupportedModel]
    ) -> Bool {
        availableModels.contains { model in
            model.excalidrawTier == tier && canSelectModel(model)
        }
    }

    @MainActor
    func fallbackTierIfNeeded(
        _ tier: ExcalidrawModelTier,
        from availableTiers: [ExcalidrawModelTier]
    ) -> ExcalidrawModelTier {
        guard !availableTiers.isEmpty else { return tier }
        guard !tier.requiresMaxAIPlan || store.canUseExtraHighAIModel else {
            return availableTiers.first(where: { $0 == .high })
            ?? availableTiers.first(where: { $0 == .medium })
            ?? availableTiers[0]
        }
        guard availableTiers.contains(tier) else {
            return availableTiers.first(where: { $0 == .medium })
            ?? availableTiers[0]
        }

        return tier
    }

    func loadAvailableModelsIfNeeded() async {
        guard availableModels.isEmpty else { return }
        do {
            let config = try await LLMClient.shared.getDomainAgentConfig(agentID: agentID)
            await MainActor.run {
                self.availableModels = config.allowedModels
            }
        } catch {
            // Silently keep the picker showing just the current selection.
            // The user can still change it later when network recovers.
        }
    }
}
