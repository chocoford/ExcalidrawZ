//
//  Paywall.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI
import StoreKit

import ChocofordUI
import LLMKit
import Shimmer
import SmoothGradient
import SFSafeSymbols

struct Paywall: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @Environment(\.alert) private var alert
    
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var llmState: LLMStateObject
    @ObservedObject private var paywallPresentation = PaywallPresentationState.shared
    
    @State private var selectedSubscriptionItem: SubscriptionItem?
    @State private var isPresented = false
    @State private var billingPeriod: BillingPeriod = .monthly
    @State private var maxCreditTier: MaxCreditTier = .standard
    
    enum Route: Hashable {
        case plans, donation
    }
    
    enum BillingPeriod: String, CaseIterable, Identifiable {
        case monthly
        case yearly
        
        var id: Self { self }
        
        var title: String {
            switch self {
                case .monthly: String(localizable: .paywallBillingPeriodMonthlyTitle)
                case .yearly: String(localizable: .paywallBillingPeriodYearlyTitle)
            }
        }
    }
    
    @State private var route: Route = .plans
    @State private var isDonationHistoryPresented = false
    
    var displayedPlans: [SubscriptionItem] {
        store.plans
    }
    
    private var displayedPlanCards: [SubscriptionItem] {
        var plans = displayedPlans.filter { $0.id != SubscriptionItem.max10x.id }
        if displayedPlans.contains(SubscriptionItem.max10x), !plans.contains(SubscriptionItem.max) {
            plans.append(.max)
        }
        return plans.sorted()
    }
    
    private var activeSubscriptionItem: SubscriptionItem? {
        store.activeSubscriptionItem
    }

    private var currentSubscriptionItemForComparison: SubscriptionItem {
        activeSubscriptionItem ?? .free
    }
    
    private var selectedBillingProduct: Product? {
        guard let selectedSubscriptionItem else { return nil }
        return product(for: selectedSubscriptionItem, billingPeriod: billingPeriod)
        ?? product(for: selectedSubscriptionItem, billingPeriod: .monthly)
    }
    
    private var isSelectedSubscriptionPurchased: Bool {
        if let selectedSubscriptionItem, selectedSubscriptionItem == activeSubscriptionItem {
            return true
        }
        guard let selectedBillingProduct else { return false }
        return store.purchasedPlans.contains { $0.id == selectedBillingProduct.id }
    }

    private var isSelectedPlanIncludedInActivePlan: Bool {
        guard let selectedSubscriptionItem,
              let activeSubscriptionItem,
              selectedSubscriptionItem != activeSubscriptionItem else {
            return false
        }
        return selectedSubscriptionItem < activeSubscriptionItem
    }
    
    private var baseFeatureLines: [Feature] {
        [
            .completeCanvasWorkspace,
            .cloudReadyLibrary,
            .mcpServices
        ]
    }
    
    private var baselinePlan: SubscriptionItem? {
        guard let selectedSubscriptionItem else { return currentSubscriptionItemForComparison }
        return min(selectedSubscriptionItem, currentSubscriptionItemForComparison)
    }

    private var baselinePlanFeatureLines: [Feature] {
        guard let baselinePlan else { return [] }
        return featureLines(for: baselinePlan, maxCredits: maxCredits(for: baselinePlan))
    }

    private var supplementTargetPlan: SubscriptionItem? {
        guard let selectedSubscriptionItem else { return currentSubscriptionItemForComparison }
        return max(selectedSubscriptionItem, currentSubscriptionItemForComparison)
    }

    private var selectedPlanSupplementFeatures: [Feature] {
        guard let supplementTargetPlan,
              let baselinePlan,
              supplementTargetPlan != baselinePlan else {
            return []
        }

        let baselineFeatureIDs = Set(baselinePlanFeatureLines.map(\.id))
        return featureLines(for: supplementTargetPlan, maxCredits: maxCredits(for: supplementTargetPlan))
            .filter { !baselineFeatureIDs.contains($0.id) }
    }
    
    private var selectedPlanSupplementTitle: String {
        guard let supplementTargetPlan else { return "" }
        return planDeltaTitle(for: supplementTargetPlan, maxCredits: maxCredits(for: supplementTargetPlan))
    }
    
    var body: some View {
        content()
            .watch(value: store.purchasedPlans) { _ in
                if let activeSubscriptionItem {
                    selectedSubscriptionItem = activeSubscriptionItem
                } else if selectedSubscriptionItem == nil {
                    selectedSubscriptionItem = recommendedSubscriptionItem()
                }
            }
            .watch(value: store.subscriptions) { _ in
                if selectedSubscriptionItem == nil {
                    selectedSubscriptionItem = defaultSubscriptionItem()
                }
            }
            .watch(value: activeSubscriptionItem) { newValue in
                if let newValue {
                    selectedSubscriptionItem = newValue
                } else if selectedSubscriptionItem == nil {
                    selectedSubscriptionItem = recommendedSubscriptionItem()
                }
            }
            .watch(value: maxCreditTier) { _ in
                guard selectedSubscriptionItem?.id == SubscriptionItem.max.id || selectedSubscriptionItem?.id == SubscriptionItem.max10x.id else { return }
                selectMaxPlan(creditTier: maxCreditTier)
            }
            .watch(value: selectedSubscriptionItem?.id) { itemID in
                if itemID == SubscriptionItem.max10x.id {
                    maxCreditTier = .triple
                } else if itemID == SubscriptionItem.max.id {
                    maxCreditTier = .standard
                }
            }
            .task {
                if selectedSubscriptionItem == nil {
                    selectedSubscriptionItem = defaultSubscriptionItem()
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
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
        .frame(width: horizontalSizeClass == .compact ? 630 : 1040)
#endif
    }
    
    @available(macOS 14.0, iOS 17.0, *)
    @MainActor @ViewBuilder
    private func modernView() -> some View {
        SubscriptionStoreView(groupID: "914DA4EE")
    }
    
    @MainActor @ViewBuilder
    private func lagacyView() -> some View {
        ZStack {
            if horizontalSizeClass == .compact {
                compactLayout()
            } else {
                regularLayout()
            }
        }
        .padding(50)
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
                                .init(color: colorScheme == .dark ? .black : Color(red: 242/255.0, green: 242/255.0, blue: 242/255.0), location: 0.4)
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
        .onAppear {
            isPresented = true
        }
        .onDisappear {
            isPresented = false
        }
    }
    
    @MainActor @ViewBuilder
    private func regularLayout() -> some View {
        ZStack(alignment: .top) {
            // toolbar()
            
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
                            dismiss()
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
                            dismiss()
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
                }
                .frame(width: 390)
            }
        }
        .frame(height: 550)
    }
    
    @MainActor @ViewBuilder
    private func compactLayout() -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                toolbar()
                Spacer()
                HStack {
                    Text(.localizable(.paywallTitle))
                        .font(.largeTitle)
                }
            }
            .frame(maxWidth: .infinity)
            
            reasonBadge()
                .frame(height: 80)
            
            CompactPlansView(selection: $selectedSubscriptionItem, plans: displayedPlans)
            
            VStack {
                purchaseButton()
                HStack {
                    aiUsageSettingsButton()
                    privacyPolicyButton()
                    Spacer()
#if APP_STORE
                    restorePurchasesButton()
#endif
                }
                .font(.footnote)
            }
        }
    }
    
    @ViewBuilder
    private func billingToggle() -> some View {
        HStack(spacing: 6) {
            ForEach(BillingPeriod.allCases) { period in
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        billingPeriod = period
                    }
                } label: {
                    Text(period.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(billingPeriod == period ? .primary : .secondary)
                .background {
                    if billingPeriod == period {
                        Capsule()
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.74))
                            .shadow(color: .accentColor.opacity(0.16), radius: 10, y: 4)
                    }
                }
            }
        }
        .padding(4)
        .background {
            Capsule()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.38))
                .background {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                    }
                }
        }
    }
    
    @MainActor @ViewBuilder
    private func leftFeatureShowcase() -> some View {
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
            
            // reasonBadge()
            
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
    private func debugMockPlanControl() -> some View {
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

    private var debugActivePlanBinding: Binding<SubscriptionItem?> {
        Binding {
            store.debugActiveSubscriptionItem
        } set: { newValue in
            store.debugActiveSubscriptionItem = newValue
            selectedSubscriptionItem = newValue ?? recommendedSubscriptionItem()
        }
    }
#endif
    
    @ViewBuilder
    private func selectedPlanDeltaSections() -> some View {
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
    private func planDeltaSection(title: String, features: [Feature]) -> some View {
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
    
    
    @ViewBuilder
    private func reasonBadge() -> some View {
        if let reason = paywallPresentation.reachReason {
            ZStack {
                if isPresented {
                    Text(reason.description)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background {
                            Capsule().fill(Color.red.opacity(0.5))
                            Capsule().fill(.ultraThickMaterial)
                        }
                        .transition(.scale.animation(.bouncy.delay(0.2)))
                        .multilineTextAlignment(.center)
                }
            }
            .animation(.bouncy(duration: 0.3, extraBounce: 0.6), value: isPresented)
        } else {
            Color.clear.frame(height: 1)
        }
    }
    
    @ViewBuilder
    private func featureLine(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemSymbol: feature.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AIAppearancePalette.foregroundGradient)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(feature.title)
                        .font(.callout.weight(.semibold))
                    
                    if let badge = feature.badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background {
                                Capsule()
                                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))
                            }
                    }
                }
                
                Text(feature.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func toolbar() -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.text(square: true))
            
            Spacer()
            
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
    }
    
