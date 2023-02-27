//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import Foundation
import ChocofordUI
import Introspect

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var hideContent: Bool = false
    
    private var hasError: Binding<Bool> {
        store.binding(for: \.hasError) {
            .setHasError($0)
        }
    }
    
    var body: some View {
        content
            .alert(isPresented: hasError, error: store.state.error) {}
    }

    
    @ViewBuilder private var content: some View {
        navigationView
        .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 300)
        .navigationSplitViewStyle(.automatic)
        .toolbar(content: toolbarContent)
        .onAppear {
            store.send(.setCurrentGroupFromLastSelected)
        }
    }
    
    @ViewBuilder private var navigationView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            GroupSidebarView()
                .frame(minWidth: 150)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            withAnimation {
                                switch columnVisibility {
                                    case .all:
                                        columnVisibility = .detailOnly
                                    case .detailOnly:
                                        columnVisibility = .all
                                    default:
                                        columnVisibility = .all
                                }
                            }
                        } label: {
                            Image(systemName: "sidebar.leading")
                        }
                        .help("Toggle sidebar")
                    }
                }
            
        } detail: {
            HStack(spacing: 0) {
                if columnVisibility != .detailOnly {
                    ResizableView(.horizontal, edge: .trailing, initialSize: 200, minSize: 200) {
                        FileListView(group: store.state.currentGroup)
//                            .visualEffect(material: .sidebar, blendingMode: .withinWindow)
                    }
                    .border(.trailing, color: Color(nsColor: .separatorColor))
                }
                ExcalidrawView()
            }
        }
        .removeSidebarToggle()
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
        .navigationTitle("")
    }
}

extension ContentView {
    func createNewFile() {
        store.send(.newFile())
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
            Text(store.state.currentFile?.name ?? "Untitled")
                .frame(width: 200)
        }
        
        ToolbarItemGroup(placement: .navigation) {
            // create
            Button {
                createNewFile()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New draw")

            Button {
                let panel = ExcalidrawOpenPanel.importPanel
                if panel.runModal() == .OK {
                    if let url = panel.url {
                        store.send(.importFile(url))
                    } else {
                        store.send(.setError(.fileError(.invalidURL)))
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Import files")
        }
    }
#endif
}

fileprivate extension NavigationSplitView {
    @ViewBuilder func removeSidebarToggle() -> some View {
        introspectSplitView(customize: { splitView in
            let toolbar = splitView.window?.toolbar
            let toolbarItems = toolbar?.items
//            let identifiers = toolbarItems?.map { $0.itemIdentifier }
//            print(identifiers)
            // "com.apple.SwiftUI.navigationSplitView.toggleSidebar"
            if let index = toolbarItems?.firstIndex(where: { $0.itemIdentifier.rawValue == "com.apple.SwiftUI.navigationSplitView.toggleSidebar" }) {
                toolbar?.removeItem(at: index)
            }
        })
    }
}



#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore.preview)
            .frame(minWidth: 800, minHeight: 600)
    }
}
#endif
