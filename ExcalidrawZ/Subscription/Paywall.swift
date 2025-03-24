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

    var body: some View {
        content()
            .watchImmediately(of: store.purchasedPlans) { newValue in
                self.selectedPlan = newValue.first
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
            HStack {
                Text("Upgrade your plan")
                    .font(.largeTitle)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Button {
                    dismiss()
                } label: {
                    Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.text(square: true))
            }
            .overlay(alignment: .trailing) {
                Button {
                    route = .donation
                } label: {
                    HStack {
                        Text("Sponsor author")
                        Image(systemSymbol: .chevronRight2)
                    }
                    .shimmering(
                        animation: Animation.linear(duration: 1).delay(2).repeatForever(autoreverses: false)
                    )
                }
                .buttonStyle(.borderless)
            }
            .padding(.bottom, 30)
            .overlay(alignment: .bottom) {
                if let reason = store.reachPaywallReason {
                    ZStack {
                        if isPresented {
                            Text(reason.description)
                                .foregroundStyle(.red)
                                .font(.footnote)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule().fill(Color.red)
                                    Capsule().fill(.ultraThickMaterial)
                                }
                                .transition(.scale.animation(.bouncy.delay(0.2)))
                        }
                    }
                    .animation(.bouncy, value: isPresented)
                }
            }
            
            Color.clear.frame(height: 50)
            
            HStack(spacing: 20) {
                ForEach(
                    store.plans.filter({ plan in
                        if store.purchasedPlans.isEmpty { return true }
                        if let activePlan = store.plans.first(where: {$0.id == store.purchasedPlans.first?.id}) {
                            return plan >= activePlan
                        } else {
                            return false
                        }
                    })
                ) { item in
                    PlanCard(
                        isSelected: item == .free ? selectedPlan == nil : selectedPlan?.id == item.id,
                        plan: item,
                        product: store.subscriptions.first(where: {$0.id == item.id})
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.bouncy(duration: 0.2)) {
                            selectedPlan = store.subscriptions.first(where: {$0.id == item.id})
                        }
                    }
                }
            }
            
            HStack {
                Spacer()
                
                AsyncButton {
                    try await purchaseSelectedPlan()
                } label: {
                    ZStack {
                        if selectedPlan == store.purchasedPlans.first {
                            Text("Current plan")
                        } else if let selectedPlan {
                            let planName: String = store.plans.first(where: {$0.id == selectedPlan.id})?.title ?? selectedPlan.displayName
                            let period: String = selectedPlan.subscription?.subscriptionPeriod.formatted(selectedPlan.subscriptionPeriodFormatStyle) ?? ""
                            Text("Subscribe **\(planName)** with ") +
                            Text("\(selectedPlan.displayPrice) \(period)").font(.footnote)
                        } else {
                            
                        }
                    }
                    .padding(.horizontal)
                }
                .controlSize({
                    if #available(macOS 14.0, *) {
                        .extraLarge
                    } else {
                        .large
                    }
                }())
                .buttonStyle(.borderedProminent)
                .disabled(selectedPlan == store.purchasedPlans.first)
                
                Spacer()
            }
            .overlay(alignment: .trailing) {
                AsyncButton {
                    await store.updateCustomerProductStatus()
                    alert(title: "Restore purchases done") {
                            
                    }
                } label: {
                    Text("Restore purchases")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(40)
        .background {
            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .accent, location: 0),
                        .init(color: colorScheme == .dark ? .black : .white, location: 0.4),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .onAppear {
            isPresented = true
        }
        .onDisappear {
            isPresented = false
        }
    }
    
    private func purchaseSelectedPlan() async throws {
        if let product = store.subscriptions.first(where: {$0.id == selectedPlan?.id}) {
            if let _ = try await store.purchase(product) {
                dismiss()
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
                        currencyFormatter.locale = .current
                        return currencyFormatter.string(from: 0.00) ?? ""
                    }())
                    .font(.title.bold())
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
                    HStack {
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
        .frame(width: 260, height: 340, alignment: .top)
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

#Preview {
    Paywall()
}
