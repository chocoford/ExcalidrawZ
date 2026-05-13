//
//  Paywall.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI
import StoreKit

import ChocofordUI
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
    
    @State private var selectedPlan: Product?
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
            .filter({ plan in
                if store.purchasedPlans.isEmpty { return true }
                if let activePlan = store.plans.first(where: { $0.containsProductID(store.purchasedPlans.first?.id) }) {
                    return plan >= activePlan
                } else {
                    return false
                }
            })
    }
    
    private var displayedPlanCards: [SubscriptionItem] {
        var plans = displayedPlans.filter { $0.id != SubscriptionItem.max10x.id }
        if displayedPlans.contains(SubscriptionItem.max10x), !plans.contains(SubscriptionItem.max) {
            plans.append(.max)
        }
        return plans.sorted()
    }
    
    private var selectedSubscriptionItem: SubscriptionItem? {
        store.plans.first { $0.containsProductID(selectedPlan?.id) }
    }
    
    private var activeSubscriptionItem: SubscriptionItem? {
        guard let purchasedPlan = store.purchasedPlans.first else { return nil }
        return store.plans.first { $0.containsProductID(purchasedPlan.id) }
    }
    
    private var selectedBillingProduct: Product? {
        guard let selectedSubscriptionItem else { return selectedPlan }
        return product(for: selectedSubscriptionItem, billingPeriod: billingPeriod)
        ?? product(for: selectedSubscriptionItem, billingPeriod: .monthly)
        ?? selectedPlan
    }
    
    private var isSelectedSubscriptionPurchased: Bool {
        guard let selectedBillingProduct else { return false }
        return store.purchasedPlans.contains { $0.id == selectedBillingProduct.id }
    }
    
    private var baseFeatureLines: [Feature] {
        [
            .completeCanvasWorkspace,
            .cloudReadyLibrary,
            .mcpServices
        ]
    }
    
    private var currentOwnedFeatureLines: [Feature] {
        guard let activeSubscriptionItem else { return [] }
        return featureLines(for: activeSubscriptionItem, maxCredits: activeMaxCredits(for: activeSubscriptionItem))
    }
    
    private var selectedPlanExtraFeatures: [Feature] {
        guard let selectedSubscriptionItem else {
            return []
        }
        
        let ownedFeatureIDs = Set(currentOwnedFeatureLines.map(\.id))
        let features = featureLines(for: selectedSubscriptionItem, maxCredits: selectedMaxCredits)
            .filter { !ownedFeatureIDs.contains($0.id) }
        
        if features.isEmpty {
            return []
        }
        return features
    }
    
    private var selectedPlanExtraTitle: String {
        guard let selectedSubscriptionItem else { return "" }
        if selectedSubscriptionItem.id == SubscriptionItem.max10x.id {
            return "Max \(MaxCreditTier.triple.title)"
        }
        if selectedSubscriptionItem.id == SubscriptionItem.max.id {
            return "Max \(maxCreditTier.title)"
        }
        return selectedSubscriptionItem.title
    }
    
    var body: some View {
        content()
            .watch(value: store.purchasedPlans) { newValue in
                if let purchasedPlans = newValue.first {
                    self.selectedPlan = purchasedPlans
                } else {
                    self.selectedPlan = firstProduct(for: billingPeriod)
                }
            }
            .watch(value: store.subscriptions) { newValue in
                if selectedPlan == nil {
                    selectedPlan = firstProduct(for: billingPeriod)
                }
            }
            .watch(value: billingPeriod) { newValue in
                guard let selectedSubscriptionItem else {
                    selectedPlan = firstProduct(for: newValue)
                    return
                }
                selectedPlan = product(for: selectedSubscriptionItem, billingPeriod: newValue)
                ?? product(for: selectedSubscriptionItem, billingPeriod: .monthly)
                ?? firstProduct(for: newValue)
            }
            .watch(value: maxCreditTier) { _ in
                guard selectedSubscriptionItem?.id == SubscriptionItem.max.id || selectedSubscriptionItem?.id == SubscriptionItem.max10x.id else { return }
                selectMaxPlan(creditTier: maxCreditTier)
            }
            .watch(value: selectedPlan?.id) { productID in
                if SubscriptionItem.max10x.containsProductID(productID) {
                    maxCreditTier = .triple
                } else if SubscriptionItem.max.containsProductID(productID) {
                    maxCreditTier = .standard
                }
            }
            .task {
                if selectedPlan == nil {
                    selectedPlan = firstProduct(for: billingPeriod)
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
                    
                    RegularPlansView(
                        selection: $selectedPlan,
                        maxCreditTier: $maxCreditTier,
                        billingPeriod: billingPeriod,
                        plans: displayedPlanCards,
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
            
            CompactPlansView(selection: $selectedPlan, plans: displayedPlans)
            
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
                
                ForEach(currentOwnedFeatureLines) { feature in
                    featureLine(feature)
                }
            }
            
            selectedPlanExtras()
            
            Spacer(minLength: 0)
            
            HStack {
                aiUsageSettingsButton()
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private func selectedPlanExtras() -> some View {
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
                
                Text("With \(selectedPlanExtraTitle)")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(selectedPlanExtraFeatures) { feature in
                    featureLine(feature)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .id("\(selectedSubscriptionItem?.id ?? "none")-\(maxCreditTier.rawValue)")
        }
        .frame(height: 180, alignment: .top)
        .animation(.smooth(duration: 0.22), value: selectedSubscriptionItem?.id)
        .animation(.smooth(duration: 0.22), value: maxCreditTier)
    }
    
    
    @ViewBuilder
    private func reasonBadge() -> some View {
        if let reason = store.reachPaywallReason {
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
        .disabled(selectedBillingProduct == nil || isSelectedSubscriptionPurchased)
    }
    
    @MainActor @ViewBuilder
    private func restorePurchasesButton() -> some View {
        AsyncButton {
            await store.updateCustomerProductStatus()
            alert(title: .localizable(.paywallRestorePurchasesDoneAlertTitle)) {
                
            }
        } label: {
            Text(.localizable(.paywallButtonRestorePurchases))
        }
        .buttonStyle(.borderless)
    }
    
    private func purchaseSelectedPlan() async throws {
        if let product = selectedBillingProduct {
            if let _ = try await store.purchase(product) {
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
    
    private func firstProduct(for billingPeriod: BillingPeriod) -> Product? {
        displayedPlanCards
            .lazy
            .compactMap { product(for: $0, billingPeriod: billingPeriod) ?? product(for: $0, billingPeriod: .monthly) }
            .first
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
    
    private func product(forMaxCreditTier creditTier: MaxCreditTier, billingPeriod: BillingPeriod) -> Product? {
        let productID = maxProductID(forCreditTier: creditTier, billingPeriod: billingPeriod)
        return store.subscriptions.first { $0.id == productID }
    }
    
    private func selectMaxPlan(creditTier: MaxCreditTier) {
        selectedPlan = product(forMaxCreditTier: creditTier, billingPeriod: billingPeriod)
        ?? product(forMaxCreditTier: creditTier, billingPeriod: .monthly)
        ?? selectedPlan
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
    
    private func featureLines(for plan: SubscriptionItem, maxCredits: Int? = nil) -> [Feature] {
        switch plan.id {
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
