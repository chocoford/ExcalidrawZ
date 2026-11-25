//
//  SidebarToggle.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

import ChocofordUI

struct SidebarToggle: View {
    @Environment(LayoutState.self) private var layoutState
    
    init() {}
    
    var body: some View {
        Button {
            layoutState.isSidebarPresented.toggle()
        } label: {
            Label(.localizable(.sidebarToggleName), systemSymbol: .sidebarLeft)
        }
    }
}

