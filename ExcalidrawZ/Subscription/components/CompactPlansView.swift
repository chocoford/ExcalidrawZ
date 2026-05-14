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
    
    @Binding var selection: SubscriptionItem?
    var plans: [SubscriptionItem]
    
    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                let plan: SubscriptionItem = selection ?? .starter
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
            
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: 14) {
                    planButtons
                }
            } else {
                planButtons
            }
        }
    }

    private var planButtons: some View {
        HStack(spacing: 10) {
            ForEach(plans) { plan in
                let product: Product? = store.subscriptions.first(where: {$0.id == plan.id})
                let isSelected = selection == plan
                let accent = accentColor(for: plan)

                VStack {
                    Text(plan.title)
                    
#if APP_STORE
                    Text(product?.displayPrice ?? "")
                        .font(.headline)
                    if let product, let subscription = product.subscription {
                        Text(subscription.subscriptionPeriod.formatted(product.subscriptionPeriodFormatStyle))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
#else
                    Text(plan.fallbackDisplayPrice)
                        .font(.headline)
                    Text(plan.fallbackDisplayPeriod)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
#endif
                }
                .frame(width: 100, height: 100)
                .background {
                    let roundedRectangle = RoundedRectangle(cornerRadius: 14)
                    if #available(iOS 26.0, macOS 26.0, *) {
                        ZStack {
                            roundedRectangle
                                .fill(.background)
                                .opacity(0.08)
                            roundedRectangle
                                .glassEffect(
                                    .regular
                                        .tint(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                                        .interactive(),
                                    in: roundedRectangle
                                )

                            if isSelected {
                                roundedRectangle
                                    .fill(accent.opacity(colorScheme == .dark ? 0.13 : 0.08))
                                roundedRectangle
                                    .stroke(accent.opacity(0.95), lineWidth: 1.2)
                            } else {
                                roundedRectangle
                                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.42), lineWidth: 0.6)
                            }
                        }
                        .shadow(color: accent.opacity(isSelected ? 0.26 : 0.10), radius: isSelected ? 16 : 8, y: isSelected ? 8 : 4)
                    } else {
                        ZStack {
                            if colorScheme == .light {
                                roundedRectangle
                                    .fill(.white)
                            } else {
                                roundedRectangle
                                    .fill(.ultraThickMaterial)
                            }
                            if isSelected {
                                roundedRectangle
                                    .stroke(Color.accentColor)
                            }
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.bouncy(duration: 0.2)) {
                        selection = plan
                    }
                }
            }
        }
    }

    private func accentColor(for plan: SubscriptionItem) -> Color {
        switch plan.id {
        case SubscriptionItem.starter.id:
            Color(hue: 0.55, saturation: 0.30, brightness: 1.0)
        case SubscriptionItem.pro.id:
            Color(hue: 0.64, saturation: 0.28, brightness: 1.0)
        case SubscriptionItem.max.id:
            Color(hue: 0.86, saturation: 0.30, brightness: 1.0)
        default:
            .accentColor
        }
    }
}
