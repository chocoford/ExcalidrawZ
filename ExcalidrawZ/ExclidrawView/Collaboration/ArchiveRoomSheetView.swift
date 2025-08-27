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
            }
            .environmentObject(fileState)
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
                .buttonStyle(.borderedProminent)
                .disabled(fileState.currentActiveGroup == nil)
            }
        }
    }
    
    private func archiveCollaborationFile()  {
        let fileID = file.objectID
        let name = file.name ?? String(localizable: .generalUntitled)
        let content = file.content
        guard let activeGroup = fileState.currentActiveGroup else { return }
        do {
            try file.archiveToLocal(
                group: activeGroup,
                delete: false,
            ) { error, target in
                switch target {
                    case .file(let groupID, let fileID):
                        if let group = viewContext.object(with: groupID) as? Group {
                            parentFileState.currentActiveGroup = .group(group)
                            if let file = viewContext.object(with: fileID) as? File {
                                parentFileState.currentActiveFile = .file(file)
                            }
                            parentFileState.expandToGroup(groupID)
                        }
                    case .localFile(let folderID, let url):
                        if let localFolder = viewContext.object(with: folderID) as? LocalFolder {
                            parentFileState.currentActiveGroup = .localFolder(localFolder)
                            parentFileState.currentActiveFile = .localFile(url)
                            parentFileState.expandToGroup(folderID)
                        }
                    case nil:
                        if let error {
                            alertToast(error)
                        }
                }
                dismiss()
            }
        } catch {
            alertToast(error)
        }
    }
}
