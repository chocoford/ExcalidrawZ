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
    
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    private var collaborationFiles: FetchedResults<CollaborationFile>
    
    init() { }
    
    var body: some View {
        content()
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
        VStack(spacing: 0) {
            Button {
                fileState.currentCollaborationFile = nil
            } label: {
                Label(.localizable(.sidebarCollaborationFileRowHomeTitle), systemSymbol: .house)
            }
            .buttonStyle(
                .listCell(selected: fileState.currentCollaborationFile == nil && fileState.isInCollaborationSpace)
            )
            
            Divider()
                .padding(.vertical, 4)
            
            ScrollView {
                LazyVStack(alignment: .leading) {
                    /// ❕❕❕use `id: \.self` can avoid multi-thread access crash when closing join-room-sheet.
                    ForEach(collaborationFiles, id: \.self) { file in
                        CollaborationFileRow(file: file)
                    }
                }
                // ⬇️ cause `com.apple.SwiftUI.AsyncRenderer (22): EXC_BREAKPOINT` on iOS
                // .animation(.smooth, value: files)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
}

#Preview {
    CollaborationFilesList()
}
