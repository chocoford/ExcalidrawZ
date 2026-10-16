//
//  PaywallPresentationState.swift
//  ExcalidrawZ
//

import Observation
import SwiftUI

@Observable
final class PaywallPresentationState {
    static let shared = PaywallPresentationState()
    static let didPresentNotification = Notification.Name("PaywallPresentationState.didPresent")

    var isPresented = false
    var reachReason: Store.ReachPaywallReason?

    private init() {}

    func present(reason: Store.ReachPaywallReason) {
        reachReason = reason
        if !isPresented {
            isPresented = true
        }
        NotificationCenter.default.post(name: Self.didPresentNotification, object: nil)
    }
}
