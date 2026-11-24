//
//  Paywall+CompactIOS.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/09.
//

import SwiftUI

import ChocofordUI
import LLMKit
import Shimmer
import SFSafeSymbols

#if os(iOS)

extension Paywall {
    @ViewBuilder
    func compactIOSContent() -> some View {
        NavigationStack {
            ZStack {
                if route == .plans {
                    compactIOSPlansLayout()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    compactIOSDonationLayout()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .toolbar {
                compactIOSToolbarContent()
            }
            .toolbarBackground(.visible, for: .bottomBar)
            .background {
                PaywallAuroraBackground(colorScheme: colorScheme)
                    .ignoresSafeArea()
            }
            .animation(.easeOut(duration: 0.3), value: route)
            .onAppear {
                isPresented = true
            }
            .task {
                guard AIChatPreferences.shared.isAIEnabled else { return }
                await LLMCreditsRefreshCoordinator.shared.refreshCredits(reason: .paywallAppear)
            }
            .onDisappear {
                isPresented = false
            }
        }
    }

    @ViewBuilder
    func compactIOSPlansLayout() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(.localizable(.paywallTitle))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(localizable: .paywallSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                reasonBadge()

                billingToggle()

                RegularPlansView(
                    selection: $selectedSubscriptionItem,
                    maxCreditTier: $maxCreditTier,
                    billingPeriod: billingPeriod,
                    plans: displayedPlanCards,
                    activePlan: activeSubscriptionItem,
                    productProvider: { plan in
                        product(for: plan, billingPeriod: billingPeriod)
                        ?? product(for: plan, billingPeriod: .monthly)
                    },
                    maxCreditTierChangeHandler: { tier in
                        selectMaxPlan(creditTier: tier)
                    }
                )

                compactIOSFeatureList()

                compactIOSFooterActions()
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    func compactIOSDonationLayout() -> some View {
#if APP_STORE
        let isAppStore = true
#else
        let isAppStore = false
#endif
        SupportChocofordView(isAppStore: isAppStore)
            .contentPadding(16)
            .bindingSupportHistoryPresentedValue($isDonationHistoryPresented)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.default, value: isDonationHistoryPresented)
    }

    @ToolbarContentBuilder
    func compactIOSToolbarContent() -> some ToolbarContent {
        if route == .plans {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismissPaywall()
                } label: {
                    Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut(.cancelAction)
            }

            ToolbarItem(placement: .bottomBar) {
                purchaseButton()
                    .frame(maxWidth: .infinity)
            }

            ToolbarItem(placement: .automatic) {
                compactIOSDonationButton()
            }
        } else if !isDonationHistoryPresented {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    route = .plans
                } label: {
                    Label(
                        .localizable(.navigationButtonBack),
                        systemSymbol: .chevronLeft
                    )
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    @ViewBuilder
    func compactIOSFeatureList() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(compactSelectedFeatureLines) { feature in
                featureLine(feature)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    func compactIOSFooterActions() -> some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    aiUsageSettingsButton()

                    Spacer(minLength: 0)

#if APP_STORE
                    restorePurchasesButton()
#endif

                    privacyPolicyButton()
                }

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        aiUsageSettingsButton()

#if APP_STORE
                        restorePurchasesButton()
#endif
                    }

                    privacyPolicyButton()
                }
                .frame(maxWidth: .infinity)
            }
            .font(.caption)

            Text(localizable: .paywallAICloudDisclosure)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }

    @ViewBuilder
    func compactIOSDonationButton() -> some View {
        Button {
            route = .donation
        } label: {
            HStack(spacing: 4) {
                Text(.localizable(.paywallButtonDonation))
                Image(systemSymbol: .chevronRight2)
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .shimmering(
                animation: Animation.linear(duration: 1).delay(2).repeatForever(autoreverses: false),
                gradient: Gradient(colors: [.white, .white.opacity(0.3), .white])
            )
        }
        .buttonStyle(.borderless)
    }
}

#endif
