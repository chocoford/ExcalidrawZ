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
        ZStack {
            content()
        }
        .onChange(of: columnVisibility) { newValue in
            layoutState.isSidebarPresented = newValue != .detailOnly
        }
        .onChange(of: layoutState.isSidebarPresented) { newValue in
            if newValue {
                withAnimation {
                    columnVisibility = .all
                }
            } else {
                withAnimation {
                    columnVisibility = .detailOnly
                }
            }
        }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            if #available(macOS 14.0, iOS 17.0, *) {
#if os(macOS)
                SidebarView()
                     .toolbar(content: sidebarToolbar)
#elseif os(iOS)
                if horizontalSizeClass == .compact {
                    SidebarView()
                        .toolbar(content: sidebarToolbar)
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
            ContentViewDetail(isSettingsPresented: $isSettingsPresented)
        }
    }
    
    @ToolbarContentBuilder
    private func sidebarToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // create
            NewFileButton(openWithDelay: false)
        }
        
#if os(macOS)
        // in macOS 14.*, the horizontalSizeClass is not `.regular`
        // if horizontalSizeClass == .regular {
//            ToolbarItemGroup(placement: .destructiveAction) {
//                SidebarToggle(columnVisibility: $columnVisibility)
                
//                NewFileButton()
//            }
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
        /// In the latest macOS 26.0, this is not needed anymore. Otherwise, there will be a blank background.
        ToolbarItemGroup(placement: .secondaryAction) {
            if #available(macOS 26.0, iOS 26.0, *) { } else {
                Color.clear
            }
        }
#endif
    }
}
