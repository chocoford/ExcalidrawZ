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
import SFSafeSymbols

struct Paywall: View {
    private static let minimumRegularIOSWidth: CGFloat = 760

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @Environment(\.alert) private var alert
    
    @EnvironmentObject var store: Store
    @EnvironmentObject var llmState: LLMStateObject
    @ObservedObject var paywallPresentation = PaywallPresentationState.shared
    
    @State var selectedSubscriptionItem: SubscriptionItem?
    @State var isPresented = false
    @State var billingPeriod: BillingPeriod = .monthly
    @State var maxCreditTier: MaxCreditTier = .standard
    @State var presentedMCPFeatureHelpID: String?
    
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
    
    @State var route: Route = .plans
    @State var isDonationHistoryPresented = false
    
    var displayedPlans: [SubscriptionItem] {
        store.plans
    }
    
    var displayedPlanCards: [SubscriptionItem] {
        var plans = displayedPlans.filter { $0.id != SubscriptionItem.max10x.id }
        if displayedPlans.contains(SubscriptionItem.max10x), !plans.contains(SubscriptionItem.max) {
            plans.append(.max)
        }
        return plans.sorted()
    }
    
    var activeSubscriptionItem: SubscriptionItem? {
        store.activeSubscriptionItem
    }

    var currentSubscriptionItemForComparison: SubscriptionItem {
        activeSubscriptionItem ?? .free
    }
    
    var selectedBillingProduct: Product? {
        guard let selectedSubscriptionItem else { return nil }
        return product(for: selectedSubscriptionItem, billingPeriod: billingPeriod)
        ?? product(for: selectedSubscriptionItem, billingPeriod: .monthly)
    }
    
    var isSelectedSubscriptionPurchased: Bool {
        if let selectedSubscriptionItem, selectedSubscriptionItem == activeSubscriptionItem {
            return true
        }
        guard let selectedBillingProduct else { return false }
        return store.purchasedPlans.contains { $0.id == selectedBillingProduct.id }
    }

    var isSelectedPlanIncludedInActivePlan: Bool {
        guard let selectedSubscriptionItem,
              let activeSubscriptionItem,
              selectedSubscriptionItem != activeSubscriptionItem else {
            return false
        }
        return selectedSubscriptionItem < activeSubscriptionItem
    }
    
    var baseFeatureLines: [Feature] {
        var features: [Feature] = [.completeCanvasWorkspace]
        if ExcalidrawZMCPServerController.isAvailable {
            features.append(mcpServicesFeature(for: currentSubscriptionItemForComparison))
        }
        return features
    }

    func mcpServicesFeature(for plan: SubscriptionItem) -> Feature {
        plan >= .starter ? .optimizedMCPServices : .basicMCPServices
    }
    
    var baselinePlan: SubscriptionItem? {
        guard let selectedSubscriptionItem else { return currentSubscriptionItemForComparison }
        return min(selectedSubscriptionItem, currentSubscriptionItemForComparison)
    }

    var baselinePlanFeatureLines: [Feature] {
        guard let baselinePlan else { return [] }
        return featureLines(for: baselinePlan, maxCredits: maxCredits(for: baselinePlan))
    }

    var supplementTargetPlan: SubscriptionItem? {
        guard let selectedSubscriptionItem else { return currentSubscriptionItemForComparison }
        return max(selectedSubscriptionItem, currentSubscriptionItemForComparison)
    }

    var selectedPlanSupplementFeatures: [Feature] {
        guard let supplementTargetPlan,
              let baselinePlan,
              supplementTargetPlan != baselinePlan else {
            return []
        }

        let baselineFeatureIDs = Set(
            planComparisonFeatureLines(
                for: baselinePlan,
                maxCredits: maxCredits(for: baselinePlan)
            )
            .map(\.id)
        )
        return planComparisonFeatureLines(
            for: supplementTargetPlan,
            maxCredits: maxCredits(for: supplementTargetPlan)
        )
        .filter { !baselineFeatureIDs.contains($0.id) }
    }
    
    var selectedPlanSupplementTitle: String {
        guard let supplementTargetPlan else { return "" }
        return planDeltaTitle(for: supplementTargetPlan, maxCredits: maxCredits(for: supplementTargetPlan))
    }

