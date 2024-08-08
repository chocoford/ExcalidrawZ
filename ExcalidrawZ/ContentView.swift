//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import ChocofordUI
import ChocofordEssentials
import SwiftyAlert

struct ContentView: View {
    @State private var appPreference = AppPreference()
    @State private var hideContent: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    
    @StateObject private var fileState = FileState()
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .toolbar(content: navigationToolbar)
        } detail: {
            ExcalidrawContainerView()
        }
        .navigationTitle("")
        .toolbar { toolbarContent() }
        .environment(appPreference)
        .environmentObject(fileState)
        .swiftyAlert()
    }
}

extension ContentView {
    func createNewFile() {
//        self.store.send(.sidebar(.file(.createNewFile)))
    }
}

// MARK: - Toolbar Content
extension ContentView {
    @ToolbarContentBuilder
    private func toolbarContent() -> some ToolbarContent {
#if os(iOS)
        toolbarContent_iOS()
#else
        toolbarContent_macOS()
#endif
    }
    
#if os(iOS)
    @ToolbarContentBuilder
    private func toolbarContent_iOS() -> some ToolbarContent {
        
    }
#else
    @ToolbarContentBuilder
    private func toolbarContent_macOS() -> some ToolbarContent {
        ToolbarItemGroup(placement: .status) {
//            Text(configuration.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
//                .frame(width: 200)
        }
        
        ToolbarItemGroup(placement: .navigation) {
            // create
            Button {
                createNewFile()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New draw")
//            .disabled(viewStore.sidebar.currentGroup?.groupType == .trash)
        }

        ToolbarItemGroup(placement: .automatic) {
            Spacer()
            
            Popover {
                FileCheckpointListView()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
//            .disabled(viewStore.sidebar.currentGroup?.groupType == .trash)
            
            Button {
//                self.store.send(.shareButtonTapped)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Share")
//            .disabled(viewStore.sidebar.currentGroup?.groupType == .trash)
            

        }
    }
#endif
    
    @ToolbarContentBuilder
    private func navigationToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            HStack(spacing: 0) {
                if #available(macOS 15.0, *) {
                    // Do not show the toggle..
                    Menu {
                        Button {
                            withAnimation { columnVisibility = .all }
                            appPreference.sidebarMode = .all
                        } label: {
                            if appPreference.sidebarMode == .all && columnVisibility != .detailOnly {
                                Image(systemSymbol: .checkmark)
                            }
                            Text("Show folders and files")
                        }
                        Button {
                            withAnimation { columnVisibility = .all }
                            appPreference.sidebarMode = .filesOnly
                        } label: {
                            if appPreference.sidebarMode == .filesOnly && columnVisibility != .detailOnly {
                                Image(systemSymbol: .checkmark)
                            }
                            Text("Show files only")
                        }
                    } label: { }
                        .buttonStyle(.borderless)
                        .offset(x: -6)
                } else {
                    Button {
                        withAnimation {
                            if columnVisibility == .detailOnly {
                                columnVisibility = .all
                            } else {
                                columnVisibility = .detailOnly
                            }
                        }
                    } label: {
                        Image(systemSymbol: .sidebarLeading)
                    }
                    
                    Menu {
                        Button {
                            withAnimation { columnVisibility = .all }
                            appPreference.sidebarMode = .all
                        } label: {
                            if appPreference.sidebarMode == .all && columnVisibility != .detailOnly {
                                Image(systemSymbol: .checkmark)
                            }
                            Text("Show folders and files")
                        }
                        Button {
                            withAnimation { columnVisibility = .all }
                            appPreference.sidebarMode = .filesOnly
                        } label: {
                            if appPreference.sidebarMode == .filesOnly && columnVisibility != .detailOnly {
                                Image(systemSymbol: .checkmark)
                            }
                            Text("Show files only")
                        }
                    } label: {
                    }
                    .buttonStyle(.borderless)
                }
                
            }
        }
    }
}


#if DEBUG
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}
#endif
