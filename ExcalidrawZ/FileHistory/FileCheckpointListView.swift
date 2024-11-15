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
    @FetchRequest
    var fileCheckpoints: FetchedResults<FileCheckpoint>
    
//    @Binding var selection: FileCheckpoint?
    
    init(file: File/*, selection: Binding<FileCheckpoint?>*/) {
        self._fileCheckpoints = FetchRequest(
            sortDescriptors: [SortDescriptor(\.updatedAt, order: .reverse)],
            predicate: NSPredicate(format: "file == %@", file)
        )
//        self._selection = selection
    }
    
    var body: some View {
        List {
            ForEach(fileCheckpoints) { checkpoint in
                FileCheckpointRowView(checkpoint: checkpoint)
//                    .onTapGesture {
//                        selection = checkpoint
//                    }
            }
        }
    }
}


#if DEBUG
//#Preview {
//    FileCheckpointListView(store: .init(initialState: .init()) {
//        FileCheckpointListStore()
//    })
//}
#endif
