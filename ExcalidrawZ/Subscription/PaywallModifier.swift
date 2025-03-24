//
//  PaywallModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI

import ChocofordUI
import SwiftyAlert

struct PaywallModifier: ViewModifier {
    @EnvironmentObject private var store: Store
    
    @State private var window: NSWindow?
    
    // Don't Check everytime, check with throttle 10 minutes.
    @State private var lastUpdate: Date = .distantPast

    func body(content: Content) -> some View {
        content
            .bindWindow($window)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                if let window = notification.object as? NSWindow, window == self.window {
                    updateProductStatus()
                }
            }
            .sheet(isPresented: $store.isPaywallPresented) {
                Paywall()
                    .swiftyAlert()
            }
    }
    
    
    private func updateProductStatus() {
        DispatchQueue.main.async {
            let now = Date()

            if now.timeIntervalSince(lastUpdate) >= 60 * 10 {
                lastUpdate = now
                DispatchQueue.main.async {
                    Task {
                        await store.updateCustomerProductStatus()
                    }
                }
            }
        }
    }
}
