//
//  ContentView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import Foundation


struct ContentView: View {
    @EnvironmentObject var store: AppStore
//    @AppStorage("columnVisibility") var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var hideContent: Bool = false
    
    private var hasError: Binding<Bool> {
        store.binding(for: \.hasError) {
            .setHasError($0)
        }
    }
    
    var body: some View {
        content
        .alert(isPresented: hasError,
               error: store.state.error,
               actions: { error in
            
        }, message: { error in
            
        })
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
        } content: {
            FileListView(group: store.state.currentGroup)
        } detail: {
            ExcalidrawView()
        }
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
//        ToolbarItemGroup(placement: .navigation) {
//            Button {
//                hideContent.toggle()
//            } label: {
//                Image(systemName: "sidebar.left")
//            }
//        }
        
        ToolbarItemGroup(placement: .status) {
            Text(store.state.currentFile?.name ?? "Untitled")
        }
        
        ToolbarItemGroup(placement: .primaryAction) {
            Spacer()
            // import
            Button {
                let panel = ExcalidrawOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.allowedContentTypes = [.init(filenameExtension: "excalidraw")].compactMap{ $0 }
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
            
            // create
            Button {
                createNewFile()
            } label: {
                Image(systemName: "square.and.pencil")
            }
        }
    }
#endif
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
