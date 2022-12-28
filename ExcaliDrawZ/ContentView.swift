//
//  ContentView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI


struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var fileManager: AppFileManager = .shared
    
    
    var body: some View {
        NavigationSplitView {
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
            NavigationLink(value: fileInfo.url) {
                VStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Text(fileInfo.name ?? "Untitled")
                            .layoutPriority(1)
                        Text("." + (fileInfo.fileExtension ?? ""))
                            .opacity(0.5)
                    }
                    .font(.headline)
                    .fontWeight(.medium)
                    
                    HStack {
                        Text((fileInfo.updatedAt ?? .distantPast).formatted())
                            .font(.footnote)
                        Spacer()
                        Text(fileInfo.size ?? "")
                            .font(.footnote)
                    }
                }
                .padding(.vertical)
            }
        }
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
