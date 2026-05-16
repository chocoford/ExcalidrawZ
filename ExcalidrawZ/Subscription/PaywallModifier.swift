//
//  PaywallModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI

import SwiftyAlert

struct PaywallModifier: ViewModifier {
    @EnvironmentObject private var store: Store

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $store.isPaywallPresented) {
                Paywall()
                    .swiftyAlert()
            }
    }
}
