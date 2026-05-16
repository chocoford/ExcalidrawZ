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
    /// Picker for `prefs.defaultModel`. Bound through rawValue so the
    /// underlying `SupportedModel` enum doesn't need explicit Hashable
    /// conformance for the Picker tag matching. List is the agent's
    /// allowed models with the user's current pick spliced in if it
    /// somehow isn't there (e.g., backend dropped a model from the
    /// allowed list after the user already picked it).
    @MainActor @ViewBuilder
    var defaultModelPicker: some View {
        let selectableModels = availableModels.filter { canSelectModel($0) }
        let current = fallbackModelIfNeeded(prefs.defaultModel, from: selectableModels)
        let mergedModels: [SupportedModel] = {
            if selectableModels.isEmpty {
                return [current]
            }
            if selectableModels.contains(where: { $0.rawValue == current.rawValue }) {
                return selectableModels
            }
            return [current] + selectableModels
        }()

        Picker(.localizable(.settingsAIDefaultModelTitle), selection: Binding(
            get: { current.rawValue },
            set: { rawValue in
                let model = SupportedModel(rawValue: rawValue)
                guard canSelectModel(model) else { return }
                prefs.defaultModel = model
            }
        )) {
            ForEach(mergedModels, id: \.rawValue) { model in
                Text(model.excalidrawTierName)
                    .tag(model.rawValue)
                    .disabled(!canSelectModel(model))
            }
        }
        .help(.localizable(.settingsAIDefaultModelHelp))
    }

    @MainActor
    func canSelectModel(_ model: SupportedModel) -> Bool {
        model.isVisibleInExcalidrawModelPicker
        && (!model.requiresMaxAIPlan || store.canUseExtraHighAIModel)
    }

    @MainActor
    func fallbackModelIfNeeded(
        _ model: SupportedModel,
        from availableModels: [SupportedModel]
    ) -> SupportedModel {
        guard !canSelectModel(model) else { return model }

        return availableModels.first(where: { $0 == .claudeSonnet4_6 })
        ?? availableModels.first(where: { canSelectModel($0) })
        ?? .claudeSonnet4_6
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
