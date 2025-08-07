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
        let context = PersistenceController.shared.container.newBackgroundContext()
        let fileID = file.objectID
        let name = file.name ?? String(localizable: .generalUntitled)
        let content = file.content
        if case .group(let group) = fileState.currentActiveGroup {
            let groupID = group.objectID
            Task.detached {
                do {
                    try await context.perform {
                        guard case let group as Group = context.object(with: groupID) else { return }
                        let newFile = File(name: name, context: context)
                        newFile.group = group
                        newFile.content = content
                        newFile.inTrash = false
                        
                        context.insert(newFile)
                        
                        try context.save()
                        
                        let fileID = newFile.objectID
                        Task {
                            await MainActor.run {
                                if let group = viewContext.object(with: groupID) as? Group {
                                    parentFileState.currentActiveGroup = .group(group)
                                    if let file = viewContext.object(with: fileID) as? File {
                                        parentFileState.currentActiveFile = .file(file)
                                    }
                                    parentFileState.expandToGroup(groupID)
                                }
                            }
                        }
                    }
                    await dismiss()
                } catch {
                    await alertToast(error)
                }
            }
            
        } else if case .localFolder(let localFolder) = fileState.currentActiveGroup {
            let localFolderID = localFolder.objectID
            Task.detached {
                do {
                    try await context.perform {
                        guard case let localFolder as LocalFolder = context.object(with: localFolderID) else { return }
                        try localFolder.withSecurityScopedURL { scopedURL in
                            var file = try ExcalidrawFile(from: fileID, context: context)
                            try file.syncFiles(context: context)
                            let fileURL = scopedURL.appendingPathComponent(
                                name,
                                conformingTo: .excalidrawFile
                            )
                            try file.content?.write(to: fileURL)
                            Task {
                                await MainActor.run {
                                    if let localFolder = viewContext.object(with: localFolderID) as? LocalFolder {
                                        parentFileState.currentActiveGroup = .localFolder(localFolder)
                                        parentFileState.currentActiveFile = .localFile(fileURL)
                                        parentFileState.expandToGroup(localFolderID)
                                    }
                                }
                            }
                        }
                    }
                    await dismiss()
                } catch {
                    await alertToast(error)
                }
            }
        }
        
    }
}

//#Preview {
//    ArchiveRoomSheetView()
//        .environmentObject(FileState())
//}
