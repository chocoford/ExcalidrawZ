//
//  View+Extension.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 12/16/24.
//

import SwiftUI

extension View {
    @MainActor @ViewBuilder
    public func modifier<V: ViewModifier>(_ modifier: V, isActive: Bool) -> some View {
        if isActive {
            self.modifier(modifier)
        } else {
            self
        }
    }
    
    @MainActor @ViewBuilder
    func sheetPadding() -> some View {
        self
            .padding(.horizontal, {
                if #available(macOS 26.0, iOS 26.0, *) {
                    26
                } else {
                    10
                }
            }())
            .padding(.vertical, {
                if #available(macOS 26.0, iOS 26.0, *) {
                    26
                } else {
                    10
                }
            }())
    }
}
