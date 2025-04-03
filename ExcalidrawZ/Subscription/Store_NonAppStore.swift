//
//  Store_NonAppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI
import StoreKit


class Store: ObservableObject {
    let plans: [SubscriptionItem] = [.free, .starter, .pro]
    
    @Published private(set) var subscriptions: [Product] = []
    @Published private(set) var memberships: [Product] = []
    
    @Published private(set) var purchasedPlans: [Product] = []
    @Published private(set) var purchasedMemberships: [Product] = []
    
    @Published var isPaywallPresented = false
    @Published var reachPaywallReason: ReachPaywallReason?
    
    var collaborationRoomLimits: Int? { 1 }
}
