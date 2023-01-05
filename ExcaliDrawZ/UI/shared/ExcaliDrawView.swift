//
//  ExcaliDrawView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI

struct ExcaliDrawView: View {
    @EnvironmentObject var store: AppStore

    @State private var isLoading = true

    private var currentFile: Binding<URL?> {
        store.binding(for: \.currentFile,
                      toAction: {
            return .setCurrentFile($0)
        })
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WebView(store: store,
                        currentFile: currentFile,
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
                    store.send(.setCurrentFile(store.state.assetFiles.first?.url))
                }
            }
        }
    }
}

#if DEBUG
struct ExcaliDrawView_Previews: PreviewProvider {
    static var previews: some View {
        ExcaliDrawView()
            .environmentObject(AppStore.preview)
            .frame(width: 800, height: 600)
    }
}
#endif
