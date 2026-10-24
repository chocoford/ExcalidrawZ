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
    /// send time from the current backend-defined profile list, so backend
    /// model rotation does not rewrite the user's preferred capability tier.
    @ViewBuilder
    var defaultModelPicker: some View {
        let visibleOptions = availableModelOptions.filter { canShowModelInPicker($0) }
        let selectableOptions = visibleOptions.filter { canSelectModel($0) }
        let visibleTiers = ExcalidrawModelTier.pickerOrder.filter { tier in
            visibleOptions.contains { $0.tier == tier }
        }
        let selectableTiers = ExcalidrawModelTier.pickerOrder.filter { tier in
            selectableOptions.contains { $0.tier == tier }
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
                      canSelectTier(tier, from: selectableOptions)
                else { return }
                prefs.defaultTier = tier
            }
        )) {
            ForEach(mergedTiers) { tier in
                Text(tier.name)
                    .tag(tier.rawValue)
                    .disabled(!canSelectTier(tier, from: selectableOptions))
            }
        }
        .help(.localizable(.settingsAIDefaultModelHelp))
        .disabled(!prefs.isAIEnabled)
    }

    @MainActor
    func canShowModelInPicker(_ option: ExcalidrawModelProfileOption) -> Bool {
        option.isVisible
    }

    @MainActor
    func canSelectModel(_ option: ExcalidrawModelProfileOption) -> Bool {
        canShowModelInPicker(option)
            && (!option.requiresMaxAIPlan || store.canUseExtraHighAIModel)
    }

    @MainActor
    func canSelectTier(
        _ tier: ExcalidrawModelTier,
        from availableOptions: [ExcalidrawModelProfileOption]
    ) -> Bool {
        availableOptions.contains { option in
            option.tier == tier && canSelectModel(option)
        }
    }

    @MainActor
    func fallbackTierIfNeeded(
        _ tier: ExcalidrawModelTier,
        from availableTiers: [ExcalidrawModelTier]
    ) -> ExcalidrawModelTier {
        guard !availableTiers.isEmpty else { return tier }
        guard availableTiers.contains(tier) else {
            return availableTiers[0]
        }

        return tier
    }

    func loadAvailableModelsIfNeeded() async {
        guard AIChatAvailability.canUseAI else { return }
        guard availableModelOptions.isEmpty else { return }
        do {
            guard AIChatAvailability.canUseAI else { throw CancellationError() }
            let config = try await LLMClient.shared.getDomainAgentConfig(agentID: agentID)
            await MainActor.run {
                self.availableModelOptions = config.excalidrawModelOptions
            }
        } catch is CancellationError {
        } catch {
            // Silently keep the picker showing just the current selection.
            // The user can still change it later when network recovers.
        }
    }
}
