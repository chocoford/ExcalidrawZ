//
//  MediaItemSyncModifier.swift
//  ExcalidrawZ
//
//  Created by Claude on 2026/01/03.
//

import SwiftUI
import CoreData
import Logging

/// View modifier that monitors MediaItem changes and triggers re-injection to IndexedDB
/// Listens for CoreData remote changes, detects MediaItem count changes, and calls
/// ExcalidrawCore.refreshMediaItemsIfNeeded() to re-inject media to the WebView
struct MediaItemSyncModifier: ViewModifier {
    private let logger = Logger(label: "MediaItemSyncModifier")

    @EnvironmentObject private var fileState: FileState

    @State private var lastKnownMediaItemCount: Int = 0
    @State private var remoteChangeTask: Task<Void, Never>?
    @State private var refreshDebounceTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear {
                startMonitoring()
            }
            .onDisappear {
                stopMonitoring()
            }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Get initial MediaItem count
        Task {
            lastKnownMediaItemCount = await getCurrentMediaItemCount()
        }

        // Listen for remote changes from CloudKit
        remoteChangeTask = Task {
            let notifications = NotificationCenter.default.notifications(
                named: .NSPersistentStoreRemoteChange,
                object: PersistenceController.shared.container.persistentStoreCoordinator
            )

            for await notification in notifications {
                await handleRemoteChange(notification)
            }
        }
    }

    private func stopMonitoring() {
        remoteChangeTask?.cancel()
        refreshDebounceTask?.cancel()
    }

    // MARK: - Change Handling

    private func handleRemoteChange(_ notification: Notification) async {
        // Debounce: cancel previous task
        refreshDebounceTask?.cancel()

        refreshDebounceTask = Task {
            // Wait for debounce interval (2 seconds)
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            guard !Task.isCancelled else {
                return
            }

            // Check if MediaItem count has changed
            let currentCount = await getCurrentMediaItemCount()
            if currentCount != lastKnownMediaItemCount {
                logger.info("MediaItem count changed: \(lastKnownMediaItemCount) -> \(currentCount), triggering refresh...")
                lastKnownMediaItemCount = currentCount

                // Trigger MediaItem re-injection
                await refreshMediaItems()
            }
        }
    }

    // MARK: - Helper Methods

    /// Get current MediaItem entity count from CoreData
    private func getCurrentMediaItemCount() async -> Int {
        let context = PersistenceController.shared.newTaskContext()
        return await context.perform {
            let request: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
            return (try? context.count(for: request)) ?? 0
        }
    }

    /// Refresh MediaItems in the WebView
    @MainActor
    private func refreshMediaItems() async {
        // Access ExcalidrawCore through fileState
        guard let excalidrawCore = fileState.excalidrawWebCoordinator else {
            logger.warning("ExcalidrawCore not available, cannot refresh MediaItems")
            return
        }

        do {
            try await excalidrawCore.refreshMediaItemsIfNeeded()
        } catch {
            logger.error("Failed to refresh MediaItems: \(error.localizedDescription)")
        }
    }
}
