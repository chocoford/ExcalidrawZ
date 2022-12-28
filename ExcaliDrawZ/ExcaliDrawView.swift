//
//  ExcaliDrawView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI

struct ExcaliDrawView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var fileManager: AppFileManager = .shared

    @State private var isLoading = true

    var currentFile: URL? {
        store.state.currentFile
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
//                store.binding(for: \.currentFile,
//                                                   toAction: { .setCurrentFile($0) })
                WebView(currentFile: .constant(store.state.currentFile),
                        loading: $isLoading)
                
                if isLoading {
                    ZStack {
                        Rectangle()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .background(.background)
                        VStack {
                            LoadingView(strokeColor: Color.accentColor)
                            Text("Loading...")
                        }
                    }
                }
            }
            .transition(.opacity)
            .animation(.default, value: isLoading)
            .onChange(of: isLoading) { newValue in
                if !newValue {
                    Task {
                        await store.send(.setCurrentFile(fileManager.assetFiles.first?.url))
                    }
                }
            }
        }
    }
}

struct ExcaliDrawView_Previews: PreviewProvider {
    static var previews: some View {
        ExcaliDrawView()
    }
}
