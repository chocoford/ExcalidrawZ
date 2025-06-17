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
            // macOS always displays the content column.
            if #available(macOS 14.0, iOS 17.0, *), false {
                threeColumnNavigationSplitView()
            } else {
                twoColumnNavigationSplitView()
            }
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
    private func twoColumnNavigationSplitView() -> some View {
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
            ContentViewDetail(isSettingsPresented: $isSettingsPresented)
        }

#if os(macOS)
        .removeSettingsSidebarToggle()
#endif
    }
    
    
    @StateObject private var localFolderState = LocalFolderState()
    
    @available(macOS 14.0, iOS 17.0, *)
    @MainActor @ViewBuilder
    private func threeColumnNavigationSplitView() -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
#if os(macOS)
            GroupsSidebar()
                .frame(minWidth: 270)
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
        } content: {
            FilesSidebar()
        } detail: {
            ContentViewDetail(isSettingsPresented: $isSettingsPresented)
        }
        .environmentObject(localFolderState)
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
                
//                NewFileButton()
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
