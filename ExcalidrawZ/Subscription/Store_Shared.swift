//
//  Store_Shared.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import Foundation
#if APP_STORE
import StoreKit
#endif

//struct ProductInfo: Hashable, Sendable {
//#if APP_STORE
//    var product: Product
//#endif
//    var displayPrice: String
//    var subscriptionPeriod: String
//    
//#if APP_STORE
//    init(product: Product) {
//        self.product = product
//        self.displayPrice = product.displayPrice
//        self.subscriptionPeriod = product.subscriptionPeriod.formatted(product.subscriptionPeriodFormatStyle)
//    }
//#endif
//    init(displayPrice: String, subscriptionPeriod: String) {
//        self.displayPrice = displayPrice
//        self.subscriptionPeriod = subscriptionPeriod
//    }
//}

struct SubscriptionItem: Hashable, Identifiable, Comparable {
    static let free = SubscriptionItem(
        id: "free",
        yearlyID: nil,
        title: String(localizable: .paywallPlanFreeTitle),
        // 免费的计划，可以享受绝大部分的功能
        description: String(localizable: .paywallPlanFreeDescription),
        features: [
            String(localizable: .paywallPlanGeneralFeaturesUnlimitedDraws),
            String(localizable: .paywallPlanGeneralFeaturesICloudSync),
            String(localizable: .paywallPlanGeneralFeaturesPDFExport),
            String(localizable: .paywallPlanGeneralFeaturesLibrariesSupport),
            String(localizable: .paywallPlanGeneralFeaturesCollaborationRoomsCount("1")),
        ],
        fallbackDisplayPrice: "Free",
        fallbackDisplayPeriod: "Forever",
        fallbackYearlyDisplayPrice: "Free",
        fallbackYearlyDisplayPeriod: "Forever"
    )
    static let starter = SubscriptionItem(
        id: "plan.starter",
        yearlyID: "plan.starter_yearly",
        title: String(localizable: .paywallPlanStarterTitle),
        // Starter now carries the original Pro feature set.
        description: "Unlimited collaboration and all core premium features.",
        features: [
            String(localizable: .paywallPlanGeneralFeaturesUnlimitedDraws),
            String(localizable: .paywallPlanGeneralFeaturesICloudSync),
            String(localizable: .paywallPlanGeneralFeaturesPDFExport),
            String(localizable: .paywallPlanGeneralFeaturesLibrariesSupport),
            String(localizable: .paywallPlanGeneralFeaturesCollaborationRoomsCount("Unlimited")),
        ],
        fallbackDisplayPrice: "$2.99",
        fallbackDisplayPeriod: "a month",
        fallbackYearlyDisplayPrice: "$29.99",
        fallbackYearlyDisplayPeriod: "a year"
    )
    static let pro = SubscriptionItem(
        id: "plan.pro",
        yearlyID: "plan.pro_yearly",
        title: String(localizable: .paywallPlanProTitle),
        // 无限制
        description: "Everything in Starter, plus monthly AI credits for regular AI work.",
        features: [
            String(localizable: .paywallPlanGeneralFeaturesUnlimitedDraws),
            String(localizable: .paywallPlanGeneralFeaturesICloudSync),
            String(localizable: .paywallPlanGeneralFeaturesPDFExport),
            String(localizable: .paywallPlanGeneralFeaturesLibrariesSupport),
            String(localizable: .paywallPlanGeneralFeaturesCollaborationRoomsCount("Unlimited")),
            "**500 AI credits** / month",
        ],
        fallbackDisplayPrice: "$9.99",
        fallbackDisplayPeriod: "a month",
        fallbackYearlyDisplayPrice: "$99.99",
        fallbackYearlyDisplayPeriod: "a year"
    )
    static let max = SubscriptionItem(
        id: "plan.max_3x",
        yearlyID: "plan.max_3x_yearly",
        title: "Max",
        description: "For heavier AI usage and larger collaborative work.",
        features: [
            String(localizable: .paywallPlanGeneralFeaturesUnlimitedDraws),
            String(localizable: .paywallPlanGeneralFeaturesICloudSync),
            String(localizable: .paywallPlanGeneralFeaturesPDFExport),
            String(localizable: .paywallPlanGeneralFeaturesLibrariesSupport),
            String(localizable: .paywallPlanGeneralFeaturesCollaborationRoomsCount("Unlimited")),
            "**1800 AI credits** / month",
        ],
        fallbackDisplayPrice: "$29.99",
        fallbackDisplayPeriod: "a month",
        fallbackYearlyDisplayPrice: "$299.99",
        fallbackYearlyDisplayPeriod: "a year"
    )
    static let max10x = SubscriptionItem(
        id: "plan.max_10x",
        yearlyID: "plan.max_10x_yearly",
        title: "Max 10x",
        description: "For the highest AI usage tier.",
        features: [
            String(localizable: .paywallPlanGeneralFeaturesUnlimitedDraws),
            String(localizable: .paywallPlanGeneralFeaturesICloudSync),
            String(localizable: .paywallPlanGeneralFeaturesPDFExport),
            String(localizable: .paywallPlanGeneralFeaturesLibrariesSupport),
            String(localizable: .paywallPlanGeneralFeaturesCollaborationRoomsCount("Unlimited")),
            "**5400 AI credits** / month",
        ],
        fallbackDisplayPrice: "$99.99",
        fallbackDisplayPeriod: "a month",
        fallbackYearlyDisplayPrice: "$999.99",
        fallbackYearlyDisplayPeriod: "a year"
    )
    
    var id: String
    var yearlyID: String?
    var title: String
    var description: String
    var features: [String]
    
    var fallbackDisplayPrice: String
    var fallbackDisplayPeriod: String
    var fallbackYearlyDisplayPrice: String?
    var fallbackYearlyDisplayPeriod: String?

    var productIDs: [String] {
        [id, yearlyID].compactMap { $0 }
    }

    func containsProductID(_ productID: String?) -> Bool {
        guard let productID else { return false }
        return productIDs.contains(productID)
    }
    
//    // Product Info
//    var productInfo: ProductInfo?
    
    static func < (lhs: SubscriptionItem, rhs: SubscriptionItem) -> Bool {
        if lhs == rhs { return false }
        let order: [SubscriptionItem] = [.free, .starter, .pro, .max, .max10x]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

extension Store {
    @MainActor
    var canUseExtraHighAIModel: Bool {
        purchasedPlans.contains { product in
            SubscriptionItem.max.containsProductID(product.id)
                || SubscriptionItem.max10x.containsProductID(product.id)
        }
    }

    enum ReachPaywallReason {
        case manaully
        
        case roomLimit
        /// AI chat hit `LLMError.insufficientCredits`. Drives the paywall
        /// open from the chat error funnel so the user can top up without
        /// leaving the canvas.
        case aiInsufficientCredits

        var description: String {
            switch self {
                case .manaully:
                    "Try now!"
                case .roomLimit:
                    String(localizable: .paywallReachReasonRoomLimit)
                case .aiInsufficientCredits:
                    // TODO: add a localized key for this reason.
                    "Your AI credits have run out. Upgrade to keep chatting."
            }
        }
    }

    func togglePaywall(reason: ReachPaywallReason) {
        self.reachPaywallReason = reason
        self.isPaywallPresented.toggle()
    }

}
