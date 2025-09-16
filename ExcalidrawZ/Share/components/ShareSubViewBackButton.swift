//
//  ShareSubViewBackButton.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 9/16/25.
//

import SwiftUI

struct ShareSubViewBackButtonModifier: ViewModifier {
    var dismiss: () -> Void
    @State private var showBackButton = false

    func body(content: Content) -> some View {
        content
#if os(macOS)
            .overlay(alignment: .topLeading) {
                if showBackButton {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemSymbol: .chevronLeft)
                            .padding(4)
                    }
                    .modernButtonStyle(style: .glass, shape: .circle)
                    .transition(
                        .offset(x: -10).combined(with: .opacity)
                    )
                }
            }
            .animation(.default, value: showBackButton)
#endif // os(macOS)
            .onAppear {
                showBackButton = true
            }
            .onDisappear {
                showBackButton = false
            }
    }
}
