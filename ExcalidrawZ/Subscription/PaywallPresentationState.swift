//
//  PaywallPresentationState.swift
//  ExcalidrawZ
//

import SwiftUI

final class PaywallPresentationState: ObservableObject {
    static let shared = PaywallPresentationState()

    @Published var isPresented = false
    @Published var reachReason: Store.ReachPaywallReason?

    private init() {}

    func present(reason: Store.ReachPaywallReason) {
        reachReason = reason
        if !isPresented {
            isPresented = true
        }
    }
}
