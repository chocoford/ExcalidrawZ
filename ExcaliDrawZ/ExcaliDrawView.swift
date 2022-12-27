//
//  ExcaliDrawView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/27.
//

import SwiftUI

struct ExcaliDrawView: View {
    @ObservedObject var fileManager: AppFileManager = .shared

    @Binding var currentFileURL: URL?
    @State private var isLoading = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WebView(currentFile: $currentFileURL, isLoading: $isLoading)
                
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
                    currentFileURL = fileManager.assetFiles.first?.url
                }
            }
        }
    }
}

struct ExcaliDrawView_Previews: PreviewProvider {
    static var previews: some View {
        ExcaliDrawView(currentFileURL: .constant(nil))
    }
}
