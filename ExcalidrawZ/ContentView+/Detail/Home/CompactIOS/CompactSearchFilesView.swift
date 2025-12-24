//
//  CompactSearchFilesView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/21/25.
//

import SwiftUI

struct CompactSearchFilesView: View {
    @EnvironmentObject private var layoutState: LayoutState

    
    @State private var searchText: String = ""
    
    
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
                                    file: file
                                )
                            }
                        }
                        .padding(16)
                    }
                }
                .searchable(text: $searchText)
                .navigationTitle("Search")
                .toolbar {
#if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        SettingsViewButton()
                    }
#endif
                }
            }
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
    CompactSearchFilesView()
}
