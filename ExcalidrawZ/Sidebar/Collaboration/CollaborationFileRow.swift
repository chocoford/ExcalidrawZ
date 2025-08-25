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
    var collaborationFiles: FetchedResults<CollaborationFile>
    
    init(file: CollaborationFile, files: FetchedResults<CollaborationFile>) {
        self.file = file
        self.collaborationFiles = files
    }
    
    var isSelected: Bool {
        if case .collaborationFile(let room) = fileState.currentActiveFile {
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
    
    var body: some View {
        FileRowButton(isSelected: isSelected, isMultiSelected: false) {
            if collaborationState.userCollaborationInfo.username.isEmpty {
                alert(title: .localizable(.collaborationAlertNameRequiredTitle)) {
                    Text(.localizable(.collaborationAlertNameRequiredMessage))
                }
            } else if let limit = store.collaborationRoomLimits,
                      fileState.collaboratingFiles.count >= limit,
                      !fileState.collaboratingFiles.contains(file) {
                store.togglePaywall(reason: .roomLimit)
            } else {
                fileState.currentActiveFile = .collaborationFile(file)
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
        .modifier(FileRowDragDropModifier(file: file, allCollaborationFiles: collaborationFiles))
        .modifier(CollaborationFileContextMenuModifier(file: file))
    }
}
