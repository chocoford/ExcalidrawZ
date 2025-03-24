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
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: Store
    
#if canImport(AppKit)
    @State private var window: NSWindow?
#endif
    
    // Don't Check everytime, check with throttle 10 minutes.
    @State private var lastUpdate: Date = .distantPast

    func body(content: Content) -> some View {
        content
#if canImport(AppKit)
            .bindWindow($window)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                if let window = notification.object as? NSWindow, window == self.window {
                    updateProductStatus()
                }
            }
#elseif canImport(UIKit)
            .onChange(of: scenePhase) { newValue in
                if newValue == .active {
                    updateProductStatus()
                }
            }
#endif
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
