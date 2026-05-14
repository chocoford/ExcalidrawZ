//
//  RegularPlansView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/2/25.
//

import SwiftUI
import StoreKit

enum MaxCreditTier: String, CaseIterable, Identifiable {
    case standard
    case triple
    
    var id: Self { self }
    
    var title: String {
        switch self {
            case .standard:
                "3x"
            case .triple:
                "10x"
        }
    }
    
    var credits: Int {
        switch self {
            case .standard:
                1800
            case .triple:
                5400
        }
    }
    
    var badgeText: String {
        "\(credits) AI"
    }
}

struct RegularPlansView: View {
    @Binding var selection: SubscriptionItem?
    @Binding var maxCreditTier: MaxCreditTier
    var billingPeriod: Paywall.BillingPeriod
    var plans: [SubscriptionItem]
    var activePlan: SubscriptionItem?
    var productProvider: (SubscriptionItem) -> Product?
    var maxCreditTierChangeHandler: (MaxCreditTier) -> Void = { _ in }
    
    var body: some View {
        planCards
    }
    
    private var planCards: some View {
        VStack(spacing: 12) {
            ForEach(plans) { item in
                PlanCard(
                    isSelected: isSelected(item),
                    plan: item,
                    product: productProvider(item),
                    billingPeriod: billingPeriod,
                    activePlan: activePlan,
                    maxCreditTier: item.id == SubscriptionItem.max.id ? $maxCreditTier : nil,
                    maxCreditTierChangeHandler: maxCreditTierChangeHandler
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.bouncy(duration: 0.2)) {
                        if item.id == SubscriptionItem.max.id, maxCreditTier == .triple {
                            selection = .max10x
                        } else {
                            selection = item
                        }
                    }
                }
            }
        }
    }
    
    private func isSelected(_ item: SubscriptionItem) -> Bool {
        if item.id == SubscriptionItem.max.id {
            return selection == .max || selection == .max10x
        }
        return item == selection
    }
}

