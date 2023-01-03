//
//  ContentView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI
import Foundation


struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var fileManager: AppFileManager = .shared
    
    @State private var text = ""
    
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
//            Text(error.errorDescription ?? "")
        })
    }
    
    private var selectedGroup: Binding<URL> {
        store.binding(for: \.currentGroup) {
            return .setCurrentGroup($0)
        }
    }
    
    @ViewBuilder private var content: some View {
        NavigationSplitView {
            List(fileManager.assetGroups, selection: selectedGroup) { group in
                NavigationLink(group.name, value: group.url)
            }
            .navigationTitle("Folder")
        } content: {
            sidebarList
                .toolbar(content: toolbarContent)
        } detail: {
            ExcaliDrawView()
        }
    }

    
    private var selectedFile: Binding<URL?> {
        store.binding(for: \.currentFile) {
            return .setCurrentFile($0)
        }
    }
    
    @ViewBuilder private var sidebarList: some View {
        List(fileManager.assetFiles, selection: selectedFile) { fileInfo in
            FileRowView(fileInfo: fileInfo)
        }
        .animation(.easeIn, value: fileManager.assetFiles)
    }
}

extension ContentView {
    func createNewFile() {
        guard let file = fileManager.createNewFile() else { return }
        store.send(.setCurrentFile(file))
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
            Text(store.state.currentFile?.lastPathComponent ?? "Untitled.excalidraw")
        }
        
        ToolbarItemGroup(placement: .primaryAction) {
            Spacer()
            // import
            Button {
                let panel = ExcaliDrawOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.allowedContentTypes = [.init(filenameExtension: "excalidraw")].compactMap{ $0 }
                if panel.runModal() == .OK {
                    if let url = panel.url {
                        do {
                            let importedURL = try fileManager.importFile(from: url)
                            store.send(.setCurrentFile(importedURL))
                        } catch let error as ImportError {
                            store.send(.setError(.importError(error)))
                        } catch {
                            store.send(.setError(.importError(.unexpected(error))))
                        }
                    } else {
                        store.send(.setError(.importError(.invalidURL)))
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
