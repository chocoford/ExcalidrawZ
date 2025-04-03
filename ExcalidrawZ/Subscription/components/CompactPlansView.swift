//
//  CompactPlansView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/2/25.
//

import SwiftUI
import StoreKit

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
