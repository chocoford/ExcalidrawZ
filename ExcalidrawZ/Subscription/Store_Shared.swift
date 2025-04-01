//
//  Store_Shared.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import Foundation

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
        ]
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
        ]
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
        ]
    )
    var id: String
    var title: String
    var description: String
    var features: [String]
    
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
                    "You’ve reached the maximum number of collaborative rooms limitation in current Plan."
            }
        }
    }
    
    func togglePaywall(reason: ReachPaywallReason) {
        self.reachPaywallReason = reason
        self.isPaywallPresented.toggle()
    }
    
}
