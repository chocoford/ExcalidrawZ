//
//  CollaborationFileRowContextMenu.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 8/7/25.
//

import SwiftUI

struct CollaborationFileMenuProvider: View {
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState

    var file: CollaborationFile
    var content: (Triggers) -> AnyView
    
    init<Content: View>(
        file: CollaborationFile,
        content: @escaping (Triggers) -> Content
    ) {
        self.file = file
        self.content = { AnyView(content($0)) }
    }
    
    struct Triggers {
        var onArchiveFile: (CollaborationFile) -> Void
        var onToggleDelete: () -> Void
    }
    
    @State private var isDeleteRoomConfirmationDialogPresented: Bool = false
    @State private var fileToBeArchived: CollaborationFile?
    
    var triggers: Triggers {
        Triggers {
            fileToBeArchived = $0
        } onToggleDelete: {
            isDeleteRoomConfirmationDialogPresented.toggle()
        }
    }
    
    var body: some View {
        content(triggers)
            .modifier(ArchiveRoomModifier(collaborationFile: $fileToBeArchived))
            .confirmationDialog(
                String(
                    localizable: .sidebarCollaborationFileRowDeleteConfirmationTitle(file.name ?? String(localizable: .generalUntitled))
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
        let fileID = file.objectID
        Task.detached {
            do {
                try await PersistenceController.shared.collaborationFileRepository.delete(
                    collaborationFileObjectID: fileID,
                    save: true
                )
            } catch {
                await alertToast(error)
            }
        }

        fileState.collaboratingFiles.removeAll(where: {$0 == file})
        fileState.collaboratingFilesState[file] = nil
        if fileState.currentActiveFile == .collaborationFile(file) {
            fileState.setActiveFile(nil)
        }
    }
}

struct CollaborationFileContextMenuModifier: ViewModifier {
    var file: CollaborationFile

    func body(content: Content) -> some View {
        CollaborationFileMenuProvider(file: file) { triggers in
            content
                .contextMenu {
                    CollaborationFileMenuItems(file: file) {
                        triggers.onArchiveFile($0)
                    } onDelete: {
                        triggers.onToggleDelete()
                    }
                    .labelStyle(.titleAndIcon)
                }
        }
    }
}

struct CollaborationFileMenu: View {
    var file: CollaborationFile
    var label: AnyView
    
    init<Label: View>(
        file: CollaborationFile,
        @ViewBuilder label: () -> Label
    ) {
        self.file = file
        self.label = AnyView(label())
    }
    
    var body: some View {
        CollaborationFileMenuProvider(file: file) { triggers in
            Menu {
                CollaborationFileMenuItems(
                    file: file
                ) { file in
                    triggers.onArchiveFile(file)
                } onDelete: {
                    triggers.onToggleDelete()
                }
            } label: {
                label
            }
        }
    }
}

struct CollaborationFileMenuItems: View {
    
    @EnvironmentObject private var fileState: FileState

    var file: CollaborationFile
    // @Binding var fileToBeArchived: CollaborationFile?
    
    var onArchiveFile: (CollaborationFile) -> Void
    var onDelete: () -> Void
    
    var body: some View {
        Button {
            fileState.currentActiveFile = .collaborationFile(file)
        } label: {
            if #available(macOS 13.0, *) {
                Label(
                    .localizable(.collaborationButtonJoinRoom),
                    systemSymbol: .doorLeftHandOpen
                )
            } else {
                Label(
                    .localizable(.collaborationButtonJoinRoom),
                    systemSymbol: .ipadAndArrowForward
                )
            }
        }
        
        
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
            onArchiveFile(file)
        } label: {
            Label(
                .localizable(.sidebarCollaborationFileRowContextMenuArchive),
                systemSymbol: .archivebox
            )
        }
        
        if fileState.collaboratingFiles.contains(file) {
            Button {
                fileState.collaboratingFiles.removeAll(where: {$0 == file})
                fileState.collaboratingFilesState[file] = nil
                if fileState.currentActiveFile == .collaborationFile(file) {
                    fileState.setActiveFile(nil)
                }
            } label: {
                Label(
                    .localizable(.sidebarCollaborationFileRowContextMenuDisconnect),
                    systemSymbol: .rectanglePortraitAndArrowRight
                )
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
        }
    }
}
