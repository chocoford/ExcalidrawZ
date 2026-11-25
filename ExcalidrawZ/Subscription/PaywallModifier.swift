//
//  PaywallModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI

import SwiftyAlert
#if os(macOS)
import AppKit
import CoreData
import LLMKit
import ChocofordUI
#endif

struct PaywallModifier: ViewModifier {
#if os(macOS)
    @Environment(Store.self) private var store
    @Environment(AppPreference.self) private var appPreference
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var llmState: LLMStateObject
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .bindWindow($window)
            .watch(value: window?.windowNumber, initial: true) { _ in registerHost() }
            .watch(value: ObjectIdentifier(llmState)) { _ in registerHost() }
            .onDisappear {
                if let window { PaywallPanelController.shared.unregister(window: window) }
            }
    }

    private func registerHost() {
        guard let window else { return }
        let store = store
        let appPreference = appPreference
        let viewContext = viewContext
        let llmState = llmState
        PaywallPanelController.shared.register(window: window) { actions in
            AnyView(PaywallPanelContent(
                store: store,
                appPreference: appPreference,
                viewContext: viewContext,
                llmState: llmState,
                actions: actions
            ))
        }
    }
#else
    @Bindable private var paywallPresentation = PaywallPresentationState.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $paywallPresentation.isPresented) {
                Paywall()
                    .swiftyAlert()
            }
    }
#endif
}

#if os(macOS)
private struct PaywallPanelContent: View {
    let store: Store
    let appPreference: AppPreference
    let viewContext: NSManagedObjectContext
    let llmState: LLMStateObject
    let actions: PaywallPanelController.Actions

    var body: some View {
        Paywall(onDismiss: actions.dismiss, onInteractionChanged: actions.updateProtection)
            .environment(store)
            .environment(appPreference)
            .environment(\.managedObjectContext, viewContext)
            .environmentObject(llmState)
            .preferredColorScheme(appPreference.appearance.colorScheme)
            .containerSizeClassInjection()
            .swiftyAlert()
#if APP_STORE
            .onAppear {
                Task { @MainActor in
                    await store.refreshEntitlements(reason: .paywallPresented, force: true)
                }
            }
#endif
    }
}
#endif