#if APP_STORE
    @MainActor @ViewBuilder
    private func purchaseButton() -> some View {
        AsyncButton {
            try await purchaseSelectedPlan()
        } label: {
            ZStack {
                if isSelectedSubscriptionPurchased {
                    Text(.localizable(.paywallButtonCurrentPlan))
                } else if isSelectedPlanIncludedInActivePlan {
                    Text(.localizable(.paywallButtonIncludedInCurrentPlan))
                } else if let selectedBillingProduct {
                    let planName: String = selectedSubscriptionItem?.title ?? selectedBillingProduct.displayName
                    let period: String = selectedBillingProduct.subscription?.subscriptionPeriod.formatted(selectedBillingProduct.subscriptionPeriodFormatStyle) ?? ""
                    if horizontalSizeClass == .compact {
                        Text(.localizable(.paywallButtonSubscribe(planName)))
                    } else {
                        Text(.localizable(.paywallButtonSubscribe(planName))) +
                        Text(" \(selectedBillingProduct.displayPrice) \(period)").font(.footnote)
                    }
                }
            }
            .padding(.horizontal)
            .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : nil)
        }
        .controlSize({
            if #available(macOS 14.0, iOS 17.0, *) {
                .extraLarge
            } else {
                .large
            }
        }())
        .buttonStyle(.borderedProminent)
        .disabled(selectedBillingProduct == nil || isSelectedSubscriptionPurchased || isSelectedPlanIncludedInActivePlan)
    }
    
    @MainActor @ViewBuilder
    private func restorePurchasesButton() -> some View {
        AsyncButton {
            await store.refreshEntitlements(reason: .restorePurchases, force: true)
            alertToast(.init(displayMode: .hud, type: .complete(.green), title: String(localizable: .paywallRestorePurchasesDoneAlertTitle)))
        } label: {
            Text(localizable: .paywallButtonRestorePurchases)
        }
        .buttonStyle(.borderless)
    }
    
    @MainActor
    private func purchaseSelectedPlan() async throws {
        if let product = selectedBillingProduct {
            if let _ = try await store.purchase(product, handleVerifiedPurchase: { verificationResult in
                try await llmState.handlePurchase(verificationResult: verificationResult)
            }) {
                dismiss()
            }
        }
    }
