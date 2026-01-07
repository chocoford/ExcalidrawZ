//
//  JoinRoomSheetView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/18/25.
//

import SwiftUI
import CoreData

struct JoinRoomSheetView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alertToast) private var alertToast
    @EnvironmentObject private var fileState: FileState
    @State private var invitationLink: String = ""
    
    enum JoinRoomError: LocalizedError {
        case invalidLink
        case invalidRoomID
        
        var errorDescription: String? {
            switch self {
                case .invalidLink:
                    String(localizable: .collaborationJoinRoomErrorDescriptionInvalidLink)
                case .invalidRoomID:
                    String(localizable: .collaborationJoinRoomErrorDescriptionInvalidRoomID)
            }
        }
    }
    
    @State private var error: JoinRoomError?
    @State private var name: String = ""
    @State private var roomID: String?
    
    var canJoin: Bool {
        !invitationLink.isEmpty && error == nil && roomID != nil && !name.isEmpty
    }
    
    var body: some View {
        VStack {
            HStack {
                Text(.localizable(.collaborationJoinRoomSheetTitle))
                    .font(.headline)
                Spacer()
            }
            row(.localizable(.collaborationJoinRoomLinkFieldLabel)) {
                TextField(
                    .localizable(.collaborationJoinRoomLinkFieldLabel),
                    text: $invitationLink,
                    prompt: Text("https://excalidraw.com/#room=...")
                )
                .textFieldStyle(.roundedBorder)
                .onChange(of: invitationLink) { newValue in
                    DispatchQueue.main.async {
                        parseLink()
                    }
                }
                .onSubmit {
                    guard canJoin else { return }
                    dismiss()
                    joinRoom()
                }
            }
            row(.localizable(.generalName)) {
                TextField(.localizable(.generalName), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard canJoin else { return }
                        dismiss()
                        joinRoom()
                    }
            }
            Text(error?.errorDescription ?? error?.localizedDescription ?? "")
                .opacity(error == nil ? 0 : 1)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(height: 18, alignment: .top)
            
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(.localizable(.generalButtonCancel))
                        .frame(width: 60)
                }
                .modernButtonStyle(style: .glass)
                
                Button {
                    dismiss()
                    joinRoom()
                } label: {
                    Text(.localizable(.collaborationJoinRoomButtonJoin))
                        .frame(width: 60)
                }
                .modernButtonStyle(style: .glassProminent)
                .disabled(error != nil || roomID == nil || name.isEmpty)
            }
            .modernButtonStyle(shape: .modern)
        }
        .padding()
    }
    
    @MainActor @ViewBuilder
    private func row<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            content()
        }
    }
    
    private func parseLink() {
        if invitationLink.isEmpty {
            self.error = nil
            self.roomID = nil
            self.name = ""
            return
        }
        
        // Not a valid URL, treat as a raw room ID.
        if let url = URL(string: invitationLink) {
            if url.scheme == "excalidrawz" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   components.host == "collab",
                   let roomID = CollabRoomIDCoder.shared.decode(encodedString: String(components.path.dropFirst())) {
                    if checkRoomID(roomID: roomID) {
                        self.error = nil
                        self.name = components.queryItems?.first(where: {$0.name == "name"})?.value ?? String(localizable: .generalUntitled)
                        self.roomID = roomID
                    } else {
                        self.error = .invalidRoomID
                    }
                } else {
                    self.error = .invalidLink
                }
                return
            } else if url.scheme == "https" {
                // something like https://excalidraw.com/#room=f30fd641442177a46c86,6GVLbf3fP8txlKBqw6JNEQ
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   components.host == "excalidraw.com",
                   let roomID = components.fragment?.split(separator: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    
                    if checkRoomID(roomID: roomID) {
                        self.error = nil
                        self.name = components.queryItems?.first(where: {$0.name == "name"})?.value ?? String(localizable: .generalUntitled)
                        self.roomID = roomID
                    } else {
                        self.error = .invalidRoomID
                    }
                } else {
                    self.error = .invalidLink
                }
                return
            }
        } else {
            self.roomID = invitationLink
            self.error = nil
        }
        
        
        // parse link
        guard let url = URL(string: invitationLink),
              url.scheme == "excalidrawz",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "collab",
              let roomID = CollabRoomIDCoder.shared.decode(encodedString: String(components.path.dropFirst())) else {
            self.error = .invalidLink
            return
        }
        
        guard checkRoomID(roomID: roomID) else {
            self.error = .invalidRoomID
            return
        }
        
        self.error = nil
        self.name = components.queryItems?.first(where: {$0.name == "name"})?.value ?? String(localizable: .generalUntitled)
        self.roomID = roomID
    }
    
    /// The room ID must contains a comma.
    /// The string before the comma must be 20 characters long.
    /// The string after the comma must be 22 characters long.
    private func checkRoomID(roomID: String) -> Bool {
        let components = roomID.split(separator: ",")
        guard components.count == 2 else { return false }
        let firstPart = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let secondPart = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        
        return firstPart.count == 20 && secondPart.count == 22
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
                            name: name.isEmpty ? String(localizable: .generalUntitled) : name,
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
                                fileState.setActiveFile(.collaborationFile(room))
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
