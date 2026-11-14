import SwiftUI
import ChocofordUI

extension AIInferenceIntegrationMode {
    var title: String {
        switch self {
            case .basic: String(localizable: .aiBYOKBasicOption)
            case .optimized: String(localizable: .aiBYOKOptimizedOption)
        }
    }
}

extension AISettingsView {
    var byokIntegrationModeRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                byokIntegrationModeLabel
                Spacer(minLength: 16)
                byokIntegrationModePicker
            }
            VStack(alignment: .leading, spacing: 8) {
                byokIntegrationModeLabel
                byokIntegrationModePicker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $byokIntegrationHelpMode) { mode in
            BYOKIntegrationHelpSheet(initialMode: mode)
        }
        .onAppear(perform: resetUnauthorizedBYOKIntegrationMode)
        .watch(value: store.canUseOptimizedBYOKServices) {
            resetUnauthorizedBYOKIntegrationMode()
        }
        .watch(value: store.hasResolvedSubscriptionEntitlements) {
            resetUnauthorizedBYOKIntegrationMode()
        }
        .watch(value: inferenceBilling.integrationMode) {
            resetUnauthorizedBYOKIntegrationMode()
        }
        .watch(value: inferenceBilling.isBusy) {
            resetUnauthorizedBYOKIntegrationMode()
        }
    }

    private var byokIntegrationModeLabel: some View {
        HStack(spacing: 4) {
            Text(.localizable(.aiBYOKIntegrationTitle))
            Button {
                byokIntegrationHelpMode = inferenceBilling.integrationMode
            } label: {
                Label(.localizable(.aiBYOKIntegrationTitle), systemImage: "questionmark.circle")
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var byokIntegrationModePicker: some View {
        Picker(.localizable(.aiBYOKIntegrationTitle), selection: Binding(
            get: { inferenceBilling.integrationMode },
            set: { mode in
                // Match the native MCP picker: defer entitlement changes until selection settles.
                Task { @MainActor in
                    await Task.yield()
                    selectBYOKIntegrationMode(mode)
                }
            }
        )) {
            ForEach(AIInferenceIntegrationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .aiIntegrationModePickerShape()
        .fixedSize(horizontal: true, vertical: true)
        .disabled(inferenceBilling.isBusy)
        .id(byokIntegrationPickerID)
    }

    private func selectBYOKIntegrationMode(_ mode: AIInferenceIntegrationMode) {
        if mode == .optimized, !store.hasResolvedSubscriptionEntitlements {
            byokIntegrationPickerID = UUID()
            return
        }
        if mode == .optimized, !store.canUseOptimizedBYOKServices {
            updateInferenceBilling { try inferenceBilling.setIntegrationMode(.basic) }
            byokIntegrationPickerID = UUID()
            presentPaywall(reason: .optimizedBYOK)
            return
        }
        guard mode != inferenceBilling.integrationMode else { return }
        updateInferenceBilling { try inferenceBilling.setIntegrationMode(mode) }
    }

    private func resetUnauthorizedBYOKIntegrationMode() {
        guard inferenceBilling.integrationMode == .optimized,
              store.hasResolvedSubscriptionEntitlements,
              !store.canUseOptimizedBYOKServices, !inferenceBilling.isBusy else { return }
        updateInferenceBilling { try inferenceBilling.setIntegrationMode(.basic) }
        byokIntegrationPickerID = UUID()
    }
}

private struct BYOKIntegrationHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AIInferenceIntegrationMode

    init(initialMode: AIInferenceIntegrationMode) {
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Text(.localizable(.aiBYOKIntegrationTitle))
                    .font(.headline)
                    .padding(.horizontal, 48)
                HStack {
                    Button { dismiss() } label: {
                        Label(.localizable(.generalButtonClose), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 18, height: 18)
                    }
                    .modernButtonStyle(style: .glass, size: .large, shape: .circle)
                    .keyboardShortcut(.cancelAction)
                    Spacer(minLength: 0)
                }
            }

            Picker(.localizable(.aiBYOKIntegrationTitle), selection: $mode) {
                ForEach(AIInferenceIntegrationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .aiIntegrationModePickerShape()

            VStack(spacing: 10) {
                if mode == .basic {
                    featureRow("arrow.up.right", title: .aiBYOKDirectConnectionTitle, message: .aiBYOKBasicDescription)
                    featureRow("pencil.and.outline", title: .aiBYOKBasicDrawingTitle, message: .aiBYOKBasicDrawingDescription)
                    featureRow("key", title: .paywallPlanFreeTitle, message: .aiBYOKBasicFreeDescription)
                } else {
                    featureRow("cloud", title: .aiBYOKManagedConnectionTitle, message: .aiBYOKSettingsFooter)
                    featureRow("sparkles", title: .aiBYOKOptimizedFeatureTitle, message: .aiBYOKOptimizedFeatureDescription)
                    featureRow("key", title: .paywallPlanStarterTitle, message: .aiBYOKStarterPlanDescription)
                }
            }

            Text(.localizable(.aiBYOKProviderBillingNote))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
#if os(macOS)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
#endif
    }

    private func featureRow(_ symbol: String, title: String.Localizable, message: String.Localizable) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(.localizable(title))
                    .font(.callout.weight(.semibold))
                Text(.localizable(message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
}
