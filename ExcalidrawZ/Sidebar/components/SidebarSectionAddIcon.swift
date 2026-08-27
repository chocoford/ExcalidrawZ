//
//  SidebarSectionAddIcon.swift
//  ExcalidrawZ
//

import SwiftUI

struct SidebarSectionAddIcon: View {
    let accessibilityLabel: Text

    var body: some View {
        Image(systemName: "plus.circle.fill")
            .font(.callout.weight(.semibold))
            .tint(.secondary)
            .frame(width: 18, height: 18)
            .accessibilityLabel(accessibilityLabel)
    }
}
