//
//  SidebarToggle.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

import ChocofordUI

struct SidebarToggle: View {
    @EnvironmentObject private var layoutState: LayoutState
    
    init() {}
    
    var body: some View {
        Button {
            layoutState.isSidebarPresented.toggle()
        } label: {
            Label(.localizable(.sidebarToggleName), systemSymbol: .sidebarLeft)
        }
    }
}

