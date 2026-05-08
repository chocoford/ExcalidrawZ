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
        //        if #available(iOS 26.0, macOS 26.0, *) {
        //            GlassEffectContainer(spacing: 32) {
        //                planCards
        //            }
        //        } else {
        planCards
        //        }
    }
    
    private var planCards: some View {
        HStack(spacing: 20) {
            ForEach(plans) { item in
                PlanCard(
                    isSelected: item.containsProductID(selection?.id),
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
    @Environment(\.colorScheme) private var colorScheme
    
    var isSelected: Bool
    
    var plan: SubscriptionItem
    var product: Product?
    
    private var accent: Color {
        switch plan.id {
            case SubscriptionItem.starter.id:
                Color(hue: 0.55, saturation: 1, brightness: 0.8)
            case SubscriptionItem.pro.id:
                Color(hue: 0.64, saturation: 1, brightness: 0.8)
            case SubscriptionItem.max.id:
                Color(hue: 0.86, saturation: 1, brightness: 0.8)
            default:
                    .accentColor
        }
    }
    
    var body: some View {
        content()
            .padding()
            .frame(width: 260, height: 380, alignment: .top)
            .background {
                if #available(iOS 26.0, macOS 26.0, *) {
                    let roundedRectangle = RoundedRectangle(cornerRadius: 24)
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
            .scaleEffect(isSelected ? 1.03 : 1, anchor: .bottom)
    }
    
    
    @ViewBuilder
    private func content() -> some View {
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
                Spacer()
            }
            .frame(height: 30)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plan.features, id: \.self) { feature in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemSymbol: .checkmark)
                            .symbolVariant(.circle)
                            .foregroundStyle(accent)
                        Text(try! AttributedString(markdown: feature))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
