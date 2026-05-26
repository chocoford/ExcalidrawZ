//
//  StoreKitEntitlementRefreshModifier.swift
//  ExcalidrawZ
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

import ChocofordUI

struct StoreKitEntitlementRefreshModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: Store

#if canImport(AppKit)
    @State private var window: NSWindow?
#endif

    func body(content: Content) -> some View {
        content
#if APP_STORE
#if canImport(AppKit)
            .bindWindow($window)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refresh(reason: .appBecameActive)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow, window == self.window else { return }
                refresh(reason: .windowBecameKey)
            }
#else
            .onChange(of: scenePhase) { newValue in
                if newValue == .active {
                    refresh(reason: .appBecameActive)
                }
            }
#endif
            .onReceive(NotificationCenter.default.publisher(for: PaywallPresentationState.didPresentNotification)) { _ in
                refresh(reason: .paywallPresented, force: true)
            }
#endif
    }

#if APP_STORE
    private func refresh(
        reason: StoreKitEntitlementRefreshReason,
        force: Bool = false
    ) {
        Task {
            await store.refreshEntitlements(reason: reason, force: force)
        }
    }
#endif
}
