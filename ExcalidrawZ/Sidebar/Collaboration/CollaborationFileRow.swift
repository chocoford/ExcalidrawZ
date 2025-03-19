//
//  CollaborationFileRow.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/17/25.
//

import SwiftUI

import ChocofordUI

struct CollaborationFileRow: View {
    @Environment(\.alertToast) private var alertToast
    @Environment(\.alert) private var alert
    @EnvironmentObject private var fileState: FileState
    @EnvironmentObject private var collaborationState: CollaborationState

    var file: CollaborationFile
    
    init(file: CollaborationFile) {
        self.file = file
    }
    
    var isSelected: Bool { fileState.currentCollaborationFile == file }
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
        Button {
            if collaborationState.userCollaborationInfo.username.isEmpty {
                alert(title: "Name requeired") {
                    Text("Please input your name to start collaboration.")
                }
            } else {
                fileState.currentCollaborationFile = file
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
        .buttonStyle(.listCell(selected: isSelected))
        .contextMenu {
            contextMenu()
                .labelStyle(.titleAndIcon)
        }
        .confirmationDialog(
            "Delete room",
            isPresented: $isDeleteRoomConfirmationDialogPresented,
            titleVisibility: .automatic
        ) {
//            Button(role: .cancel) {
//                isDeleteRoomConfirmationDialogPresented.toggle()
//            } label: {
//                Text(.localizable(.generalButtonCancel))
//            }
            
            Button(role: .destructive) {
                deleteCollaborationFile(file: file)
            } label: {
                Text(.localizable(.generalButtonDelete))
            }
        }
        .modifier(ArchiveRoomModifier(collaborationFile: $fileToBeArchived))
    }
    
    @MainActor @ViewBuilder
    private func contextMenu() -> some View {
        if let roomID = file.roomID {
            Button {
                copyRoomShareLink(roomID: roomID, filename: file.name)
            } label: {
                Label("Copy share link", systemSymbol: .link)
            }
        }
#if DEBUG
//        Button {
//                let link = "excalidrawz://collab/9b9a9392cc9ccf98939acf9e98cccf9a9a9e9c9a86d8d9d0d39b87e2eedfdde087c7879e98f3d0d9e6e8cd?name=hellow"
//
//                let url = URL(string: link)!
//                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
//                    return
//                }
//                // print(components.queryItems)
//                if let nameItem = components.queryItems?.first(where: {$0.name == "name"}) {
//                    nameItem.value
//                }
//        } label: {
//            Text("Test accept share link")
//        }
#endif
        Button {
            fileToBeArchived = file
        } label: {
            Label("Archive...", systemSymbol: .archivebox)
        }
        
        Button {
            fileState.collaboratingFiles.removeAll(where: {$0 == file})
            fileState.collaboratingFilesState[file] = nil
            if fileState.currentCollaborationFile == file {
                fileState.currentCollaborationFile = nil
            }
        } label: {
            Label("Disconnect", systemSymbol: .rectanglePortraitAndArrowRight)
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
        if fileState.currentCollaborationFile == file {
            fileState.currentCollaborationFile = nil
        }
    }
}

//#Preview {
//    CollaborationFileRow()
//}
