//
//  CollaborationFileRow.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI
import CoreData

import ChocofordUI

struct CollaborationFileRow: View {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.alert) private var alert
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState

    var file: CollaborationFile
    
    init(file: CollaborationFile) {
        self.file = file
    }
    
    var isSelected: Bool {
        if case .room(let room) = fileState.currentCollaborationFile {
            return room == file
        } else {
            return false
        }
    }
    var isInCollaboration: Bool { fileState.collaboratingFiles.contains(where: {$0 == file}) }
    var collaboratingState: ExcalidrawView.LoadingState? {
        fileState.collaboratingFilesState[file]
    }
    var stateIndicatorColor: Color {
        switch collaboratingState {
            case .none, .idle:
                return .gray
            case .loaded:
                return .green
            case .loading:
                return .yellow
            case .error:
                return .red
        }
    }
    
    @State private var isDeleteRoomConfirmationDialogPresented = false
    @State private var fileToBeArchived: CollaborationFile?
    
    var body: some View {
        FileRowButton(isSelected: isSelected) {
            if collaborationState.userCollaborationInfo.username.isEmpty {
                alert(title: .localizable(.collaborationAlertNameRequiredTitle)) {
                    Text(.localizable(.collaborationAlertNameRequiredMessage))
                }
            } else if let limit = store.collaborationRoomLimits,
                      fileState.collaboratingFiles.count >= limit,
                      !fileState.collaboratingFiles.contains(file) {
                store.togglePaywall(reason: .roomLimit)
            } else {
                fileState.currentCollaborationFile = .room(file)
            }
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Text(file.name ?? String(localizable: .generalUntitled))
                        .foregroundColor(.secondary)
                        .font(.title3)
                        .lineLimit(1)
                    
                    if isInCollaboration {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemSymbol: .person2)
                            Text("\(fileState.collaborators[file]?.count ?? 0)")
                        }
                        .font(.footnote)
                    }
                }
                .padding(.bottom, 4)

                HStack {
                    if let updatedAt = file.updatedAt {
                        Text(updatedAt.formatted())
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(stateIndicatorColor)
                        .shadow(color: stateIndicatorColor, radius: 2)
                        .frame(width: 6, height: 6)
                }
                .font(.footnote)
            }
        }
        .modifier(FileRowDragDropModifier(file: file, sortField: fileState.sortField))
        .modifier(ArchiveRoomModifier(collaborationFile: $fileToBeArchived))
        .contextMenu {
            contextMenu()
                .labelStyle(.titleAndIcon)
        }
        .confirmationDialog(
            .localizable(.sidebarCollaborationFileRowContextMenuDelete),
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
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
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
            if fileState.currentCollaborationFile == .room(file) {
                fileState.currentCollaborationFile = nil
            }
        } label: {
            Label(
                .localizable(.sidebarCollaborationFileRowContextMenuDisconnect),
                systemSymbol: .rectanglePortraitAndArrowRight
            )
        }

        Divider()

        Button(role: .destructive) {
            isDeleteRoomConfirmationDialogPresented.toggle()
        } label: {
            Label(.localizable(.generalButtonDelete), systemSymbol: .trash)
        }
    }
    
    private func deleteCollaborationFile(file: CollaborationFile) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        let fileID = file.objectID
        Task.detached {
            do {
                try await context.perform {
                    guard let file = context.object(with: fileID) as? CollaborationFile else { return }

                    context.delete(file)
                    
                    // also delete checkpoints
                    let checkpointsFetchRequest = NSFetchRequest<FileCheckpoint>(entityName: "FileCheckpoint")
                    checkpointsFetchRequest.predicate = NSPredicate(format: "collaborationFile = %@", file)
                    let checkpoints = try context.fetch(checkpointsFetchRequest)
                    if !checkpoints.isEmpty {
                        let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: checkpoints.map{$0.objectID})
                        try context.executeAndMergeChanges(using: batchDeleteRequest)
                    }

                    try context.save()
                    
                }
            } catch {
                await alertToast(error)
            }
        }
        
        fileState.collaboratingFiles.removeAll(where: {$0 == file})
        fileState.collaboratingFilesState[file] = nil
        if fileState.currentCollaborationFile == .room(file) {
            fileState.currentCollaborationFile = nil
        }
    }
}

//#Preview {
//    CollaborationFileRow()
//}
