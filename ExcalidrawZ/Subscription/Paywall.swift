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


struct Paywall: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) private var alertToast
    @Environment(\.alert) private var alert
    
    @State private var selection: SubscriptionItem = .free
    @EnvironmentObject private var store: Store
    
    @State private var selectedPlan: Product?
    
    @State private var isPresented = false
    
    enum Route: Hashable {
        case plans, donation
    }
    
    @State private var route: Route = .plans
    @State private var isDonationHistoryPresented = false
    
    var displayedPlans: [SubscriptionItem] {
        store.plans
            .filter({ plan in
                if store.purchasedPlans.isEmpty { return true }
                if let activePlan = store.plans.first(where: {$0.id == store.purchasedPlans.first?.id}) {
                    return plan >= activePlan
                } else {
                    return false
                }
            })
            .filter({
                $0 != .free || horizontalSizeClass != .compact
            })
    }

    var body: some View {
        content()
            .watchImmediately(of: store.purchasedPlans) { newValue in
                if let purchasedPlans = newValue.first {
                    self.selectedPlan = purchasedPlans
                } else if horizontalSizeClass == .compact {
                    self.selectedPlan = store.subscriptions.first
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        ZStack {
            lagacyView()
                .offset(x: route == .plans ? 0 : -100)
            
            if route == .donation {
                SupportChocofordView(isAppStore: true)
                    .contentPadding(40)
                    .bindingSupportHistoryPresentedValue($isDonationHistoryPresented)
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
        .frame(width: store.purchasedPlans.isEmpty ? 915 : 630)
#endif
    }
    
    @available(macOS 14.0, iOS 17.0, *)
    @MainActor @ViewBuilder
    private func modernView() -> some View {
        SubscriptionStoreView(groupID: "914DA4EE")
    }
    
    @MainActor @ViewBuilder
    private func lagacyView() -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                if horizontalSizeClass == .compact {
                    toolbar()
                    Spacer()
                }
                HStack {
                    Text(.localizable(.paywallTitle))
                        .font(.largeTitle)
                }
            }
            .frame(maxWidth: .infinity)
            .overlay {
                if horizontalSizeClass != .compact {
                    toolbar()
                }
            }
            
            Color.clear.frame(height: 80)
                .overlay(alignment: .top) {
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
                    }
                }
            
            if horizontalSizeClass == .compact {
                CompactPlansView(selection: $selectedPlan, plans: displayedPlans)
            } else {
                RegularPlansView(selection: $selectedPlan, plans: displayedPlans)
            }
            
            if horizontalSizeClass != .compact {
                HStack {
                    Spacer()
                    
                    purchaseButton()
                    
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    restorePurchasesButton()
                }
            } else {
                VStack {
                    purchaseButton()
                    HStack {
                        privacyPolicyButton()
                        Spacer()
                        restorePurchasesButton()
                    }
                    .font(.footnote)
                }
            }
        }
        .padding(40)
        .background {
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
        }
        .onAppear {
            isPresented = true
        }
        .onDisappear {
            isPresented = false
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
    
    @MainActor @ViewBuilder
    private func purchaseButton() -> some View {
        AsyncButton {
            try await purchaseSelectedPlan()
        } label: {
            ZStack {
                if selectedPlan == store.purchasedPlans.first {
                    Text(.localizable(.paywallButtonCurrentPlan))
                } else if let selectedPlan {
                    let planName: String = store.plans.first(where: {$0.id == selectedPlan.id})?.title ?? selectedPlan.displayName
                    let period: String = selectedPlan.subscription?.subscriptionPeriod.formatted(selectedPlan.subscriptionPeriodFormatStyle) ?? ""
                    if horizontalSizeClass == .compact {
                        Text(.localizable(.paywallButtonSubscribe(planName)))
                    } else {
                        Text(.localizable(.paywallButtonSubscribe(planName))) +
                        Text(" \(selectedPlan.displayPrice) \(period)").font(.footnote)
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
        .disabled(selectedPlan == store.purchasedPlans.first)
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
    
    @MainActor @ViewBuilder
    private func privacyPolicyButton() -> some View {
        Link(destination: URL(string: "https://excalidrawz.chocoford.com/privacy/")!) {
            Text(.localizable(.generalButtonPrivacyPolicy))
        }
        .foregroundStyle(.secondary)
    }
    
    private func purchaseSelectedPlan() async throws {
        if let product = store.subscriptions.first(where: {$0.id == selectedPlan?.id}) {
            if let _ = try await store.purchase(product) {
                dismiss()
            }
        }
    }
}

struct RegularPlansView: View {
    @EnvironmentObject private var store: Store
    
    @Binding var selection: Product?
    var plans: [SubscriptionItem]
    
    var body: some View {
        HStack(spacing: 20) {
            ForEach(plans) { item in
                PlanCard(
                    isSelected: item == .free ? selection == nil : selection?.id == item.id,
                    plan: item,
                    product: store.subscriptions.first(where: {$0.id == item.id})
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.bouncy(duration: 0.2)) {
                        selection = store.subscriptions.first(where: {$0.id == item.id})
                    }
                }
            }
        }
    }
}

struct PlanCard: View {
    var isSelected: Bool
    
    var plan: SubscriptionItem
    var product: Product?
    
    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                
                Text(plan.title)
                    .font(.title)
                
                Text(plan.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 70, alignment: .top)
            }
            
            HStack(alignment: .bottom) {
                if plan == .free {
                    // Text(0.formatted(.currency(code: Locale.current.identifier)))
                    Text({
                        let currencyFormatter = NumberFormatter()
                        currencyFormatter.numberStyle = .currency
                        currencyFormatter.minimumFractionDigits = 2
                        currencyFormatter.locale = product?.priceFormatStyle.locale ?? .current
                        return currencyFormatter.string(from: 0.00) ?? ""
                    }())
                    .font(.title.bold())
                    Text(.localizable(.paywallPlanPeriodForever))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(product?.displayPrice ?? "")
                        .font(.title.bold())
                    if let product, let subscription = product.subscription {
                        Text(subscription.subscriptionPeriod.formatted(product.subscriptionPeriodFormatStyle))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .frame(height: 30)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.features, id: \.self) { feature in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemSymbol: .checkmark)
                            .symbolVariant(.circle)
                            .foregroundStyle(.green)
                        Text(try! AttributedString(markdown: feature))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(width: 260, height: 380, alignment: .top)
        .background {
            let roundedRectangle = RoundedRectangle(cornerRadius: 12)
            
            ZStack {
                roundedRectangle.fill(.ultraThinMaterial)
                if isSelected {
//                    if #available(macOS 14.0, iOS 17.0, *) {
//                        roundedRectangle.fill(.accent.secondary)
//                    } else {
//                        roundedRectangle.fill(.accent.opacity(0.4))
//                    }
                    if #available(macOS 13.0, iOS 17.0, *) {
                        roundedRectangle.stroke(.accent)
                    } else {
                        roundedRectangle.stroke(.accent)
                    }
                } else {
                    
                    if #available(macOS 13.0, iOS 17.0, *) {
                        roundedRectangle.stroke(.separator)
                    } else {
                        roundedRectangle.stroke(.secondary)
                    }
                }
            }
            .shadow(color: .accent, radius: isSelected ? 4 : 0)
            .animation(.easeIn(duration: 0.2), value: isSelected)
        }
        .scaleEffect(isSelected ? 1.03 : 1, anchor: .bottom)
        // .animation(.bouncy(duration: 0.2), value: isSelected)
    }
}

struct CompactPlansView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: Store
    
    @Binding var selection: Product?
    var plans: [SubscriptionItem]
    
    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                let plan: SubscriptionItem = store.plans.first(where: {$0.id == selection?.id}) ?? .free
                ForEach(plan.features, id: \.self) { feature in
                    HStack {
                        Image(systemSymbol: .checkmark)
                            .symbolVariant(.circle)
                            .foregroundStyle(.green)
                        Text(try! AttributedString(markdown: feature))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            
            HStack(spacing: 10) {
                ForEach(plans) { plan in
                    let product: Product? = store.subscriptions.first(where: {$0.id == plan.id})
                    VStack {
                        Text(plan.title)
                        
                        if plan == .free {
                            // Text(0.formatted(.currency(code: Locale.current.identifier)))
                            Text({
                                let currencyFormatter = NumberFormatter()
                                currencyFormatter.numberStyle = .currency
                                currencyFormatter.minimumFractionDigits = 2
                                currencyFormatter.locale = product?.priceFormatStyle.locale ?? .current
                                return currencyFormatter.string(from: 0.00) ?? ""
                            }())
                            .font(.headline)
                            
                            Text(.localizable(.paywallPlanPeriodForever))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(product?.displayPrice ?? "")
                                .font(.headline)
                            if let product, let subscription = product.subscription {
                                Text(subscription.subscriptionPeriod.formatted(product.subscriptionPeriodFormatStyle))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(width: 100, height: 100)
                    .background {
                        let roundedRectangle = RoundedRectangle(cornerRadius: 12)
                        if colorScheme == .light {
                            roundedRectangle
                                .fill(.white)
                        } else {
                            roundedRectangle
                                .fill(.ultraThickMaterial)
                        }
                        if selection == product {
                            roundedRectangle
                                .stroke(Color.accentColor)
                        }
                    }
                    .onTapGesture {
                        withAnimation(.bouncy(duration: 0.2)) {
                            selection = product
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    Paywall()
}
