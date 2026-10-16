//
//  ExcalidrawEditor+CloudKitSync.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 12/27/25.
//

import SwiftUI
import CoreData
import Combine

/// ViewModifier that handles CloudKit sync events for database files.
private struct CloudKitSyncModifier: ViewModifier {
    @Environment(FileState.self) var fileState

    let activeFile: FileState.ActiveFile?
    let onReloadNeeded: () -> Void

    @State private var isImporting = false
    @State private var fileBeforeImporting: ExcalidrawFile?
    @State private var cloudContainerEventChangeListener: AnyCancellable?

    func body(content: Content) -> some View {
        content
            .task {
                startCloudKitEventListener()
            }
    }

    private func startCloudKitEventListener() {
        cloudContainerEventChangeListener?.cancel()
        cloudContainerEventChangeListener = NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification
        ).sink { notification in
            guard let userInfo = notification.userInfo,
                  let event = userInfo["event"] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            Task { @MainActor in
                // Import started - save current file state
                if event.type == .import, !event.succeeded {
                    isImporting = true
                    if case .file(let file) = activeFile {
                        do {
                            let content = try await file.loadContent()
                            fileBeforeImporting = try ExcalidrawFile(data: content, id: file.id?.uuidString)
                        } catch {
                            // Failed to load content, ignore
                        }
                    }
                }

                // Import succeeded - check if reload needed
                if event.type == .import, event.succeeded, isImporting {
                    isImporting = false
                    if case .file(let file) = activeFile {
                        do {
                            let content = try await file.loadContent()
                            let fileAfterImporting = try ExcalidrawFile(data: content, id: file.id?.uuidString)

                            // Check if content actually changed
                            if fileBeforeImporting?.elements == fileAfterImporting.elements {
                                // No changes, do nothing
                            } else if Set(fileAfterImporting.elements).isSubset(of: Set(fileBeforeImporting?.elements ?? [])) {
                                // Local changes include all cloud changes, do nothing
                            } else {
                                // Cloud has new changes, force reload
                                onReloadNeeded()
                            }
                        } catch {
                            // Failed to load content, ignore
                        }
                    }
                }
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Apply CloudKit sync monitoring.
    @ViewBuilder
    func applyCloudKitSync(
        activeFile: FileState.ActiveFile?,
        onReloadNeeded: @escaping () -> Void
    ) -> some View {
        self.modifier(CloudKitSyncModifier(
            activeFile: activeFile,
            onReloadNeeded: onReloadNeeded
        ))
    }
}
