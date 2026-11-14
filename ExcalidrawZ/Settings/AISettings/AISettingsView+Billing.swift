import SwiftUI
import LLMKit
import LLMCore
import ChocofordUI

extension AISettingsView {
    enum AIServiceMode: Hashable, Identifiable {
        case none
        case excalidrawZ
        case byok

        var id: Self { self }

        var billingMode: AIInferenceBillingMode? {
            switch self {
                case .none: nil
                case .excalidrawZ: .platform
                case .byok: .byok
            }
        }
    }

    @MainActor
    @ViewBuilder
    var aiServiceModePicker: some View {
        Picker(.localizable(.aiServiceTitle), selection: Binding(
            get: {
                guard prefs.isAIEnabled, !inferenceBilling.requiresBillingSelection else { return AIServiceMode.none }
                return inferenceBilling.usesBYOK ? .byok : .excalidrawZ
            },
            set: { selectAIServiceMode($0) }
        )) {
            Text(.localizable(.aiServiceNone))
                .tag(AIServiceMode.none)
            if AIChatAvailability.supportsManagedInference {
                Text(.localizable(.aiServiceExcalidrawZ))
                    .tag(AIServiceMode.excalidrawZ)
                    .disabled(inferenceBilling.isBusy && inferenceBilling.usesBYOK)
            }
            Text(.localizable(.aiServiceBYOK))
                .tag(AIServiceMode.byok)
                .disabled(inferenceBilling.isBusy && !inferenceBilling.usesBYOK)
        }
        .help(.localizable(.settingsAIEnableFeatureHelp))

    }

    @ViewBuilder
    var aiServiceSettingsFooter: some View {
        if inferenceBilling.requiresBillingSelection {
            Text(.localizable(.aiBYOKBillingSelectionRequired))
                .foregroundStyle(.red)
        }
        if inferenceBilling.isBusy {
            Text(.localizable(.aiBYOKSettingsBusy))
        }
        if let byokStatusMessage, !prefs.isAIEnabled || !inferenceBilling.usesBYOK {
            Text(byokStatusMessage)
                .foregroundStyle(byokStatusIsError ? Color.red : Color.secondary)
        }
    }

    @MainActor
    private func selectAIServiceMode(_ mode: AIServiceMode) {
        guard mode != .none else {
            byokStatusMessage = nil
            prefs.isAIEnabled = false
            return
        }
        guard let billingMode = mode.billingMode else { return }
        guard aiServiceConsent.hasAccepted(billingMode) else {
            pendingAIServiceMode = mode
            return
        }
        applyAIServiceMode(mode)
    }

    @MainActor
    func applyAIServiceMode(_ mode: AIServiceMode) {
        guard let billingMode = mode.billingMode, aiServiceConsent.hasAccepted(billingMode) else { return }
        updateInferenceBilling {
            // Set credentials before enabling account refresh or any model request.
            try inferenceBilling.setMode(billingMode)
            if !prefs.isAIEnabled {
                prefs.isAIEnabled = true
            }
            if mode == .byok {
                selectedTab = .settings
            }
        }
    }

    @ViewBuilder
    var byokConnectionsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            byokConnectionsHeaderRow

            ForEach(inferenceBilling.profiles) { profile in
                byokConnectionRow(profile)
            }
            if inferenceBilling.profiles.isEmpty {
                Text(.localizable(.aiBYOKSelectConnection))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var byokConnectionsHeaderRow: some View {
        HStack {
            Text(.localizable(.aiBYOKConnectionsTitle))
            Spacer(minLength: 8)
            Button {
                byokConnectionSheet = .add
            } label: {
                Label(.localizable(.aiBYOKAddConnection), systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(inferenceBilling.isBusy)
        }
        .frame(maxWidth: .infinity)
        .sheet(item: $byokConnectionSheet) { sheet in
            AIInferenceConnectionEditor(billing: inferenceBilling, profileID: sheet.profileID)
        }
    }

    private func byokConnectionRow(_ profile: AIInferenceConnectionProfile) -> some View {
        let isSelected = inferenceBilling.selectedProfileID == profile.id

        return HStack(spacing: 12) {
            Button {
                updateInferenceBilling { try inferenceBilling.selectConnection(profile.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                        Text(profile.configuration?.baseURL.host ?? profile.provider.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            Button {
                byokConnectionSheet = .edit(profile.id)
            } label: {
                Label(.localizable(.aiBYOKEditConnection), systemImage: "info.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
        .disabled(inferenceBilling.isBusy)
    }

    var byokConnectionsFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.localizable(.aiBYOKConnectionsHelp))
            if inferenceBilling.configurationLoadFailed {
                Text(.localizable(.aiBYOKInvalidConfiguration)).foregroundStyle(.red)
            }
            if let byokStatusMessage {
                Text(byokStatusMessage)
                    .foregroundStyle(byokStatusIsError ? Color.red : Color.secondary)
            }
        }
    }

    func updateInferenceBilling(_ update: () throws -> Void) {
        do {
            try update()
            byokStatusMessage = nil
            byokStatusIsError = false
        } catch {
            byokStatusMessage = (AIInferenceErrorMessage.localizedError(for: error) ?? error).localizedDescription
            byokStatusIsError = true
        }
    }
}
