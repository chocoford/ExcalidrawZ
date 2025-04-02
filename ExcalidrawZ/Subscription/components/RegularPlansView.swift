//
//  RegularPlansView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/2/25.
//

import SwiftUI
import StoreKit

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
#if APP_STORE
                    Text(product?.displayPrice ?? "")
                        .font(.title.bold())
                    if let product, let subscription = product.subscription {
                        Text(subscription.subscriptionPeriod.formatted(product.subscriptionPeriodFormatStyle))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
#else
                    Text(plan.fallbackDisplayPrice)
                        .font(.title.bold())
                    Text(plan.fallbackDisplayPeriod)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
#endif
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
