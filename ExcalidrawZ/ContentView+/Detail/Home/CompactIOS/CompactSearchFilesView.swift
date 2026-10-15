//
//  CompactSearchFilesView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/21/25.
//

import SwiftUI

struct CompactSearchFilesView: View {
    @Binding var searchText: String
    
    var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }
    

    
    var body: some View {
        if #available(macOS 13.0, *) {
            NavigationStack {
                SearchResultsProvider(searchText: searchText) { files in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(files) { file in
                                FileHomeItemView(
                                    file: file,
                                    selectionSiblings: files
                                )
                            }
                        }
                        .padding(16)
                    }
                }
                .navigationTitle(.localizable(.compactSearchTitle))
                .toolbar {
#if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        SettingsViewButton()
                    }
#endif
                }
            }
            .searchable(text: $searchText)
        }
    }
}

struct CompactSearchFilesResultView: View {
    
    var serachText: String
    
    @State private var searchResults: [FileState.ActiveFile] = []
    
    var body: some View {
        
    }
}
#Preview {
    CompactSearchFilesView(searchText: .constant(""))
}
