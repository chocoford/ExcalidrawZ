//
//  PaywallPresentationState.swift
//  ExcalidrawZ
//

import SwiftUI

final class PaywallPresentationState: ObservableObject {
    static let shared = PaywallPresentationState()
    static let didPresentNotification = Notification.Name("PaywallPresentationState.didPresent")

    @Published var isPresented = false
    @Published var reachReason: Store.ReachPaywallReason?

    private init() {}

    func present(reason: Store.ReachPaywallReason) {
        reachReason = reason
        if !isPresented {
            isPresented = true
        }
        NotificationCenter.default.post(name: Self.didPresentNotification, object: nil)
    }
}
