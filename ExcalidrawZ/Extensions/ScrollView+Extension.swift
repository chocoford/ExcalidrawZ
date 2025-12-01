//
//  ScrollView+Extension.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 8/30/25.
//

import SwiftUI

extension View {
    @ViewBuilder
    public func scrollClipDisabledIfAvailable(_ isDisabled: Bool = true) -> some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            self.scrollClipDisabled(isDisabled)
        } else {
            self
        }
    }
}
