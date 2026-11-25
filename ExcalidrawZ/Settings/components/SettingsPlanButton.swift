//
//  SettingsPlanButton.swift
//  ExcalidrawZ
//

import SwiftUI
import LLMKit

#if os(macOS)
struct SettingsPlanButton: View {
#if DEBUG && !APP_STORE
    // Display-only date for the existing Debug plan override.
    private static let debugPlanExpirationDate = Date.now.addingTimeInterval(30 * 24 * 60 * 60)
#endif

    @Environment(Store.self) private var store
    @EnvironmentObject private var llmState: LLMStateObject

    private var plan: SubscriptionItem {
        store.activeSubscriptionItem ?? .free
    }

    private var creditsText: String? {
        guard let balance = llmState.creditsInfo?.balance,
              balance.isFinite, balance > 0 else {
            return nil
        }
        return balance.formatted(.number.precision(.fractionLength(0...2)))
    }

    private var validityText: String? {
        guard store.hasResolvedSubscriptionEntitlements,
              let activePlan = store.activeSubscriptionItem,
              activePlan != .free,
              let expirationDate = planExpirationDate else {
            return nil
        }
        return String(localizable: .settingsPlanValidUntil(
            expirationDate.formatted(date: .abbreviated, time: .omitted)
        ))
    }

    private var planExpirationDate: Date? {
#if DEBUG && !APP_STORE
        if store.debugActiveSubscriptionItem != nil {
            return Self.debugPlanExpirationDate
        }
#endif
        return store.activePlanExpirationDate
    }

    var body: some View {
        Button {
            store.togglePaywall(reason: .manaully)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    if store.hasResolvedSubscriptionEntitlements {
                        Text(plan.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)
                            .layoutPriority(1)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer(minLength: 4)

                    if let creditsText {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.circle")
                                .accessibilityHidden(true)
                            Text(creditsText)
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.medium))
                        .padding(.top, 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(localizable: .settingsAIUsageActivityFileCreditsLabel(creditsText)))
                        .help(String(localizable: .settingsAIUsageActivityFileCreditsLabel(creditsText)))
                    }
                }
                .lineLimit(1)

                if let validityText {
                    Text(validityText)
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AIAppearancePalette.foregroundGradient)
                    .opacity(0.06)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .help(String(localizable: .paywallButtonCurrentPlan))
    }
}
#endif
