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
            Text(String(localized: "AI.WebSearch.title"))
            Button { showsHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "AI.WebSearch.title"))
            .popover(isPresented: $showsHelp) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "AI.WebSearch.title")).font(.headline)
                    Text(String(localized: "AI.WebSearch.basicDescription"))
                    if let adapter = configuration?.webSearchAdapter {
                        Text(BYOKWebSearchDescription.text(for: adapter))
                    } else if configuration == nil {
                        Text(String(localizable: .aiBYOKSelectConnection))
                    } else {
                        Text(String(localized: "AI.WebSearch.unsupported"))
                    }
                    Text(String(localized: "AI.WebSearch.billingDescription"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 300)
            }
            Spacer(minLength: 16)
            Toggle(String(localized: "AI.WebSearch.title"), isOn: Binding(
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
        case .openRouter: String(localized: "AI.WebSearch.modelDecides")
        case .openAI: String(localized: "AI.WebSearch.alwaysSearch")
        case .dashScope: String(localized: "AI.WebSearch.providerDefined")
        case .groq: String(localized: "AI.WebSearch.browserModel")
        @unknown default: String(localized: "AI.WebSearch.providerDefined")
        }
    }
}
