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
        fallbackDisplayPeriod: "Forever"
    )
    static let starter = SubscriptionItem(
        id: "plan.starter",
        title: String(localizable: .paywallPlanStarterTitle),
        // 基础计划，提供基础付费功能，收费方面也很低——$0.99，主要用来cover成本
        description: String(localizable: .paywallPlanStarterDescription),
        features: [
            String(localizable: .paywallPlanGeneralFeaturesUnlimitedDraws),
            String(localizable: .paywallPlanGeneralFeaturesICloudSync),
            String(localizable: .paywallPlanGeneralFeaturesPDFExport),
            String(localizable: .paywallPlanGeneralFeaturesLibrariesSupport),
            String(localizable: .paywallPlanGeneralFeaturesCollaborationRoomsCount("3")),
        ],
        fallbackDisplayPrice: "$0.99",
        fallbackDisplayPeriod: "a month"
    )
    static let pro = SubscriptionItem(
        id: "plan.pro",
        title: String(localizable: .paywallPlanProTitle),
        // 无限制
        description: String(localizable: .paywallPlanProDescription),
        features: [
            String(localizable: .paywallPlanGeneralFeaturesUnlimitedDraws),
            String(localizable: .paywallPlanGeneralFeaturesICloudSync),
            String(localizable: .paywallPlanGeneralFeaturesPDFExport),
            String(localizable: .paywallPlanGeneralFeaturesLibrariesSupport),
            String(localizable: .paywallPlanGeneralFeaturesCollaborationRoomsCount("Unlimited")),
        ],
        fallbackDisplayPrice: "$2.99",
        fallbackDisplayPeriod: "Forever"
    )
    
    var id: String
    var title: String
    var description: String
    var features: [String]
    
    var fallbackDisplayPrice: String
    var fallbackDisplayPeriod: String
    
//    // Product Info
//    var productInfo: ProductInfo?
    
    static func < (lhs: SubscriptionItem, rhs: SubscriptionItem) -> Bool {
        if lhs == rhs { return false }
        if lhs == .free {
            return true
        }
        if lhs == .starter {
            return rhs != .free
        }
        if lhs == .pro {
            return false
        }
        return false
    }
}

extension Store {
    enum ReachPaywallReason {
        case roomLimit
        
        var description: String {
            switch self {
                case .roomLimit:
                    String(localizable: .paywallReachReasonRoomLimit)
            }
        }
    }
    
    func togglePaywall(reason: ReachPaywallReason) {
        self.reachPaywallReason = reason
        self.isPaywallPresented.toggle()
    }
    
}
