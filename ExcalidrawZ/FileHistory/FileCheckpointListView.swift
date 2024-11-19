//
//  FileCheckpointListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
import ChocofordEssentials

struct FileHistoryModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var fileState: FileState
    @Binding var isPresented: Bool
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    func body(content: Content) -> some View {
        content
#if os(macOS)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                if let file = fileState.currentFile {
                    FileCheckpointListView(file: file)
                }
            }
#elseif os(iOS)
            .sheet(isPresented: $isPresented) {
                if let file = fileState.currentFile {
                    if #available(macOS 13.3, iOS 16.4, *), horizontalSizeClass == .regular {
                        FileCheckpointListView(file: file)
                            .presentationCompactAdaptation(.popover)
                    } else {
                        FileCheckpointListView(file: file)
                    }
                }
            }
#endif
    }
}

struct FileCheckpointListView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
    
    @State private var selection: FileCheckpoint?
    
    var body: some View {
        if horizontalSizeClass == .compact {
#if os(iOS)
            NavigationStack {
                List(selection: $selection) {
                    ForEach(fileCheckpoints) { checkpoint in
                        FileCheckpointRowView(checkpoint: checkpoint)
                    }
                }
                .navigationTitle("File history")
            }
#else
            List {
                ForEach(fileCheckpoints) { checkpoint in
                    FileCheckpointRowView(checkpoint: checkpoint)
                }
            }
#endif
        } else {
            List {
                ForEach(fileCheckpoints) { checkpoint in
                    FileCheckpointRowView(checkpoint: checkpoint)
                }
            }
        }
    }
    
//    @MainActor @ViewBuilder
//    private func content() -> some View {
//       
//    }
}


#if DEBUG
//#Preview {
//    FileCheckpointListView(store: .init(initialState: .init()) {
//        FileCheckpointListStore()
//    })
//}
#endif
