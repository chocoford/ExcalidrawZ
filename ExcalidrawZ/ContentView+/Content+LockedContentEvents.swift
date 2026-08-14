//
//  Content+LockedContentEvents.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/05/31.
//

import Combine
import CoreData
import SwiftUI

struct LockedContentEventModifier: ViewModifier {
    @EnvironmentObject private var lockedContentState: LockedContentStateStore
    @ObservedObject var fileState: FileState

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .lockedContentDidReset)
                    .receive(on: RunLoop.main)
            ) { _ in
                handleLockedContentReset()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .lockedContentDidDeleteFile)
                    .receive(on: RunLoop.main)
            ) { notification in
                handleLockedContentFileDeletion(notification)
            }
    }

    @MainActor
    private func handleLockedContentReset() {
        fileState.discardAndCloseActiveFile()
        fileState.resetSelections()
        lockedContentState.resetAll()
    }

    @MainActor
    private func handleLockedContentFileDeletion(_ notification: Notification) {
        if let fileID = notification.userInfo?["fileID"] as? String {
            lockedContentState.removeDeletedFile(fileID: fileID)
        }

        guard let deletedObjectID = notification.object as? NSManagedObjectID,
              case .file(let activeFile) = fileState.currentActiveFile,
              activeFile.objectID == deletedObjectID else { return }

        fileState.discardAndCloseActiveFile()
        fileState.resetSelections()
    }
}
