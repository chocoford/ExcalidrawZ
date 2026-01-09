//
//  ToolbarDoneButton.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/20/25.
//

import SwiftUI

struct ToolbarDoneButton: View {
    var onDone: () -> Void
    
    
    var body: some View {
        Button {
            onDone()
        } label: {
            Label(.localizable(.generalButtonDone), systemSymbol: .checkmark)
        }
        .modernButtonStyle(style: .glassProminent)
    }
}
