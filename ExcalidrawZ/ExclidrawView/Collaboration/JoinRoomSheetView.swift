//
//  JoinRoomSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/18/25.
//

import SwiftUI

struct JoinRoomSheetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @State private var invitationLink: String = ""
    
    enum JoinRoomError: LocalizedError {
        case invalidLink
        
        var errorDescription: String? {
            switch self {
                case .invalidLink:
                    "Invalid link."
            }
        }
    }
    
    @State private var error: JoinRoomError?
    @State private var name: String?
    @State private var roomID: String?
    
    var body: some View {
        VStack {
            HStack {
                Text("Join a room")
                Spacer()
            }
            TextField("Invitation link", text: $invitationLink)
                .onChange(of: invitationLink) { newValue in
                    DispatchQueue.main.async {
                        parseLink()
                    }
                }
            Text(error?.errorDescription ?? error?.localizedDescription ?? "")
                .opacity(error == nil ? 0 : 1)
                .font(.footnote)
                .foregroundStyle(.red)
            
            Divider()
            
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(width: 60)
                }
                Button {
                    dismiss()
                    joinRoom()
                } label: {
                    Text("Join")
                        .frame(width: 60)
                }
                .buttonStyle(.borderedProminent)
                .disabled(error != nil)
            }
        }
        .padding()
    }
    
    private func parseLink() {
        self.name = nil
        
        // parse link
        guard let url = URL(string: invitationLink),
        url.scheme == "excalidrawz",
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.host == "collab",
        let roomID = CollabRoomIDCoder.shared.decode(encodedString: String(components.path.dropFirst())) else {
            self.error = .invalidLink
            return
        }
        
        self.error = nil
        self.name = components.queryItems?.first(where: {$0.name == "name"})?.value
        self.roomID = roomID
    }
    
    private func joinRoom() {
        guard error == nil, let roomID else { return }
        let context = PersistenceController.shared.container.newBackgroundContext()
        let name = name
        
        Task.detached {
            do {
                try await context.perform {
                    // fetch first
                    let fetchRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
                    fetchRequest.predicate = NSPredicate(format: "roomID = %@", roomID)
                    
                    let room: CollaborationFile
                    if let firstRoom = try context.fetch(fetchRequest).first {
                        room = firstRoom
                    } else {
                        room = CollaborationFile(
                            name: name ?? String(localizable: .generalUntitled),
                            content: ExcalidrawFile().content,
                            isOwner: false,
                            context: context
                        )
                        room.roomID = roomID
                        context.insert(room)
                        try context.save()
                    }
                    let roomID = room.objectID
                    Task {
                        await MainActor.run {
                            if let room = viewContext.object(with: roomID) as? CollaborationFile {
                                fileState.isInCollaborationSpace = true
                                fileState.currentCollaborationFile = room
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
