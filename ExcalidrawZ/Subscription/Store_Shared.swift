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
    private static var commonPlanFeatures: [String] {
        [
            String(localizable: .paywallPlanGeneralFeaturesUnlimitedDraws),
            String(localizable: .paywallPlanGeneralFeaturesICloudSync),
            String(localizable: .paywallPlanGeneralFeaturesPDFExport),
            String(localizable: .paywallPlanGeneralFeaturesLibrariesSupport),
        ]
    }

    private static func planFeatures(
        mcpFeature: String?,
        collaborationRoomsCount: String,
        aiCredits: Int? = nil
    ) -> [String] {
        var features = commonPlanFeatures
        if ExcalidrawZMCPServerController.isAvailable,
           let mcpFeature {
            features.append(mcpFeature)
        }
        features.append(
            String(
                localizable: .paywallPlanGeneralFeaturesCollaborationRoomsCount(
                    collaborationRoomsCount
                )
            )
        )
        if let aiCredits {
            features.append(String(localizable: .paywallPlanGeneralFeaturesAICredits(aiCredits)))
        }
        return features
    }

    static let free = SubscriptionItem(
        id: "free",
        yearlyID: nil,
        title: String(localizable: .paywallPlanFreeTitle),
        // 免费的计划，可以享受绝大部分的功能
        description: String(localizable: .paywallPlanFreeDescription),
        features: Self.planFeatures(
            mcpFeature: String(localizable: .paywallPlanGeneralFeaturesBasicMCPServices),
            collaborationRoomsCount: "1"
        ),
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
        description: String(localizable: .paywallPlanStarterDescription),
        features: Self.planFeatures(
            mcpFeature: String(localizable: .paywallPlanGeneralFeaturesOptimizedMCPServices),
            collaborationRoomsCount: String(localizable: .paywallPlanGeneralFeaturesUnlimitedValue)
        ),
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
        description: String(localizable: .paywallPlanProDescription),
        features: Self.planFeatures(
            mcpFeature: String(localizable: .paywallPlanGeneralFeaturesOptimizedMCPServices),
            collaborationRoomsCount: String(localizable: .paywallPlanGeneralFeaturesUnlimitedValue),
            aiCredits: 500
        ),
        fallbackDisplayPrice: "$9.99",
        fallbackDisplayPeriod: "a month",
        fallbackYearlyDisplayPrice: "$99.99",
        fallbackYearlyDisplayPeriod: "a year"
    )
    static let max = SubscriptionItem(
        id: "plan.max_3x",
        yearlyID: "plan.max_3x_yearly",
        title: "Max",
        description: String(localizable: .paywallPlanMaxDescription),
        features: Self.planFeatures(
            mcpFeature: String(localizable: .paywallPlanGeneralFeaturesOptimizedMCPServices),
            collaborationRoomsCount: String(localizable: .paywallPlanGeneralFeaturesUnlimitedValue),
            aiCredits: 1800
        ),
        fallbackDisplayPrice: "$29.99",
        fallbackDisplayPeriod: "a month",
        fallbackYearlyDisplayPrice: "$299.99",
        fallbackYearlyDisplayPeriod: "a year"
    )
    static let max10x = SubscriptionItem(
        id: "plan.max_10x",
        yearlyID: "plan.max_10x_yearly",
        title: "Max 10x",
        description: String(localizable: .paywallPlanMax10xDescription),
        features: Self.planFeatures(
            mcpFeature: String(localizable: .paywallPlanGeneralFeaturesOptimizedMCPServices),
            collaborationRoomsCount: String(localizable: .paywallPlanGeneralFeaturesUnlimitedValue),
            aiCredits: 5400
        ),
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
        activeSubscriptionItem == .max || activeSubscriptionItem == .max10x
    }

    var canUseOptimizedMCPServices: Bool {
        guard ExcalidrawZMCPServerController.isAvailable else { return false }
        guard let activeSubscriptionItem else { return false }
        return activeSubscriptionItem >= .starter
    }

    enum ReachPaywallReason {
        case manaully
        
        case roomLimit
        /// AI chat hit `LLMError.insufficientCredits`. Drives the paywall
        /// open from the chat error funnel so the user can top up without
        /// leaving the canvas.
        case aiInsufficientCredits
        case optimizedMCPServices

        var paywallMessage: String? {
            switch self {
                case .manaully:
                    nil
                case .roomLimit:
                    String(localizable: .paywallReachReasonRoomLimit)
                case .aiInsufficientCredits:
                    // TODO: add a localized key for this reason.
                    "Your AI credits have run out. Upgrade to keep chatting."
                case .optimizedMCPServices:
                    String(localizable: .paywallReachReasonOptimizedMCPServices)
            }
        }
    }

    func togglePaywall(reason: ReachPaywallReason) {
        PaywallPresentationState.shared.present(reason: reason)
    }

}
