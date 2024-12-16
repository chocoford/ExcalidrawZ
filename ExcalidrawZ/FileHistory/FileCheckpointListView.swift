//
//  FileCheckpointListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
import ChocofordEssentials

struct FileHistoryButton: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject var fileState: FileState
    
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(.localizable(.checkpoints), systemSymbol: .clockArrowCirclepath)
        }
        .disabled(fileState.currentGroup?.groupType == .trash)
        .help(.localizable(.checkpoints))
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
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass
    @Environment(\.dismiss) private var dismiss

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
//        if containerHorizontalSizeClass == .compact {
#if os(iOS)
            NavigationStack {
                List(selection: $selection) {
                    ForEach(fileCheckpoints) { checkpoint in
                        FileCheckpointRowView(checkpoint: checkpoint)
                    }
                }
                .navigationTitle("File history")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if containerVerticalSizeClass == .compact {
                            Button {
                                dismiss()
                            } label: {
                                Label(.localizable(.generalButtonClose), systemSymbol: .chevronDown)
                            }
                        }
                    }
                }
            }
#else
            List {
                ForEach(fileCheckpoints) { checkpoint in
                    FileCheckpointRowView(checkpoint: checkpoint)
                }
            }
#endif
//        } else {
//            List {
//                ForEach(fileCheckpoints) { checkpoint in
//                    FileCheckpointRowView(checkpoint: checkpoint)
//                }
//            }
//        }
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
