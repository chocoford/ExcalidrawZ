//
//  ContentView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI


struct ContentView: View {
    @ObservedObject var fileManager: AppFileManager = .shared
    
    @State private var currentFileURL: URL?
    @State private var isLoading = false
    
    var body: some View {
        NavigationSplitView {
            List(fileManager.assetFiles, selection: $currentFileURL) { fileInfo in
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
                }
            }
        } detail: {
            if let url = URL(string: "https://excalidraw.com") {
                GeometryReader { geometry in
                    ZStack {
                        WebView(url: url, currentFile: currentFileURL, isLoading: $isLoading)
                        if isLoading {
                            ZStack {
                                Rectangle()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .backgroundStyle(.ultraThickMaterial)
                                VStack {
                                    LoadingView(strokeColor: Color.accentColor)
                                    Text("Loading...")
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                    .animation(.default, value: isLoading)
                    .onChange(of: currentFileURL) { newValue in
                        isLoading = true
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
