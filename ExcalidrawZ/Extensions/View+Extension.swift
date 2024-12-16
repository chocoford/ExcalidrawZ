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
}
