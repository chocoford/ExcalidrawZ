//
//  FileCheckpointListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
import ChocofordEssentials

struct FileCheckpointListView: View {
    @FetchRequest(sortDescriptors: [SortDescriptor(\.updatedAt, order: .reverse)])
    var fileCheckpoints: FetchedResults<FileCheckpoint>
    
    var body: some View {
        List {
            ForEach(fileCheckpoints) {
                FileCheckpointRowView(checkpoint: $0)
            }
        }
        .listStyle(.plain)
    }
}


#if DEBUG
//#Preview {
//    FileCheckpointListView(store: .init(initialState: .init()) {
//        FileCheckpointListStore()
//    })
//}
#endif
