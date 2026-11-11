import SwiftUI
import ChocofordUI
import LLMKit
import LLMCore

extension AISettingsView {
    @ViewBuilder
    var defaultModelPicker: some View {
        let options = schemeCatalog.options
        let current = routing.defaultProfileID ?? schemeCatalog.scheme?.defaultProfileID ?? ""
        Picker(.localizable(.settingsAIDefaultModelTitle), selection: Binding(
            get: { current },
            set: { id in
                guard options.contains(where: { $0.profileID == id && $0.isAllowed }) else { return }
                routing.defaultProfileID = id
            }
        )) {
            if !options.contains(where: { $0.profileID == current }) {
                Text(current.isEmpty ? String(localized: "AI.Scheme.chooseForLegacy") : current)
                    .tag(current).disabled(true)
            }
            ForEach(options) { option in
                Text(option.title).tag(option.profileID).disabled(!option.isAllowed)
            }
        }
        .help(.localizable(.settingsAIDefaultModelHelp))
        .disabled(!prefs.isAIEnabled || schemeCatalog.isLoading)
        if let message = schemeCatalog.errorMessage {
            Text(message).font(.footnote).foregroundStyle(.red)
        }
    }

    func loadAvailableModelsIfNeeded() async {
        await schemeCatalog.refresh()
    }
}
