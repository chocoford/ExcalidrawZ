//
//  ShareToolbarButton.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI

class ShareFileState: ObservableObject {
    // TODO: ...
    @Published var currentSharedFile: ExcalidrawFile?
}

struct ShareToolbarButton: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast

    @EnvironmentObject var fileState: FileState
    @EnvironmentObject private var shareFileState: ShareFileState

    // should be outer, otherwise not stable
    // @Binding private var sharedFile: ExcalidrawFile?

    // Maybe a share file state
    
    var body: some View {
        Button {
            do {
                if let file = fileState.currentFile ?? fileState.currentCollaborationFile?.room {
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(from: file.objectID, context: viewContext)
                } else if let folder = fileState.currentLocalFolder,
                    let fileURL = fileState.currentLocalFile {
                    try folder.withSecurityScopedURL { _ in
                        self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: fileURL)
                    }
                } else if fileState.isTemporaryGroupSelected,
                          let fileURL = fileState.currentTemporaryFile {
                    self.shareFileState.currentSharedFile = try ExcalidrawFile(contentsOf: fileURL)
                }
            } catch {
                alertToast(error)
            }
        } label: {
            Label(.localizable(.export), systemSymbol: .squareAndArrowUp)
        }
        .help(.localizable(.export))
        .disabled(
            fileState.currentGroup?.groupType == .trash ||
            (
                fileState.currentFile == nil &&
                fileState.currentLocalFile == nil &&
                fileState.currentTemporaryFile == nil &&
                fileState.currentCollaborationFile == nil
            )
        )
    }
}

