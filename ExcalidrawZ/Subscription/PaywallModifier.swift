//
//  PaywallModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/20/25.
//

import SwiftUI

import SwiftyAlert

struct PaywallModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                PaywallPresenter()
                    .frame(width: 0, height: 0)
            }
    }
}

private struct PaywallPresenter: View {
    @ObservedObject private var paywallPresentation = PaywallPresentationState.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(isPresented: $paywallPresentation.isPresented) {
                Paywall()
                    .swiftyAlert()
            }
    }
}
