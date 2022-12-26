//
//  ContentView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2022/12/25.
//

import SwiftUI


struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List(AppFileManager.shared.assetFiles) { fileInfo in
                VStack(alignment: .leading) {
                    Text(fileInfo.name ?? "Untitled")
                        .font(.title3)
                    
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
        } detail: {
            if let url = URL(string: "https://excalidraw.com") {
                WebView(url: url)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
