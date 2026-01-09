//
//  LocalFilesListView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2/21/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct LocalFilesListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var horizontalSizeClass
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState
    
    var folder: LocalFolder
    var sortField: ExcalidrawFileSortField
    
    init(
        folder: LocalFolder,
        sortField: ExcalidrawFileSortField
    ) {
        self.folder = folder
        self.sortField = sortField
    }
    
    var body: some View {
        ScrollView {
            LocalFilesListContentView(folder: folder, sortField: sortField)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
#if os(macOS)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                                return
                            }
                            fileState.resetSelections()
                        }
                }
#endif
        }
    }
}

struct LocalFilesListContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.alertToast) private var alertToast
    @Environment(\.containerHorizontalSizeClass) private var horizontalSizeClass
    
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var localFolderState: LocalFolderState
    @EnvironmentObject private var sidebarDragState: ItemDragState
    
    var folder: LocalFolder
    var sortField: ExcalidrawFileSortField
    
    @State private var isBeingDropped: Bool = false
    
    var body: some View {
        LocalFilesProvider(folder: folder, sortField: sortField) { files, updateFlags in
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files, id: \.self) { file in
                    LocalFileRowView(
                        file: file,
                        updateFlag: updateFlags[file],
                        files: files
                    )
                    .id(updateFlags[file])
                }
            }
            .animation(.default, value: files)
            .modifier(LocalFolderDropModifier(folder: folder) {.below($0)})
        }
    }
}
