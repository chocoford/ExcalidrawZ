//
//  Paywall+Regular.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/09.
//

import SwiftUI

import ChocofordUI
import LLMKit
import Shimmer
import SFSafeSymbols

extension Paywall {
    @ViewBuilder
    func regularContent() -> some View {
        ZStack {
            lagacyView()
                .offset(x: route == .plans ? 0 : -100)

            if route == .donation {
#if APP_STORE
                let isAppStore = true
#else
                let isAppStore = false
#endif
                SupportChocofordView(isAppStore: isAppStore)
                    .contentPadding(40)
                    .bindingSupportHistoryPresentedValue($isDonationHistoryPresented)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, horizontalSizeClass == .compact ? 30 : 0)
                    .overlay(alignment: .topLeading) {
                        if !isDonationHistoryPresented {
                            Button {
                                route = .plans
                            } label: {
                                Label(
                                    .localizable(.navigationButtonBack),
                                    systemSymbol: .chevronLeft
                                )
                            }
                            .buttonStyle(.text)
                            .padding(40)
                        }
                    }
                    .animation(.default, value: isDonationHistoryPresented)
                    .background {
                        Color.windowBackgroundColor
                            .ignoresSafeArea()
                    }
                    .compositingGroup()
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.3), value: route)
#if os(macOS)
        .frame(idealWidth: horizontalSizeClass == .compact ? 630 : 1040)
#endif
    }

    @ViewBuilder
    func lagacyView() -> some View {
        ZStack {
            regularLayout()
        }
        .padding(50)
#if os(macOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
        .background {
            if #available(iOS 26.0, macOS 26.0, *) {
                PaywallAuroraBackground(colorScheme: colorScheme)
                    .ignoresSafeArea()
            } else {
                ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: .accent, location: 0),
                        ] + [{
                            if horizontalSizeClass == .compact {
                                .init(
                                    color: colorScheme == .dark
                                        ? .black
                                        : Color(red: 242 / 255.0, green: 242 / 255.0, blue: 242 / 255.0),
                                    location: 0.4
                                )
                            } else {
                                .init(color: colorScheme == .dark ? .black : .white, location: 0.4)
                            }
                        }()],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
                .scaleEffect(1.1)
            }
        }
        .task {
            guard AIChatPreferences.shared.isAIEnabled else { return }
            await LLMCreditsRefreshCoordinator.shared.refreshCredits(reason: .paywallAppear)
        }
        .onAppear {
            isPresented = true
        }
        .onDisappear {
            isPresented = false
        }
    }

    @ViewBuilder
    func regularLayout() -> some View {
        ZStack(alignment: .top) {
            HStack(alignment: .center, spacing: 52) {
                leftFeatureShowcase()
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 16) {
                    billingToggle()

                    Spacer(minLength: 0)
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
                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        // Keep center
                        Button {
                            dismissPaywall()
                        } label: {
                            Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
                                .labelStyle(.iconOnly)
                        }
                        .modernButtonStyle(
                            style: .glass,
                            size: .extraLarge,
                            shape: .circle
                        )
                        .opacity(0)

                        purchaseButton()

                        Button {
                            dismissPaywall()
                        } label: {
                            Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
                                .labelStyle(.iconOnly)
                        }
                        .modernButtonStyle(
                            style: .glass,
                            size: .extraLarge,
                            shape: .circle
                        )
                        .keyboardShortcut(.cancelAction)
                    }

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack {
                            Spacer()
#if APP_STORE
                            restorePurchasesButton()
#endif
                            privacyPolicyButton()

                            Button {
                                route = .donation
                            } label: {
                                HStack {
                                    Text(.localizable(.paywallButtonDonation))
                                    Image(systemSymbol: .chevronRight2)
                                }
                                .foregroundStyle(.primary)
                                .shimmering(
                                    animation: Animation.linear(duration: 1).delay(2).repeatForever(autoreverses: false),
                                    gradient: Gradient(colors: [.white, .white.opacity(0.3), .white])
                                )
                            }
                            .buttonStyle(.borderless)
                        }
                        .font(.footnote)

                        Text(localizable: .paywallAICloudDisclosure)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.footnote)
                    }
                }
                .frame(width: 390)
            }
        }
        .frame(height: 550)
    }

    @ViewBuilder
    func leftFeatureShowcase() -> some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Text(.localizable(.paywallTitle))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .tracking(-1.0)
                    .foregroundStyle(.primary)

                Text(localizable: .paywallSubtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(baseFeatureLines) { feature in
                    featureLine(feature)
                }

                ForEach(baselinePlanFeatureLines) { feature in
                    featureLine(feature)
                }
            }
            selectedPlanDeltaSections()

            Spacer(minLength: 0)

            HStack {
                aiUsageSettingsButton()

                Spacer()
                    .overlay(alignment: .leading) {
#if DEBUG && !APP_STORE
                        debugMockPlanControl()
#endif
                    }
            }
        }
    }

#if DEBUG && !APP_STORE
    @ViewBuilder
    func debugMockPlanControl() -> some View {
        HStack(spacing: 8) {
            Text("Debug current plan")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Picker("Debug current plan", selection: debugActivePlanBinding) {
                Text("None").tag(Optional<SubscriptionItem>.none)
                Text(SubscriptionItem.starter.title).tag(Optional.some(SubscriptionItem.starter))
                Text(SubscriptionItem.pro.title).tag(Optional.some(SubscriptionItem.pro))
                Text(SubscriptionItem.max.title).tag(Optional.some(SubscriptionItem.max))
                Text(SubscriptionItem.max10x.title).tag(Optional.some(SubscriptionItem.max10x))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 140)
        }
    }

    var debugActivePlanBinding: Binding<SubscriptionItem?> {
        Binding {
            store.debugActiveSubscriptionItem
        } set: { newValue in
            store.debugActiveSubscriptionItem = newValue
            selectedSubscriptionItem = newValue ?? recommendedSubscriptionItem()
        }
    }
#endif

    @ViewBuilder
    func selectedPlanDeltaSections() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !selectedPlanSupplementFeatures.isEmpty {
                planDeltaSection(
                    title: "With \(selectedPlanSupplementTitle)",
                    features: selectedPlanSupplementFeatures
                )
            }
        }
        .id("\(selectedSubscriptionItem?.id ?? "none")-\(activeSubscriptionItem?.id ?? "none")-\(maxCreditTier.rawValue)")
        .animation(.smooth(duration: 0.22), value: selectedSubscriptionItem?.id)
        .animation(.smooth(duration: 0.22), value: activeSubscriptionItem?.id)
        .animation(.smooth(duration: 0.22), value: maxCreditTier)
    }

    @ViewBuilder
    func planDeltaSection(title: String, features: [Feature]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.secondary.opacity(0.24)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 54, height: 1)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(features) { feature in
                    featureLine(feature)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
}
