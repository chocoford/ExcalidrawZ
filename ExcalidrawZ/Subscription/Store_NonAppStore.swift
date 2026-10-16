//
//  Store_NonAppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import Observation
import SwiftUI
import StoreKit


@Observable
class Store {
    let plans: [SubscriptionItem] = [.starter, .pro, .max, .max10x]
    
    private(set) var subscriptions: [Product] = []
    private(set) var memberships: [Product] = []
    
    private(set) var purchasedPlans: [Product] = []
    private(set) var purchasedMemberships: [Product] = []

#if DEBUG
    var debugActiveSubscriptionItem: SubscriptionItem? = .pro
#endif

    var activeSubscriptionItem: SubscriptionItem? {
#if DEBUG
        debugActiveSubscriptionItem
#else
        nil
#endif
    }
    
    var collaborationRoomLimits: Int? { 1 }
}
