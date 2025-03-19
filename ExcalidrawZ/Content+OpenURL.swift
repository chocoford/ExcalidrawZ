//
//  Content+OpenURL.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 3/18/25.
//

import SwiftUI
import CoreData

import ChocofordUI

extension ContentView {
    // MARK: - Handle OpenURL
    func onOpenURL(_ url: URL) {
        if url.isFileURL {
            onOpenLocalFile(url)
        } else if url.scheme == "excalidrawz" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return
            }
            if components.host == "collab" {
                onOpenCollabURL(url, components: components)
            }
        }
    }
    
    private func onOpenLocalFile(_ url: URL) {
        // check if it is already in LocalFolder
        let context = viewContext
        var canAddToTemp = true
        do {
            try context.performAndWait {
                let folderFetchRequest = NSFetchRequest<LocalFolder>(entityName: "LocalFolder")
                folderFetchRequest.predicate = NSPredicate(format: "filePath == %@", url.deletingLastPathComponent().filePath)
                guard let folder = try context.fetch(folderFetchRequest).first else {
                    return
                }
                canAddToTemp = false
                Task {
                    await MainActor.run {
                        fileState.currentLocalFolder = folder
                        fileState.expandToGroup(folder.objectID)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(1e+9 * 0.1))
                    await MainActor.run {
                        fileState.currentLocalFile = url
                    }
                }
            }
        } catch {
            alertToast(error)
        }
        
        guard canAddToTemp else { return }
        
        // logger.debug("on open url: \(url, privacy: .public)")
        if !fileState.temporaryFiles.contains(where: {$0 == url}) {
            fileState.temporaryFiles.append(url)
        }
        if !fileState.isTemporaryGroupSelected || fileState.currentTemporaryFile == nil {
            fileState.isTemporaryGroupSelected = true
            fileState.currentTemporaryFile = fileState.temporaryFiles.first
        }
        // save a checkpoint immediately.
        Task.detached {
            do {
                try await context.perform {
                    let newCheckpoint = LocalFileCheckpoint(context: context)
                    newCheckpoint.url = url
                    newCheckpoint.updatedAt = .now
                    newCheckpoint.content = try Data(contentsOf: url)
                    
                    context.insert(newCheckpoint)
                    try context.save()
                }
            } catch {
                await alertToast(error)
            }
        }
    }
    
    private func onOpenCollabURL(_ url: URL, components: URLComponents) {
        let encodedRoomID = String(components.path.dropFirst())
        if let roomID = CollabRoomIDCoder.shared.decode(encodedString: encodedRoomID),
           let nameItem = components.queryItems?.first(where: {$0.name == "name"}) {
            let context = PersistenceController.shared.container.newBackgroundContext()
            Task.detached {
                do {
                    // fetch the room
                    try await context.perform {
                        let roomFetchRequest = NSFetchRequest<CollaborationFile>(entityName: "CollaborationFile")
                        roomFetchRequest.predicate = NSPredicate(format: "roomID = %@", roomID)
                        let room: CollaborationFile
                        if let firstRoom = try context.fetch(roomFetchRequest).first {
                            room = firstRoom
                        } else {
                            let newRoom = CollaborationFile(
                                name: nameItem.value ?? String(localizable: .generalUntitled),
                                content: ExcalidrawFile().content,
                                isOwner: false,
                                context: context
                            )
                            newRoom.roomID = roomID
                            context.insert(newRoom)
                            try context.save()
                            room = newRoom
                        }
                        let roomID = room.objectID
                        Task {
                            await MainActor.run {
                                fileState.isInCollaborationSpace = true
                                if case let room as CollaborationFile = viewContext.object(with: roomID) {
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
}