#else
    @State private var isSwitchToAppStoreSheetPresented = false
    
    @MainActor @ViewBuilder
    private func purchaseButton() -> some View {
        Button {
            isSwitchToAppStoreSheetPresented.toggle()
        } label: {
            Text(localizable: .paywallButtonInstallAppStoreVersion)
        }
        .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .capsule)
        .modifier(SwitchAppStoreVersionViewViewModifier(isPresented: $isSwitchToAppStoreSheetPresented))
    }
#endif
    
    @MainActor @ViewBuilder
    private func privacyPolicyButton() -> some View {
        HStack {
            if let privacyPolicy = URL(string: "https://excalidrawz.chocoford.com/privacy/") {
                Link(.localizable(.generalButtonPrivacyPolicy), destination: privacyPolicy)
            }
            Text("·")
            if let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                Link(.localizable(.generalButtonTermsOfUse), destination: termsOfUse)
            }
        }
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
    }
    
    @MainActor @ViewBuilder
    private func aiUsageSettingsButton() -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            OpenAIUsageSettingsButton {
                dismiss()
            }
        } else {
            Button {
                dismiss()
                SettingsRouter.shared.requestOpenAIUsage()
            } label: {
                Label(String(localizable: .aiChatUsageTitle), systemImage: "gearshape")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderless)
        }
    }
    
    private func product(for item: SubscriptionItem, billingPeriod: BillingPeriod) -> Product? {
        let productID: String? = {
            if item.id == SubscriptionItem.max.id {
                return maxProductID(forCreditTier: maxCreditTier, billingPeriod: billingPeriod)
            }
            
            return switch billingPeriod {
                case .monthly:
                    item.id
                case .yearly:
                    item.yearlyID
            }
        }()
        guard let productID else { return nil }
        return store.subscriptions.first { $0.id == productID }
    }
    
    private func recommendedSubscriptionItem() -> SubscriptionItem? {
        if displayedPlanCards.contains(.pro) {
            return .pro
        }
        return displayedPlanCards.first
    }

    private func defaultSubscriptionItem() -> SubscriptionItem? {
        activeSubscriptionItem ?? recommendedSubscriptionItem()
    }

    private func planDeltaTitle(for plan: SubscriptionItem, maxCredits: Int) -> String {
        if plan.id == SubscriptionItem.max10x.id {
            return "Max \(MaxCreditTier.triple.title)"
        }
        if plan.id == SubscriptionItem.max.id {
            let tier = maxCredits == MaxCreditTier.triple.credits ? MaxCreditTier.triple : MaxCreditTier.standard
            return "Max \(tier.title)"
        }
        return plan.title
    }
    
    private func maxProductID(forCreditTier creditTier: MaxCreditTier, billingPeriod: BillingPeriod) -> String {
        switch (billingPeriod, creditTier) {
            case (.monthly, .standard):
                "plan.max_3x"
            case (.yearly, .standard):
                "plan.max_3x_yearly"
            case (.monthly, .triple):
                "plan.max_10x"
            case (.yearly, .triple):
                "plan.max_10x_yearly"
        }
    }
    
    private func selectMaxPlan(creditTier: MaxCreditTier) {
        selectedSubscriptionItem = creditTier == .triple ? .max10x : .max
    }
    
    private var selectedMaxCredits: Int {
        if selectedSubscriptionItem?.id == SubscriptionItem.max10x.id {
            return MaxCreditTier.triple.credits
        }
        return maxCreditTier.credits
    }
    
    private func activeMaxCredits(for plan: SubscriptionItem) -> Int {
        if plan.id == SubscriptionItem.max10x.id {
            return MaxCreditTier.triple.credits
        }
        return MaxCreditTier.standard.credits
    }

    private func maxCredits(for plan: SubscriptionItem) -> Int {
        if plan == selectedSubscriptionItem {
            return selectedMaxCredits
        }
        return activeMaxCredits(for: plan)
    }
    
    private func featureLines(for plan: SubscriptionItem, maxCredits: Int? = nil) -> [Feature] {
        switch plan.id {
            case SubscriptionItem.free.id:
                []
            case SubscriptionItem.starter.id:
                starterFeatureLines
            case SubscriptionItem.pro.id:
                starterFeatureLines + proFeatureLines
            case SubscriptionItem.max.id:
                starterFeatureLines + maxFeatureLines(credits: maxCredits ?? MaxCreditTier.standard.credits)
            case SubscriptionItem.max10x.id:
                starterFeatureLines + maxFeatureLines(credits: maxCredits ?? MaxCreditTier.triple.credits)
            default:
                []
        }
    }
    
    private var starterFeatureLines: [Feature] {
        [
            .unlimitedCollaborationTools
        ]
    }
    
    private var proFeatureLines: [Feature] {
        [
            .proAICredits
        ]
    }
    
    private func maxFeatureLines(credits: Int) -> [Feature] {
        [
            .maxAICredits(credits),
            .extraHighModelCapability
        ]
    }
}

