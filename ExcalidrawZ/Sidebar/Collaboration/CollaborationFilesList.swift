//
//  CollaborationFilesList.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/13/25.
//

import SwiftUI

import ChocofordUI

struct CollaborationFilesList: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    
    var sortField: ExcalidrawFileSortField
    
    init(sortField: ExcalidrawFileSortField) {
        self.sortField = sortField
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                CollaborationFilesContent(sortField: sortField)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .fileListDropFallback()
    }
}

struct CollaborationFilesContent: View {
    @FetchRequest
    private var collaborationFiles: FetchedResults<CollaborationFile>

    init(sortField: ExcalidrawFileSortField) {
        let sortDescriptors: [SortDescriptor<CollaborationFile>] = {
            switch sortField {
                case .updatedAt:
                    [
                        SortDescriptor(\.updatedAt, order: .reverse),
                        SortDescriptor(\.createdAt, order: .reverse)
                    ]
                case .name:
                    [
                        SortDescriptor(\.name, order: .reverse),
                    ]
                case .rank:
                    [
                        SortDescriptor(\.rank, order: .forward),
                    ]
            }
        }()
        self._collaborationFiles = FetchRequest<CollaborationFile>(
            sortDescriptors: sortDescriptors,
            animation: .smooth
        )
    }
    
    var body: some View {
        LazyVStack(alignment: .leading) {
            /// ❕❕❕use `id: \.self` can avoid multi-thread access crash when closing join-room-sheet.
            ForEach(collaborationFiles, id: \.self) { file in
                CollaborationFileRow(file: file)
            }
        }
        .fileListDropFallback()
        // ⬇️ cause `com.apple.SwiftUI.AsyncRenderer (22): EXC_BREAKPOINT` on iOS
        // .animation(.smooth, value: files)
    }
    
}

#Preview {
    CollaborationFilesList(sortField: .name)
}
