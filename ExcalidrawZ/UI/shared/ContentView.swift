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
    @State private var columnVisibility: NavigationSplitViewVisibilityCompatible = .all
    @State private var hideContent: Bool = false
    
    private var hasError: Binding<Bool> {
        store.binding(for: \.hasError) {
            .setHasError($0)
        }
    }
    
    var isExportingImage: Binding<Bool> {
        Binding {
            store.state.exportingState != nil
        } set: { val in
            if !val {
                store.send(.setExportingState(nil))
            }
        }
    }
    
    var body: some View {
        content
            .alert(isPresented: hasError, error: store.state.error) {}
    }

    @ViewBuilder private var content: some View {
        navigationView
        .onAppear {
            store.send(.setCurrentGroupFromLastSelected)
        }
    }
    
    @ViewBuilder private var navigationView: some View {
        NavigationSplitViewCompatible(columnVisibility: $columnVisibility) {
            GroupSidebarView()
                .frame(minWidth: 150)
//                .toolbar {
//                    ToolbarItemGroup(placement: .primaryAction) {
//                        Button {
//                            withAnimation {
//                                switch columnVisibility {
//                                    case .all:
//                                        columnVisibility = .detailOnly
//                                    case .detailOnly:
//                                        columnVisibility = .all
//                                    default:
//                                        columnVisibility = .all
//                                }
//                            }
//                        } label: {
//                            Image(systemName: "sidebar.leading")
//                        }
//                        .help("Toggle sidebar")
//                    }
//                }
        } detail: {
            HStack(spacing: 0) {
                if columnVisibility != .detailOnly {
                    ResizableView(.horizontal, edge: .trailing, initialSize: 200, minSize: 200) {
                        FileListView(group: store.state.currentGroup)
                    }
                    .border(.trailing, color: Color(nsColor: .separatorColor))
                }
                ExcalidrawView()
                    .toolbar(content: toolbarContent)
                    .sheet(isPresented: isExportingImage) {
                        ExportImageView(isPresent: isExportingImage, exportState: store.state.exportingState)
                    }
            }
        }
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
        }

        ToolbarItemGroup(placement: .automatic) {
            Spacer()
            // create
            Button {
                store.send(.setExportingState(.init(done: false)))
                let script = """
                document.querySelector('.App-menu_top__left').querySelector('button[data-testid="dropdown-menu-button"]').click();
                setTimeout(() => {
                    document.querySelector('.App-menu_top__left').querySelector('button[data-testid="image-export-button"]').click();
                    setTimeout(() => {
                        document.querySelector('.excalidraw-modal-container').style.display = 'none';
                        document.querySelector('.excalidraw-modal-container').querySelector('button[aria-label="Export to PNG"]').click();
                    }, 5)
                }, 10);
                """
                ExcalidrawWebView.shared.evaluateJavaScript(script)
            } label: {
                Image(systemName: "camera.on.rectangle")
            }
            .help("Take a screenshot.")
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
