//
//  FileCheckpointListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
import ChocofordEssentials

/// Inspector content that lists checkpoints for the currently active file.
/// Picks the right `FileCheckpointListView` overload based on the file type.
struct FileHistoryInspectorContent: View {
    @EnvironmentObject var fileState: FileState
    @EnvironmentObject var layoutState: LayoutState
    @EnvironmentObject var appPreference: AppPreference

    @ViewBuilder
    private func contentView() -> some View {
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

    var body: some View {
#if os(macOS)
        if appPreference.inspectorLayout == .sidebar {
            contentView()
                .toolbar {
                    InspectorHeaderToolbar(
                        title: String(localizable: .checkpoints),
                        isInspectorPresented: layoutState.isInspectorPresented
                    )
                }
        } else {
            contentView()
        }
#else
        contentView()
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
        content_macOS()
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
        let _ = print("[updateElements FileCheckpointListView] checkpoints count: \(fileCheckpoints.count), unique count: \(Set(fileCheckpoints).count), ids: \(fileCheckpoints.map { $0.objectID })")
        
        if #available(macOS 26.0, *) {
            List {
                ForEach(fileCheckpoints, id: \.objectID) { checkpoint in
                    FileCheckpointRowView(checkpoint: checkpoint)
                }
            }
            .scrollContentBackground(.hidden)
        } else if #available(macOS 13.0, *) {
            List {
                ForEach(fileCheckpoints) { checkpoint in
                    FileCheckpointRowView(checkpoint: checkpoint)
                }
            }
            .scrollContentBackground(.hidden)
        } else {
            List {
                ForEach(fileCheckpoints,  id: \.objectID) { checkpoint in
                    FileCheckpointRowView(checkpoint: checkpoint)
                }
            }
        }
    }
#endif

}

