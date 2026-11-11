import SwiftUI
import LLMCore

extension AISettingsView {
    @ViewBuilder
    var basicWebSearchRow: some View {
        if prefs.isAIEnabled, inferenceBilling.usesBYOK, inferenceBilling.integrationMode == .basic {
            BasicWebSearchSettingsRow(configuration: inferenceBilling.selectedProfile?.webSearchConfiguration,
                isBusy: inferenceBilling.isBusy, onChange: setBasicWebSearch)
                .id(inferenceBilling.selectedProfileID)
        }
    }

    private func setBasicWebSearch(_ enabled: Bool) {
        guard inferenceBilling.usesBYOK, inferenceBilling.integrationMode == .basic,
              !inferenceBilling.isBusy, let id = inferenceBilling.selectedProfileID else { return }
        Task { @MainActor in
            do {
                try await AIChatInferenceSessions.shared.setWebSearch(enabled, connectionID: id)
                byokStatusMessage = nil
                byokStatusIsError = false
            } catch {
                byokStatusMessage = (AIInferenceErrorMessage.localizedError(for: error) ?? error).localizedDescription
                byokStatusIsError = true
            }
        }
    }
}

private struct BasicWebSearchSettingsRow: View {
    let configuration: LLMBYOKConfiguration?
    let isBusy: Bool
    let onChange: (Bool) -> Void
    @State private var showsHelp = false

    var body: some View {
        HStack(spacing: 4) {
            Text(.localizable(.aIWebSearchTitle))
            Button { showsHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(.localizable(.aIWebSearchTitle))
            .popover(isPresented: $showsHelp) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(.localizable(.aIWebSearchTitle)).font(.headline)
                    Text(.localizable(.aIWebSearchBasicDescription))
                    if let adapter = configuration?.webSearchAdapter {
                        Text(BYOKWebSearchDescription.text(for: adapter))
                    } else if configuration == nil {
                        Text(String(localizable: .aiBYOKSelectConnection))
                    } else {
                        Text(.localizable(.aIWebSearchUnsupported))
                    }
                    Text(.localizable(.aIWebSearchBillingDescription))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 300)
            }
            Spacer(minLength: 16)
            Toggle(.localizable(.aIWebSearchTitle), isOn: Binding(
                get: { configuration?.webSearch?.isEnabled ?? false }, set: onChange))
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
                .disabled(isBusy || configuration?.webSearchAdapter == nil)
        }
    }
}

private enum BYOKWebSearchDescription {
    static func text(for adapter: LLMBYOKWebSearch.Adapter) -> String {
        switch adapter {
        case .openRouter: String(localizable: .aIWebSearchModelDecides)
        case .openAI: String(localizable: .aIWebSearchAlwaysSearch)
        case .dashScope: String(localizable: .aIWebSearchProviderDefined)
        case .groq: String(localizable: .aIWebSearchBrowserModel)
        @unknown default: String(localizable: .aIWebSearchProviderDefined)
        }
    }
}
