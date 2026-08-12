//
//  CompactBrowserView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/19/25.
//

import SwiftUI
import ChocofordUI
import CoreData

#if os(iOS)

// MARK: - Generic Browser Content View

struct CompactBrowserCollectionView<Folder: Identifiable, FolderContent: View>: View {
    @EnvironmentObject private var layoutState: LayoutState

    let folders: [Folder]
    let files: [FileState.ActiveFile]
    let folderContent: (Folder) -> FolderContent

    init(
        folders: [Folder],
        files: [FileState.ActiveFile],
        @ViewBuilder folderContent: @escaping (Folder) -> FolderContent
    ) {
        self.folders = folders
        self.files = files
        self.folderContent = folderContent
    }

    private var columns: [GridItem] {
        switch layoutState.compactBrowserLayout {
            case .grid:
                [GridItem(.adaptive(minimum: 100))]
            case .list:
                [GridItem(.flexible(minimum: 0, maximum: 1000))]
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(folders) { folder in
                    folderContent(folder)
                }

                ForEach(files) { file in
                    FileHomeItemView(
                        file: file,
                        selectionSiblings: files
                    )
                    .fileHomeItemStyle(.file)
                }
            }
            .padding()
        }
        .animation(.smooth, value: layoutState.compactBrowserLayout)
        .animation(.smooth(duration: 0.22), value: folders.map(\.id))
        .animation(.smooth(duration: 0.22), value: files.map(\.id))
    }
}

struct CompactBrowserContentView<HomeGroup: ExcalidrawGroup>: View {
    @Environment(\.isPresented) private var isPresented
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var fileState: FileState
    
    
    var title: String
    var group: HomeGroup
    var files: [FileState.ActiveFile]
    @FetchRequest
    private var childGroups: FetchedResults<HomeGroup>
    
    init(group: Group, files: [File]) where HomeGroup == Group {
        self.group = group
        self.title = group.name ?? String(localizable: .generalUntitled)
        self.files = files.map {.file($0)}
        self._childGroups = FetchRequest<Group>(
            sortDescriptors: [
                 NSSortDescriptor(keyPath: \Group.rank, ascending: true),
                 NSSortDescriptor(keyPath: \Group.type, ascending: true),
            ],
            predicate: group.groupType == .trash
                ? NSPredicate(value: false)
                : NSPredicate(format: "parent == %@", group)
        )
    }
    
    init(group: LocalFolder, files: [URL]) where HomeGroup == LocalFolder {
        self.group = group
        self.title = group.name ?? String(localizable: .generalUntitled)
        self.files = files.map {.localFile($0)}
        self._childGroups = FetchRequest<LocalFolder>(
            sortDescriptors: [NSSortDescriptor(keyPath: \LocalFolder.filePath, ascending: true)],
            predicate: NSPredicate(format: "parent == %@", group)
        )
    }
    
    var body: some View {
        CompactBrowserCollectionView(
            folders: Array(childGroups),
            files: files
        ) { group in
            NavigationLink(value: group.objectID) {
                CompactFolderItemView(group: group)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(fileState.currentActiveFile != nil)
        .watch(value: fileState.currentActiveFile) { activeFile in
            Task {
                if activeFile == nil {
                    await setLocalFilesMonitoringLevel(
                        files: files,
                        level: .visible
                    )
                } else {
                    await setLocalFilesMonitoringLevel(
                        files: files,
                        level: .never
                    )
                }
            }
        }
        .watch(value: scenePhase) { newValue in
            Task {
                if newValue == .active {
                    await setLocalFilesMonitoringLevel(
                        files: files,
                        level: .visible
                    )
                } else if scenePhase != .active, newValue == .background {
                    await setLocalFilesMonitoringLevel(
                        files: files,
                        level: .never
                    )
                }
            }
        }
        .task(id: files) {
            // Everytime calls
            await setLocalFilesMonitoringLevel(
                files: files,
                level: fileState.currentActiveFile != nil ? .never : .visible
            )
        }
        .onAppear {
            if let group = group as? Group {
                fileState.currentActiveGroup = .group(group)
            } else if let folder = group as? LocalFolder {
                fileState.currentActiveGroup = .localFolder(folder)
            }
        }
        .onDisappear {
            // remove visible monitoring
            Task {
                await setLocalFilesMonitoringLevel(files: files, level: .never)
            }
        }
    }
    
    
    private func setLocalFilesMonitoringLevel(
        files: [FileState.ActiveFile],
        level: FileMonitoringLevel
    ) async {
        await FileSyncCoordinator.shared.setFilesMonitoringLevel(
            files.compactMap {
                if case .localFile(let url) = $0 { return url }
                return nil
            },
            level: level
        )
    }
}

// MARK: - Group Browser View

struct CompactGroupBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var fileState: FileState

    var group: Group

    @FetchRequest
    private var files: FetchedResults<File>

    init(group: Group, sortField: ExcalidrawFileSortField = .updatedAt) {
        self.group = group

        self._files = FetchRequest(
            sortDescriptors: ExcalidrawFileSortProvider.fileSortDescriptors(for: sortField),
            predicate: group.groupType == .trash
            ? File.trashedPredicate
            : NSPredicate(format: "group == %@ AND inTrash == NO", group)
        )
    }

    var body: some View {
        CompactBrowserContentView(
            group: group,
            files: Array(files)
        )
        .watch(value: files.count) { count in
            guard group.groupType == .trash, count == 0 else { return }
            fileState.setActiveFile(nil)
            fileState.setActiveGroupIfNeeded(nil)
            dismiss()
        }
    }
}

// MARK: - Local Folder Browser View

struct CompactLocalFolderBrowserView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var fileState: FileState

    var folder: LocalFolder

    init(folder: LocalFolder) {
        self.folder = folder
    }

    var body: some View {
        LocalFilesProvider(folder: folder, sortField: fileState.sortField) { files, _ in
            CompactBrowserContentView(
                group: folder,
                files: files
            )
        }
    }
}

#if DEBUG
#Preview {
    CompactGroupBrowserView(group: Group.preview)
}
#endif

#endif
