//
//  ToolbarCloseButton.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/7/26.
//

import SwiftUI

struct ToolbarCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Button {
            dismiss()
        } label: {
            Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
        }
    }
}
