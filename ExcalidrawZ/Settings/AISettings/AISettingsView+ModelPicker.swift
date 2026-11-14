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
                Text(modelCatalogPlaceholder)
                    .tag(current).disabled(true)
            }
            ForEach(options) { option in
                Text(option.title).tag(option.profileID).disabled(!option.isAllowed)
            }
        }
        .help(.localizable(.settingsAIDefaultModelHelp))
        .disabled(!prefs.isAIEnabled || schemeCatalog.isLoading || options.isEmpty)
    }

    private var modelCatalogPlaceholder: String {
        if prefs.isAIEnabled, schemeCatalog.isLoading || (schemeCatalog.scheme == nil && schemeCatalog.errorMessage == nil) {
            return String(localizable: .aISchemeLoadingProfiles)
        }
        if schemeCatalog.scheme != nil, schemeCatalog.options.isEmpty {
            return String(localizable: .aISchemeNoProfiles)
        }
        return String(localizable: .aISchemeChooseProfile)
    }

    @ViewBuilder
    var platformModelStatusFooter: some View {
        if let message = schemeCatalog.errorMessage {
            modelCatalogFailure(message)
        } else if let scheme = schemeCatalog.scheme, !schemeCatalog.isLoading {
            if schemeCatalog.options.isEmpty {
                modelCatalogFailure(String(localizable: .aISchemeNoProfiles))
            } else {
                let id = routing.defaultProfileID ?? scheme.defaultProfileID
                if !schemeCatalog.options.contains(where: { $0.profileID == id }) {
                    Text(.localizable(.aISchemeProfileUnavailable(id)))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func modelCatalogFailure(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(message).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(.localizable(.generalButtonRetry)) {
                Task { await schemeCatalog.refresh(force: true) }
            }
            .buttonStyle(.borderless)
            .disabled(!prefs.isAIEnabled || schemeCatalog.isLoading)
        }
    }

    func loadAvailableModelsIfNeeded() async {
        await schemeCatalog.refresh()
    }
}