    var isCompactIOSPaywall: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private func shouldUseCompactIOSPaywall(availableWidth: CGFloat) -> Bool {
#if os(iOS)
        isCompactIOSPaywall ||
        (availableWidth > 0 && availableWidth < Self.minimumRegularIOSWidth)
#else
        false
#endif
    }

    var compactSelectedFeatureLines: [Feature] {
        guard let selectedSubscriptionItem else { return baseFeatureLines }
        return planComparisonFeatureLines(
            for: selectedSubscriptionItem,
            maxCredits: maxCredits(for: selectedSubscriptionItem)
        )
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
    
    @ViewBuilder
    private func content() -> some View {
#if os(iOS)
        ViewSizeReader { size in
            if shouldUseCompactIOSPaywall(availableWidth: size.width) {
                compactIOSContent()
            } else {
                regularContent()
            }
        }
#else
        regularContent()
#endif
    }
    
    @available(macOS 14.0, iOS 17.0, *)
    @ViewBuilder
    private func modernView() -> some View {
        SubscriptionStoreView(groupID: "21660497")
    }
    
    @ViewBuilder
    func billingToggle() -> some View {
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
    
    @ViewBuilder
    func reasonBadge() -> some View {
        if let message = paywallPresentation.reachReason?.paywallMessage {
            Text(message)
                .foregroundStyle(.red)
                .font(.footnote)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(Color.red.opacity(0.5))
                    Capsule().fill(.ultraThickMaterial)
                }
                .multilineTextAlignment(.center)
        }
    }
    
    @ViewBuilder
    func featureLine(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemSymbol: feature.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AIAppearancePalette.foregroundGradient)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(feature.title)
                        .font(.callout.weight(.semibold))

                    if let mcpServiceMode = feature.mcpServiceMode {
                        mcpFeatureHelpButton(
                            feature: feature,
                            initialMode: mcpServiceMode
                        )
                    }
                    
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

    @ViewBuilder
    func mcpFeatureHelpButton(
        feature: Feature,
        initialMode: ExcalidrawMCPServiceMode
    ) -> some View {
        Button {
            presentedMCPFeatureHelpID = feature.id
        } label: {
            Image(systemSymbol: .questionmarkCircle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { presentedMCPFeatureHelpID == feature.id },
                set: { isPresented in
                    if !isPresented {
                        presentedMCPFeatureHelpID = nil
                    }
                }
            ),
            arrowEdge: .trailing
        ) {
            MCPServiceModeFeaturesPopoverContent(initialMode: initialMode)
        }
        .help(String(localizable: .settingsAIMCPServiceModeHelp))
    }
    
#if APP_STORE
    @ViewBuilder
    func purchaseButton() -> some View {
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
                    if isCompactIOSPaywall {
                        Text(.localizable(.paywallButtonSubscribe(planName)))
                    } else {
                        Text(.localizable(.paywallButtonSubscribe(planName))) +
                        Text(" \(selectedBillingProduct.displayPrice) \(period)").font(.footnote)
                    }
                }
            }
            .padding(.horizontal)
            .frame(maxWidth: isCompactIOSPaywall ? .infinity : nil)
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
    
    @ViewBuilder
    func restorePurchasesButton() -> some View {
        AsyncButton {
            await store.refreshEntitlements(reason: .restorePurchases, force: true)
            alertToast(.init(displayMode: .hud, type: .complete(.green), title: String(localizable: .paywallRestorePurchasesDoneAlertTitle)))
        } label: {
            Text(localizable: .paywallButtonRestorePurchases)
        }
        .buttonStyle(.borderless)
    }
    
