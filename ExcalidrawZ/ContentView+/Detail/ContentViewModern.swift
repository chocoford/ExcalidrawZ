//
//  ContentViewModern.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 4/1/25.
//

import SwiftUI

@available(macOS 13.0, *)
struct ContentViewModern: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.alertToast) var alertToast
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var appPreference: AppPreference
    @EnvironmentObject var layoutState: LayoutState
        
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var isSettingsPresented = false
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if #available(macOS 14.0, iOS 17.0, *) {
#if os(macOS)
                SidebarView()
                    .toolbar(content: sidebarToolbar)
                    .toolbar(removing: .sidebarToggle)
#elseif os(iOS)
                if horizontalSizeClass == .compact {
                    SidebarView()
                        .toolbar(content: sidebarToolbar)
                        .toolbar(removing: .sidebarToggle)
                } else {
                    SidebarView()
                        .toolbar(content: sidebarToolbar)
                }
#endif
            } else {
                SidebarView()
                    .toolbar(content: sidebarToolbar)
            }
        } detail: {
            ContentViewDetail()
        }
#if os(macOS)
        .removeSettingsSidebarToggle()
#elseif os(iOS)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
#endif
        .onChange(of: columnVisibility) { newValue in
            layoutState.isSidebarPresented = newValue != .detailOnly
        }
    }
    
    @ToolbarContentBuilder
    private func sidebarToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // create
            NewFileButton()
        }
        
#if os(macOS)
        // in macOS 14.*, the horizontalSizeClass is not `.regular`
        // if horizontalSizeClass == .regular {
            ToolbarItemGroup(placement: .destructiveAction) {
                SidebarToggle(columnVisibility: $columnVisibility)
            }
        // }
#elseif os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                isSettingsPresented.toggle()
            } label: {
                Label(.localizable(.settingsName), systemSymbol: .gear)
            }
        }
#endif
//        ToolbarItemGroup(placement: .confirmationAction) {
//            Color.blue.frame(width: 10, height: 10)
//        }
//        ToolbarItemGroup(placement: .status) {
//            Color.yellow.frame(width: 10, height: 10)
//        }
//        ToolbarItemGroup(placement: .principal) {
//            Color.green.frame(width: 10, height: 10)
//        }
//
//        ToolbarItemGroup(placement: .cancellationAction) {
//            Color.red.frame(width: 10, height: 10)
//        }
//
#if os(macOS)
        /// It is neccessary for macOS to `space-between` the new button and sidebar toggle.
        ToolbarItemGroup(placement: .secondaryAction) {
            Color.clear
        }
#endif
    }
}
