//
//  ToolbarDismissButton.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/20/25.
//

import SwiftUI
import SFSafeSymbols

struct ToolbarDismissButton: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Button {
            dismiss()
        } label: {
            Label(.localizable(.generalButtonClose), systemSymbol: .xmark)
        }
    }
}

#Preview {
    ToolbarDismissButton()
}
