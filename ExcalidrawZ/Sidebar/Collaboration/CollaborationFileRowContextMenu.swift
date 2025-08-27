//
//  CollaborationFileRowContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/7/25.
//

import SwiftUI

struct CollaborationFileContextMenuModifier: ViewModifier {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    var file: CollaborationFile
    
    @State private var isDeleteRoomConfirmationDialogPresented: Bool = false
    @State private var fileToBeArchived: CollaborationFile?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                CollaborationFileRowContextMenu(file: file, fileToBeArchived: $fileToBeArchived) {
                    isDeleteRoomConfirmationDialogPresented.toggle()
                }
                .labelStyle(.titleAndIcon)
            }
            .modifier(ArchiveRoomModifier(collaborationFile: $fileToBeArchived))
            .confirmationDialog(
                .localizable(
                    .sidebarCollaborationFileRowDeleteConfirmationTitle(file.name ?? String(localizable: .generalUntitled))
                ),
                isPresented: $isDeleteRoomConfirmationDialogPresented,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    deleteCollaborationFile(file: file)
                } label: {
                    Text(.localizable(.generalButtonDelete))
                }
            }
    }
    
    private func deleteCollaborationFile(file: CollaborationFile) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let fileID = file.objectID
        Task.detached {
            do {
                try await context.perform {
                    guard let file = context.object(with: fileID) as? CollaborationFile else { return }
                    try file.delete(context: context)
                }
            } catch {
                await alertToast(error)
            }
        }
        
        fileState.collaboratingFiles.removeAll(where: {$0 == file})
        fileState.collaboratingFilesState[file] = nil
        if fileState.currentActiveFile == .collaborationFile(file) {
            fileState.currentActiveFile = nil
        }
    }
}

struct CollaborationFileRowContextMenu: View {
    
    @EnvironmentObject private var fileState: FileState

    var file: CollaborationFile
    @Binding var fileToBeArchived: CollaborationFile?
    
    var onDelete: () -> Void
    
    var body: some View {
        if let roomID = file.roomID {
            Button {
                copyRoomShareLink(roomID: roomID, filename: file.name)
            } label: {
                Label(
                    .localizable(.sidebarCollaborationFileRowContextMenuCopyInvitationLink),
                    systemSymbol: .link
                )
            }
        }
        Button {
            fileToBeArchived = file
        } label: {
            Label(
                .localizable(.sidebarCollaborationFileRowContextMenuArchive),
                systemSymbol: .archivebox
            )
        }
        
        Button {
            fileState.collaboratingFiles.removeAll(where: {$0 == file})
            fileState.collaboratingFilesState[file] = nil
            if fileState.currentActiveFile == .collaborationFile(file) {
                fileState.currentActiveFile = nil
            }
        } label: {
            Label(
                .localizable(.sidebarCollaborationFileRowContextMenuDisconnect),
                systemSymbol: .rectanglePortraitAndArrowRight
            )
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
        }
    }
}
