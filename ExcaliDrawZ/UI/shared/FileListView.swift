//
//  FileListView.swift
//  ExcaliDrawZ
//
//  Created by Dove Zachary on 2023/1/4.
//

import SwiftUI

struct FileListView: View {
    @EnvironmentObject var store: AppStore
    
    private var selectedFile: Binding<URL?> {
        store.binding(for: \.currentFile) {
            return .setCurrentFile($0)
        }
    }
    
    var body: some View {
        List(store.state.assetFiles, selection: selectedFile) { fileInfo in
            FileRowView(fileInfo: fileInfo)
        }
        .animation(.easeIn, value: store.state.assetFiles)
    }
}

struct FileListView_Previews: PreviewProvider {
    static var previews: some View {
        FileListView()
    }
}