private struct PaywallAuroraBackground: View {
    let colorScheme: ColorScheme
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let topHueA = AIAppearancePalette.Hue.cyan + sin(time * 0.10) * 0.035
            let topHueB = AIAppearancePalette.Hue.indigo + cos(time * 0.14) * 0.03
            let bottomHueA = AIAppearancePalette.Hue.pink + sin(time * 0.12) * 0.026
            let bottomHueB = AIAppearancePalette.Hue.purple + cos(time * 0.09) * 0.034
            let driftX = CGFloat(sin(time * 0.22)) * 34
            let driftY = CGFloat(cos(time * 0.18)) * 24
            let base = AIAppearancePalette.paywallBase(for: colorScheme)
            
            GeometryReader { proxy in
                ZStack {
                    base
                    
                    LinearGradient(
                        colors: [
                            Color(hue: topHueA, saturation: 0.58, brightness: 1).opacity(colorScheme == .dark ? 0.30 : 0.42),
                            Color(hue: topHueB, saturation: 0.44, brightness: 1).opacity(colorScheme == .dark ? 0.16 : 0.24),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: proxy.size.height * 0.55)
                    .blur(radius: 42)
                    .offset(x: driftX * 0.45, y: -proxy.size.height * 0.18 + driftY)
                    
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(hue: bottomHueB, saturation: 0.48, brightness: 1).opacity(colorScheme == .dark ? 0.15 : 0.22),
                            Color(hue: bottomHueA, saturation: 0.52, brightness: 1).opacity(colorScheme == .dark ? 0.26 : 0.34)
                        ],
                        startPoint: .top,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: proxy.size.height * 0.62)
                    .blur(radius: 48)
                    .offset(x: -driftX * 0.65, y: proxy.size.height * 0.22 - driftY)
                    
                    Circle()
                        .fill(Color(hue: topHueA, saturation: 0.62, brightness: 1).opacity(colorScheme == .dark ? 0.16 : 0.20))
                        .frame(width: 360, height: 360)
                        .blur(radius: 72)
                        .offset(x: -proxy.size.width * 0.34 + driftX, y: -proxy.size.height * 0.18)
                    
                    Circle()
                        .fill(Color(hue: bottomHueA, saturation: 0.58, brightness: 1).opacity(colorScheme == .dark ? 0.14 : 0.18))
                        .frame(width: 430, height: 430)
                        .blur(radius: 88)
                        .offset(x: proxy.size.width * 0.30 - driftX * 0.55, y: proxy.size.height * 0.30 + driftY)
                }
                .overlay {
                    RadialGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.24),
                            Color(hue: topHueB, saturation: 0.30, brightness: 1).opacity(colorScheme == .dark ? 0.05 : 0.14),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 12,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                    )
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            base.opacity(colorScheme == .dark ? 0.72 : 0.96),
                            base.opacity(colorScheme == .dark ? 0.42 : 0.76),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
    }
}

@available(macOS 14.0, iOS 17.0, *)
private struct OpenAIUsageSettingsButton: View {
    let onOpen: () -> Void
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        Button {
            SettingsRouter.shared.pendingRoute = .ai
            SettingsRouter.shared.pendingAISettingsRoute = .usage
            onOpen()
            openSettings()
        } label: {
            Label(.localizable(.aiChatUsageTitle), systemSymbol: .gearshape)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.accessoryBar)
    }
}


#Preview {
    Paywall()
}
