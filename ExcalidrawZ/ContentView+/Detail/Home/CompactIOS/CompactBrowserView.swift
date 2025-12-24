//
//  CompactBrowserView.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/19/25.
//

import SwiftUI
import CoreData

#if os(iOS)

// MARK: - Generic Browser Content View

struct CompactBrowserContentView<HomeGroup: ExcalidrawGroup>: View {
    @EnvironmentObject private var layoutState: LayoutState
    
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
            predicate: NSPredicate(format: "parent == %@", group)
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
    
    var columns: [GridItem] {
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
                ForEach(childGroups) { group in
                    NavigationLink(value: group.objectID) {
                        CompactFolderItemView(
                            group: group
                        )
                    }
                }
                
                ForEach(files) { file in
                    FileHomeItemView(file: file)
                        .fileHomeItemStyle(.file)
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth, value: layoutState.compactBrowserLayout)
    }
}

// MARK: - Group Browser View

struct CompactGroupBrowserView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var fileState: FileState

    var group: Group

    @FetchRequest
    private var files: FetchedResults<File>

    init(group: Group, sortField: ExcalidrawFileSortField = .updatedAt) {
        self.group = group

        // Fetch files in this group
        let sortDescriptors: [SortDescriptor<File>] = {
            switch sortField {
            case .updatedAt:
                [
                    SortDescriptor(\.updatedAt, order: .reverse),
                    SortDescriptor(\.createdAt, order: .reverse)
                ]
            case .name:
                [
                    SortDescriptor(\.name, order: .forward),
                    SortDescriptor(\.updatedAt, order: .reverse),
                    SortDescriptor(\.createdAt, order: .reverse),
                ]
            case .rank:
                [
                    SortDescriptor(\.rank, order: .forward),
                    SortDescriptor(\.updatedAt, order: .reverse),
                    SortDescriptor(\.createdAt, order: .reverse),
                ]
            }
        }()
        
        self._files = FetchRequest(sortDescriptors: sortDescriptors, predicate: NSPredicate(
            format: group.groupType == .trash ? "inTrash == YES" : "group == %@ AND inTrash == NO",
            group
        ), animation: .default)
    }

    var body: some View {
        CompactBrowserContentView(
            group: group,
            files: Array(files)
        )
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
