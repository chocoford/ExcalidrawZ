//
//  NewRoomModifier.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/18/25.
//

import SwiftUI

class CollaborationState: ObservableObject {
    @Published var isCreateRoomConfirmationDialogPresented = false
    @Published var isCreateRoomFromFileSheetPresented = false
    @Published var isJoinRoomSheetPresented = false
    
    @Published var isCreateRoomSheetPresented = false
    
    @AppStorage("userCollaborationName") private var userCollaborationName = ""
    var userCollaborationInfo: CollaborationInfo {
        get {
            CollaborationInfo(username: userCollaborationName)
        }
        set {
            userCollaborationName = newValue.username
        }
    }
}

struct NewRoomModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @StateObject private var state = CollaborationState()
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $state.isCreateRoomSheetPresented) {
                CreateRoomSheetView { name, isBlank in
                    if isBlank {
                        createRoom(name: name)
                    } else {
                        state.isCreateRoomFromFileSheetPresented.toggle()
                    }
                }
            }
            .confirmationDialog(
                .localizable(.collaborationNewRoomConfirmationDialogTitle),
                isPresented: $state.isCreateRoomConfirmationDialogPresented,
                titleVisibility: .visible
            ) {
                Button {
                    state.isCreateRoomSheetPresented.toggle()
                } label: {
                    Text(.localizable(.collaborationNewRoomConfirmationDialogButtonCreateBlankRoom))
                }
                Button {
                    state.isCreateRoomFromFileSheetPresented.toggle()
                } label: {
                    Text(.localizable(.collaborationNewRoomConfirmationDialogButtonCreateFromFile))
                }
            } message: {
                Text(.localizable(.collaborationNewRoomConfirmationDialogMessage))
            }
            .sheet(isPresented: $state.isCreateRoomFromFileSheetPresented) {
                ExcalidrawFileBrowser { selection in
                    do {
                        switch selection {
                            case .file(let file):
                                var excalidrawFile = try ExcalidrawFile(
                                    from: file.objectID,
                                    context: viewContext
                                )
                                try excalidrawFile.syncFiles(context: viewContext)
                                createRoom(
                                    name: file.name ?? String(localizable: .generalUntitled),
                                    file: excalidrawFile
                                )
                            case .localFile(let url):
                                createRoom(
                                    name: url.deletingPathExtension().lastPathComponent,
                                    file: try ExcalidrawFile(contentsOf: url)
                                )
                        }
                    } catch {
                        alertToast(error)
                    }
                }
            }
            .sheet(isPresented: $state.isJoinRoomSheetPresented) {
                JoinRoomSheetView()
            }
            .environmentObject(state)
    }
    
    private func createRoom(name: String, file: ExcalidrawFile = ExcalidrawFile()) {
        let context = PersistenceController.shared.container.newBackgroundContext()
        Task.detached {
            do {
                try await context.perform {
                    let collabFile = CollaborationFile(
                        name: name,
                        content: file.content,
                        isOwner: true,
                        context: context
                    )
                    collabFile.roomID = nil
                    try context.save()
                    
                    let fileID = collabFile.objectID
                    Task {
                        await MainActor.run {
                            if let collabFile = viewContext.object(with: fileID) as? CollaborationFile {
                                fileState.currentCollaborationFile = .room(collabFile)
                            }
                        }
                    }
                }
            } catch {
                await alertToast(error)
            }
        }
    }
}


func copyRoomShareLink(roomID: String, filename: String?) {
    let encodedRoomID = CollabRoomIDCoder.shared.encode(roomID: roomID)
    var url: URL
    if #available(macOS 13.0, *) {
        url = URL(string: "excalidrawz://collab/\(encodedRoomID)")!
        url.append(queryItems: [
            URLQueryItem(name: "name", value: filename?.isEmpty == false ? filename : nil)
        ])
    } else {
        url = URL(string: "excalidrawz://collab/\(encodedRoomID)" + (filename?.isEmpty == false ? "?name=\(filename!)" : ""))!
    }
#if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
#elseif os(iOS)
    UIPasteboard.general.setObjects([url])
#endif
}
