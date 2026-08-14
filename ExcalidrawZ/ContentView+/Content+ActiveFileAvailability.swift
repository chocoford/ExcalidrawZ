//
//  Content+ActiveFileAvailability.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/08/12.
//

import Combine
import CoreData
import SwiftUI

/// Closes a Core Data-backed editor session when its source is deleted or
/// moved to Trash outside the active editor workflow.
struct ActiveFileAvailabilityModifier: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var fileState: FileState

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSManagedObjectContextObjectsDidChange,
                    object: viewContext
                )
                .receive(on: RunLoop.main)
            ) { notification in
                handleContextObjectsDidChange(notification)
            }
    }

    @MainActor
    private func handleContextObjectsDidChange(_ notification: Notification) {
        guard case .file(let activeFile) = fileState.currentActiveFile else {
            return
        }

        let activeObjectID = activeFile.objectID
        let deletedObjectIDs = objectIDs(
            for: NSDeletedObjectsKey,
            in: notification
        )
        if deletedObjectIDs.contains(activeObjectID) {
            discardActiveSession()
            return
        }

        let updatedObjectIDs = objectIDs(
            for: NSUpdatedObjectsKey,
            in: notification
        )
        guard updatedObjectIDs.contains(activeObjectID), activeFile.inTrash else {
            return
        }
        discardActiveSession()
    }

    private func objectIDs(
        for key: String,
        in notification: Notification
    ) -> Set<NSManagedObjectID> {
        if let objects = notification.userInfo?[key] as? Set<NSManagedObject> {
            return Set(objects.map(\.objectID))
        }
        if let objectIDs = notification.userInfo?[key] as? Set<NSManagedObjectID> {
            return objectIDs
        }
        if let objectIDs = notification.userInfo?[key] as? [NSManagedObjectID] {
            return Set(objectIDs)
        }
        return []
    }

    @MainActor
    private func discardActiveSession() {
        fileState.discardAndCloseActiveFile()
        fileState.resetSelections()
    }
}
