//
//  PaywallPresentationState.swift
//  ExcalidrawZ
//

import Observation
import SwiftUI
#if os(macOS)
import AppKit
#endif

@MainActor
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
#if os(macOS)
        let controller = PaywallPanelController.shared
        controller.onDismiss = { [weak self] in self?.isPresented = false }
        controller.present(from: NSApp.keyWindow ?? NSApp.mainWindow)
#endif
        NotificationCenter.default.post(name: Self.didPresentNotification, object: nil)
    }
}
