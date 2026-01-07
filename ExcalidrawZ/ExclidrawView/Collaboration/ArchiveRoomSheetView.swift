//
//  ArchiveSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/19/25.
//

import SwiftUI

struct ArchiveRoomModifier: ViewModifier {
    @Binding var collaborationFile: CollaborationFile?
    
    @EnvironmentObject private var parentFileState: FileState
    
     @StateObject private var fileState = FileState()
    
    func body(content: Content) -> some View {
        content
            .sheet(item: $collaborationFile) { file in
                ArchiveRoomSheetView(file: file, parentFileState: parentFileState)
                    .padding()
                    .frame(width: 350, height: 500)
                    .environmentObject(fileState)
            }
    }
}

struct ArchiveRoomSheetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    
    @EnvironmentObject private var fileState: FileState
    
    var file: CollaborationFile
    @ObservedObject
    var parentFileState: FileState
    
    var body: some View {
        VStack {
            HStack {
                Text(.localizable(.collaborationFileArchiveSheetTitle))
                    .font(.title)
                Spacer()
            }
            ExcalidrawGroupBrowser()
                .background {
                    let roundedRectangle = RoundedRectangle(cornerRadius: 12)
                    
                    ZStack {
                        roundedRectangle.fill(.regularMaterial)
                        if #available(iOS 17.0, macOS 13.0, *) {
                            roundedRectangle.stroke(.separator)
                        } else {
                            roundedRectangle.stroke(.secondary)
                        }
                    }
                }
            HStack {
                Spacer()
                
                Button(role: .cancel) {
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                        .frame(width: 60)
                }
                
                Button {
                    archiveCollaborationFile()
                } label: {
                    Text(.localizable(.generalButtonSave))
                        .frame(width: 60)
                }
                .modernButtonStyle(style: .glassProminent)
                .disabled(fileState.currentActiveGroup == nil)
            }
            .modernButtonStyle(shape: .capsule)
        }
    }
    
    private func archiveCollaborationFile()  {
        guard let activeGroup = fileState.currentActiveGroup else { return }
        let fileID = file.objectID

        Task.detached {
            do {
                let result: CollaborationFileRepository.ArchiveTarget

                switch activeGroup {
                    case .group(let group):
                        let groupID = group.objectID
                        result = try await PersistenceController.shared.collaborationFileRepository.archiveToGroup(
                            collaborationFileObjectID: fileID,
                            targetGroupObjectID: groupID,
                            delete: false
                        )

                    case .localFolder(let localFolder):
                        let folderID = localFolder.objectID
                        result = try await PersistenceController.shared.collaborationFileRepository.archiveToLocalFolder(
                            collaborationFileObjectID: fileID,
                            targetLocalFolderObjectID: folderID,
                            delete: false
                        )

                    default:
                        return
                }

                await MainActor.run {
                    switch result {
                        case .file(_, let newFileID):
                            if let file = viewContext.object(with: newFileID) as? File {
                                parentFileState.setActiveFile(.file(file))
                            }

                        case .localFile(_, let url):
                            parentFileState.setActiveFile(.localFile(url))
                    }
                    dismiss()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}
