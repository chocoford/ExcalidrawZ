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
    
    private var disabled: Bool {
        fileState.currentGroup?.groupType == .trash ||
        (
            fileState.currentFile == nil &&
            fileState.currentLocalFile == nil &&
            fileState.currentTemporaryFile == nil &&
            fileState.currentCollaborationFile == nil
        )
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label(.localizable(.checkpoints), systemSymbol: .clockArrowCirclepath)
        }
        .disabled(disabled)
        .help(.localizable(.checkpoints))
#if os(macOS)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            if let file = fileState.currentFile {
                FileCheckpointListView(file: file)
            } else if let localFile = fileState.currentLocalFile {
                FileCheckpointListView(localFile: localFile)
            } else if let tempFile = fileState.currentTemporaryFile {
                FileCheckpointListView(localFile: tempFile)
            } else if let file = fileState.currentCollaborationFile {
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
            } else if let localFile = fileState.currentLocalFile {
                if #available(macOS 13.3, iOS 16.4, *), horizontalSizeClass == .regular {
                    FileCheckpointListView(localFile: localFile)
                        .presentationCompactAdaptation(.popover)
                } else {
                    FileCheckpointListView(localFile: localFile)
                }
            } else if let tempFile = fileState.currentTemporaryFile {
                if #available(macOS 13.3, iOS 16.4, *), horizontalSizeClass == .regular {
                    FileCheckpointListView(localFile: tempFile)
                        .presentationCompactAdaptation(.popover)
                } else {
                    FileCheckpointListView(localFile: tempFile)
                }
            }
        }
#endif
    }
}

struct FileCheckpointListView<Checkpoint: FileCheckpointRepresentable>: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass
    @Environment(\.containerVerticalSizeClass) private var containerVerticalSizeClass
    @Environment(\.dismiss) private var dismiss

    @FetchRequest
    var fileCheckpoints: FetchedResults<Checkpoint>
        
    init(file: File) where Checkpoint == FileCheckpoint {
        self._fileCheckpoints = FetchRequest(
            sortDescriptors: [SortDescriptor(\.updatedAt, order: .reverse)],
            predicate: NSPredicate(format: "file == %@", file)
        )
    }
    
    init(file: CollaborationFile) where Checkpoint == FileCheckpoint {
        self._fileCheckpoints = FetchRequest(
            sortDescriptors: [SortDescriptor(\.updatedAt, order: .reverse)],
            predicate: NSPredicate(format: "collaborationFile == %@", file)
        )
    }
    
    init(localFile: URL) where Checkpoint == LocalFileCheckpoint {
        self._fileCheckpoints = FetchRequest(
            sortDescriptors: [SortDescriptor(\.updatedAt, order: .reverse)],
            predicate: NSPredicate(format: "url == %@", localFile as NSURL)
        )
    }
    
    @State private var selection: Checkpoint?
    
    var body: some View {
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
            .onAppear {
                print("[TEST] checkpoints: \(fileCheckpoints.count)")
            }
#endif
    }
}

