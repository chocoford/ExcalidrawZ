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
    
    @EnvironmentObject private var store: Store

    @State private var selection: SubscriptionItem = .free
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
            .watch(value: store.purchasedPlans) { newValue in
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
                .overlay(alignment: .leading) {
                    privacyPolicyButton()
                }
#if APP_STORE
                .overlay(alignment: .trailing) {
                    restorePurchasesButton()
                }
#endif
            } else {
                VStack {
                    purchaseButton()
                    HStack {
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
    
#if APP_STORE
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
    
    private func purchaseSelectedPlan() async throws {
        if let product = store.subscriptions.first(where: {$0.id == selectedPlan?.id}) {
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
}


#Preview {
    Paywall()
}