    @MainActor
    func purchaseSelectedPlan() async throws {
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
    
    @ViewBuilder
    func purchaseButton() -> some View {
        Button {
            isSwitchToAppStoreSheetPresented.toggle()
        } label: {
            Text(localizable: .paywallButtonInstallAppStoreVersion)
        }
        .modernButtonStyle(style: .glassProminent, size: .extraLarge, shape: .capsule)
        .modifier(SwitchAppStoreVersionViewViewModifier(isPresented: $isSwitchToAppStoreSheetPresented))
    }
#endif
    
    @ViewBuilder
    func privacyPolicyButton() -> some View {
        VStack(spacing: 3) {
            HStack {
                if let privacyPolicy = URL(string: "https://excalidrawz.chocoford.com/privacy/") {
                    Link(.localizable(.generalButtonPrivacyPolicy), destination: privacyPolicy)
                }
                Text("·")
                if let termsOfUse = URL(string: "https://excalidrawz.chocoford.com/terms/") {
                    Link(.localizable(.generalButtonTermsOfUse), destination: termsOfUse)
                }
            }
        }
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
    }
    
    @ViewBuilder
    func aiUsageSettingsButton() -> some View {
#if os(macOS)
        if #available(macOS 14.0, *) {
            OpenAIUsageSettingsButton {
                dismiss()
            }
        } else {
            fallbackAIUsageSettingsButton
        }
#else
        fallbackAIUsageSettingsButton
#endif
    }

    @MainActor
    var fallbackAIUsageSettingsButton: some View {
        Button {
#if os(iOS)
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                SettingsRouter.shared.requestOpenAIUsage()
            }
#else
            dismiss()
            SettingsRouter.shared.requestOpenAIUsage()
#endif
        } label: {
            Label(String(localizable: .aiChatUsageTitle), systemImage: "gearshape")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
    }
    
    func product(for item: SubscriptionItem, billingPeriod: BillingPeriod) -> Product? {
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
    
    func recommendedSubscriptionItem() -> SubscriptionItem? {
        if displayedPlanCards.contains(.pro) {
            return .pro
        }
        return displayedPlanCards.first
    }

    func defaultSubscriptionItem() -> SubscriptionItem? {
        activeSubscriptionItem ?? recommendedSubscriptionItem()
    }

    func planDeltaTitle(for plan: SubscriptionItem, maxCredits: Int) -> String {
        if plan.id == SubscriptionItem.max10x.id {
            return "Max \(MaxCreditTier.triple.title)"
        }
        if plan.id == SubscriptionItem.max.id {
            let tier = maxCredits == MaxCreditTier.triple.credits ? MaxCreditTier.triple : MaxCreditTier.standard
            return "Max \(tier.title)"
        }
        return plan.title
    }
    
    func maxProductID(forCreditTier creditTier: MaxCreditTier, billingPeriod: BillingPeriod) -> String {
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
    
    func selectMaxPlan(creditTier: MaxCreditTier) {
        selectedSubscriptionItem = creditTier == .triple ? .max10x : .max
    }
    
    var selectedMaxCredits: Int {
        if selectedSubscriptionItem?.id == SubscriptionItem.max10x.id {
            return MaxCreditTier.triple.credits
        }
        return maxCreditTier.credits
    }
    
    func activeMaxCredits(for plan: SubscriptionItem) -> Int {
        if plan.id == SubscriptionItem.max10x.id {
            return MaxCreditTier.triple.credits
        }
        return MaxCreditTier.standard.credits
    }

    func maxCredits(for plan: SubscriptionItem) -> Int {
        if plan == selectedSubscriptionItem {
            return selectedMaxCredits
        }
        return activeMaxCredits(for: plan)
    }
    
    func featureLines(for plan: SubscriptionItem, maxCredits: Int? = nil) -> [Feature] {
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

    func planComparisonFeatureLines(for plan: SubscriptionItem, maxCredits: Int? = nil) -> [Feature] {
        var features: [Feature] = [.completeCanvasWorkspace]
        if ExcalidrawZMCPServerController.isAvailable {
            features.append(mcpServicesFeature(for: plan))
        }
        return features + featureLines(for: plan, maxCredits: maxCredits)
    }
    
    var starterFeatureLines: [Feature] {
        [
            .unlimitedCollaborationTools,
            .presentation
        ]
    }
    
    var proFeatureLines: [Feature] {
        [
            .proAICredits
        ]
    }
    
    func maxFeatureLines(credits: Int) -> [Feature] {
        [
            .maxAICredits(credits),
            .extraHighModelCapability
        ]
    }
}

struct PaywallAuroraBackground: View {
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

#if os(macOS)
@available(macOS 14.0, *)
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
#endif


#Preview {
    Paywall()
}
