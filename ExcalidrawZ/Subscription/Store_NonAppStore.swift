//
//  Store_NonAppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI
import StoreKit


class Store: ObservableObject {
    let plans: [SubscriptionItem] = [.starter, .pro, .max, .max10x]
    
    @Published private(set) var subscriptions: [Product] = []
    @Published private(set) var memberships: [Product] = []
    
    @Published private(set) var purchasedPlans: [Product] = []
    @Published private(set) var purchasedMemberships: [Product] = []

#if DEBUG
    @Published var debugActiveSubscriptionItem: SubscriptionItem? = .pro
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
