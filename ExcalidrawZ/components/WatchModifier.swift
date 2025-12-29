//
//  WatchModifier.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/25/25.
//

import SwiftUI

struct WatchModifier<T: Equatable>: ViewModifier {
    @State private var oldValue: T?
    
    var value: T
    var initial: Bool
    var action: (T, T) -> Void
    
    func body(content: Content) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            content
                .onChange(of: value, initial: initial) { oldValue, newValue in
                    action(oldValue, newValue)
                }
        } else {
            content
                .onChange(of: value) { newValue in
                    action(oldValue ?? newValue, newValue)
                }
                .onAppear {
                    oldValue = value
                    
                    if initial {
                        action(value, value)
                    }
                }
        }
    }
}

extension View {
    @ViewBuilder
    func watch<V>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (V, V) -> Void
    ) -> some View where V : Equatable {
        modifier(WatchModifier(value: value, initial: initial, action: action))
    }
}
