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
        {
            if case .group(let group) = fileState.currentActiveGroup {
                return group.groupType == .trash
            }
            return false
        }() ||
        fileState.currentActiveFile == nil
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
            switch fileState.currentActiveFile {
                case .file(let file):
                    FileCheckpointListView(file: file)
                case .localFile(let url):
                    FileCheckpointListView(localFile: url)
                case .temporaryFile(let url):
                    FileCheckpointListView(localFile: url)
                case .collaborationFile(let collaborationFile):
                    FileCheckpointListView(file: collaborationFile)
                default:
                    EmptyView()
            }
        }
#elseif os(iOS)
        .sheet(isPresented: $isPresented) {
            switch fileState.currentActiveFile {
                case .file(let file):
                    if #available(macOS 13.3, iOS 16.4, *), horizontalSizeClass == .regular {
                        FileCheckpointListView(file: file)
                            .presentationCompactAdaptation(.popover)
                    } else {
                        FileCheckpointListView(file: file)
                    }
                case .localFile(let url):
                    if #available(macOS 13.3, iOS 16.4, *), horizontalSizeClass == .regular {
                        FileCheckpointListView(localFile: localFile)
                            .presentationCompactAdaptation(.popover)
                    } else {
                        FileCheckpointListView(localFile: localFile)
                    }
                case .temporaryFile(let url):
                    if #available(macOS 13.3, iOS 16.4, *), horizontalSizeClass == .regular {
                        FileCheckpointListView(localFile: tempFile)
                            .presentationCompactAdaptation(.popover)
                    } else {
                        FileCheckpointListView(localFile: tempFile)
                    }
                case .collaborationFile(let collaborationFile):
                    if #available(macOS 13.3, iOS 16.4, *), horizontalSizeClass == .regular {
                        FileCheckpointListView(file: collaborationFile)
                            .presentationCompactAdaptation(.popover)
                    } else {
                        FileCheckpointListView(file: collaborationFile)
                    }
                default:
                    EmptyView()
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
        content()
    }
    
    
    @MainActor @ViewBuilder
    private func content() -> some View {
#if os(iOS)
        content_iOS()
#else
        if #available(macOS 26.0, *) {
            content_macOS()
        } else {
            content_macOS()
        }
#endif
    }
    
#if os(iOS)

    @MainActor @ViewBuilder
    private func content_iOS() -> some View {
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
    }
#else
    @MainActor @ViewBuilder
    private func content_macOS() -> some View {
        if #available(macOS 13.0, *) {
            List {
                ForEach(fileCheckpoints) { checkpoint in
                    FileCheckpointRowView(checkpoint: checkpoint)
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            List {
                ForEach(fileCheckpoints) { checkpoint in
                    FileCheckpointRowView(checkpoint: checkpoint)
                }
            }
        }
    }
#endif

}

