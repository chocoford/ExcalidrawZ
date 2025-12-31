//
//  SyncQueue.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/12/31.
//

import Foundation
import Logging

/// Persistent queue for sync operations
actor SyncQueue {
    private let logger = Logger(label: "SyncQueue")

    private var queue: [SyncEvent] = []
    private let queueKey = "com.excalidrawz.syncQueue"
    private var isLoaded = false

    // MARK: - Initialization

    init() {
        // Load queue from persistent storage
        loadQueue()
    }

    // MARK: - Queue Operations

    /// Enqueue a sync event
    func enqueue(_ event: SyncEvent) {
        queue.append(event)
        saveQueue()
        logger.debug("Queued sync operation: \(event.operation) for \(event.relativePath)")
    }

    /// Dequeue a specific event
    func dequeue(_ event: SyncEvent) {
        queue.removeAll { $0.id == event.id }
        saveQueue()
    }

    /// Remove multiple events by IDs
    func removeEvents(withIDs ids: Set<UUID>) {
        queue.removeAll { ids.contains($0.id) }
        saveQueue()
    }

    /// Get all queued events
    func getAll() -> [SyncEvent] {
        return queue
    }

    /// Get queue count
    func count() -> Int {
        return queue.count
    }

    /// Check if queue is empty
    func isEmpty() -> Bool {
        return queue.isEmpty
    }

    /// Clear all events
    func clear() {
        queue.removeAll()
        saveQueue()
    }

    // MARK: - Persistence

    /// Load queue from UserDefaults
    private func loadQueue() {
        guard !isLoaded else { return }

        if let data = UserDefaults.standard.data(forKey: queueKey) {
            do {
                let decoder = JSONDecoder()
                let loadedQueue = try decoder.decode([SyncEvent].self, from: data)
                self.queue = loadedQueue
                self.isLoaded = true
                logger.info("Loaded \(loadedQueue.count) queued sync operations")
            } catch {
                logger.error("Failed to load sync queue: \(error.localizedDescription)")
                self.queue = []
                self.isLoaded = true
            }
        } else {
            self.isLoaded = true
        }
    }

    /// Save queue to UserDefaults
    private func saveQueue() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(queue)
            UserDefaults.standard.set(data, forKey: queueKey)
        } catch {
            logger.error("Failed to save sync queue: \(error.localizedDescription)")
        }
    }
}
