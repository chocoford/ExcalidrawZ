//
//  FileItemsMoreActionsMenu.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/19/25.
//

import SwiftUI

struct FileItemsMoreActionsMenu: View {
    var body: some View {
        Menu {
            
        } label: {
            Label("More", systemSymbol: .ellipsis)
                .labelStyle(.iconOnly)
        }
    }
}

#Preview {
    FileItemsMoreActionsMenu()
}
