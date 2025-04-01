//
//  Store_NonAppStore.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI


class Store: ObservableObject {
    @Published var isPaywallPresented = false
    @Published var reachPaywallReason: ReachPaywallReason?
    
    var collaborationRoomLimits: Int? { 1 }
}