struct PlanCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var isSelected: Bool
    
    var plan: SubscriptionItem
    var product: Product?
    var billingPeriod: Paywall.BillingPeriod
    var activePlan: SubscriptionItem?
    var maxCreditTier: Binding<MaxCreditTier>?
    var maxCreditTierChangeHandler: (MaxCreditTier) -> Void = { _ in }
    
    private var accent: Color {
        switch plan.id {
            case SubscriptionItem.starter.id:
                AIAppearancePalette.planAccent(.starter)
            case SubscriptionItem.pro.id:
                AIAppearancePalette.planAccent(.pro)
            case SubscriptionItem.max.id:
                AIAppearancePalette.planAccent(.max)
            default:
                    .accentColor
        }
    }

    private var isCurrentPlan: Bool {
        if plan.id == SubscriptionItem.max.id {
            activePlan == .max || activePlan == .max10x
        } else {
            activePlan == plan
        }
    }

    private var shouldShowRecommendedBadge: Bool {
        guard plan.id == SubscriptionItem.pro.id else { return false }
        guard let activePlan else { return true }
        return activePlan < .pro
    }

    private var badgeText: String? {
        if isCurrentPlan {
            return String(localizable: .paywallButtonCurrentPlan)
        }
        if shouldShowRecommendedBadge {
            return String(localizable: .paywallPlanRecommendedBadge)
        }
        return nil
    }
    
    var body: some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 112, alignment: .center)
            .background {
                if #available(iOS 26.0, macOS 26.0, *) {
                    let roundedRectangle = RoundedRectangle(cornerRadius: 22)
                    ZStack {
                        roundedRectangle
                            .fill(.clear)
                            .glassEffect(
                                .clear
                                    .tint(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                                    .interactive(),
                                in: roundedRectangle
                            )
                        
                        if isSelected {
                            roundedRectangle
                                .fill(
                                    accent.opacity(colorScheme == .dark ? 0.12 : 0.08)
                                )
                            roundedRectangle
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(colorScheme == .dark ? 0.55 : 0.90),
                                            accent.opacity(0.92),
                                            Color.pink.opacity(0.55)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        } else {
                            roundedRectangle
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.42), lineWidth: 0.7)
                        }
                    }
                    .compositingGroup()
                    .shadow(color: accent.opacity(isSelected ? 0.30 : 0.12), radius: isSelected ? 24 : 12, y: isSelected ? 12 : 6)
                    .animation(.easeIn(duration: 0.2), value: isSelected)
                } else {
                    let roundedRectangle = RoundedRectangle(cornerRadius: 12)
                    ZStack {
                        roundedRectangle
                            .fill(.ultraThinMaterial)
                        if isSelected {
                            roundedRectangle.stroke(.accent)
                        } else {
                            roundedRectangle.stroke(.separator)
                        }
                    }
                    .shadow(color: .accent, radius: isSelected ? 4 : 0)
                    .animation(.easeIn(duration: 0.2), value: isSelected)
                }
            }
            .scaleEffect(isSelected ? 1.015 : 1, anchor: .center)
            .overlay(alignment: .topTrailing) {
                if let maxCreditTier {
                    maxCreditTierSwitch(maxCreditTier)
                        .padding(.top, 10)
                        .padding(.trailing, 12)
                }
            }
    }
    
    
    @ViewBuilder
    private func content() -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(plan.title)
                        .font(.title3.weight(.semibold))
                    
                    if let badgeText {
                        planBadge(badgeText)
                    }
                }
                
                Text(plan.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 12)
            
            VStack(alignment: .trailing, spacing: 2) {
#if APP_STORE
                Text(displayPriceText)
                    .font(.title3.bold())
                if let periodText = displayPeriodText {
                    Text(periodText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#else
                Text(displayPriceText)
                    .font(.title3.bold())
                if let periodText = displayPeriodText {
                    Text(periodText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#endif
            }
        }
    }
    
    private var displayPriceText: String {
#if APP_STORE
        if billingPeriod == .yearly, let product {
            let monthlyPrice = NSDecimalNumber(decimal: product.price)
                .dividing(by: NSDecimalNumber(value: 12))
                .decimalValue
            return monthlyPrice.formatted(
                .currency(code: product.priceFormatStyle.currencyCode)
            ) + String(localizable: .paywallPriceMonthlyUnit)
        }
        guard let product else { return "" }
        return product.displayPrice + String(localizable: .paywallPriceMonthlyUnit)
#else
        if billingPeriod == .yearly, let monthlyPrice = fallbackMonthlyPriceFromYearlyPrice {
            return monthlyPrice + String(localizable: .paywallPriceMonthlyUnit)
        }
        return fallbackPlan.fallbackDisplayPrice + String(localizable: .paywallPriceMonthlyUnit)
#endif
    }
    
    private var displayPeriodText: String? {
        if billingPeriod == .yearly {
            return fallbackPlan.fallbackYearlyDisplayPrice == nil 
            ? String(localizable: .paywallPriceBillingPeriodMonthly)
            : String(localizable: .paywallPriceBillingPeriodYearly)
        }
        return String(localizable: .paywallPriceBillingPeriodMonthly)
    }
    
    private var fallbackMonthlyPriceFromYearlyPrice: String? {
        guard let yearlyPrice = fallbackPlan.fallbackYearlyDisplayPrice else { return nil }
        let numericString = yearlyPrice
            .filter { $0.isNumber || $0 == "." }
        guard let yearlyAmount = Decimal(string: numericString) else { return nil }
        
        let monthlyAmount = (NSDecimalNumber(decimal: yearlyAmount)
            .dividing(by: NSDecimalNumber(value: 12)))
            .decimalValue
        
        return monthlyAmount.formatted(
            .currency(code: Locale.current.currency?.identifier ?? "USD")
        )
    }
    
    private var fallbackPlan: SubscriptionItem {
        if plan.id == SubscriptionItem.max.id, maxCreditTier?.wrappedValue == .triple {
            return .max10x
        }
        return plan
    }
    
    @ViewBuilder
    private func planBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white : accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(accent.opacity(colorScheme == .dark ? 0.42 : 0.12))
            }
            .overlay {
                if colorScheme == .dark {
                    Capsule()
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.6)
                }
            }
    }
    
    @ViewBuilder
    private func maxCreditTierSwitch(_ selection: Binding<MaxCreditTier>) -> some View {
        HStack(spacing: 3) {
            ForEach(MaxCreditTier.allCases) { tier in
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        selection.wrappedValue = tier
                    }
                    maxCreditTierChangeHandler(tier)
                } label: {
                    Text(tier.title)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection.wrappedValue == tier ? Color.white : accent)
                .background {
                    if selection.wrappedValue == tier {
                        Capsule()
                            .fill(accent)
                    }
                }
            }
        }
        .padding(2)
        .background {
            Capsule()
                .fill(accent.opacity(colorScheme == .dark ? 0.14 : 0.10))
        }
    }
}
