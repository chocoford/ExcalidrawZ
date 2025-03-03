//
//  SidebarToggle.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/3/25.
//

import SwiftUI

import ChocofordUI

@available(macOS 13.0, *)
struct SidebarToggle: View {
    @EnvironmentObject var appPreference: AppPreference
    
    @Binding var columnVisibility: NavigationSplitViewVisibility
    
    init(columnVisibility: Binding<NavigationSplitViewVisibility>) {
        self._columnVisibility = columnVisibility
    }
    
    var body: some View {
        Menu {
            Picker(selection: $appPreference.sidebarMode) {
                Text(.localizable(.sidebarShowAll)).tag(AppPreference.SidebarMode.all)
                Text(.localizable(.sidebarShowFilesOnly)).tag(AppPreference.SidebarMode.filesOnly)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            Label("Toggle sidebar", systemSymbol: .sidebarLeading)
        } primaryAction: {
            toggleSidebar()
        }
        .buttonStyle(.borderless)
        .onChange(of: appPreference.sidebarMode) { _ in
            withAnimation { columnVisibility = .all }
        }
    }
    
    private func toggleSidebar() {
        withAnimation {
            if columnVisibility == .detailOnly {
                columnVisibility = .all
            } else {
                columnVisibility = .detailOnly
            }
        }
    }
}

#Preview {
    if #available(macOS 13.0, *) {
        SidebarToggle(columnVisibility: .constant(.all))
            .environmentObject(AppPreference())
    }
}
