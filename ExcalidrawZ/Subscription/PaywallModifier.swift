//
//  PaywallModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI

import SwiftyAlert

struct PaywallModifier: ViewModifier {
    @ObservedObject private var paywallPresentation = PaywallPresentationState.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $paywallPresentation.isPresented) {
                Paywall()
                    .swiftyAlert()
            }
    }
}
