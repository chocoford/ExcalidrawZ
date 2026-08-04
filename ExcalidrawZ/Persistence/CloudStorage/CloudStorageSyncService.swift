//
//  CloudStorageSyncService.swift
//  ExcalidrawZ
//

import Combine
import Foundation
import Logging

/// Owns provider-backed synchronization for the lifetime of the app rather
/// than tying it to a Sidebar, FileHome, or Editor view instance.
@MainActor
final class CloudStorageSyncService {
    static let shared = CloudStorageSyncService()

    private let documentStore: CloudStorageDocumentStore
    private let pollingIntervalNanoseconds: UInt64
    private let logger = Logger(label: "CloudStorageSyncService")

    private var serviceObserverIDs: Set<UUID> = []
    private var serviceTask: Task<Void, Never>?
    private var locationObserver: AnyCancellable?
    private var observedLocationIDs: Set<UUID> = []
    private var locationSynchronizationTasks: [UUID: Task<Void, Never>] = [:]
    private var locationSynchronizationTaskIDs: [UUID: UUID] = [:]
    private var activeDocumentObservers: [String: Set<UUID>] = [:]

    private init() {
        self.documentStore = .shared
        self.pollingIntervalNanoseconds = 20_000_000_000
    }

    /// Keeps the global service alive while at least one app scene is active.
    func monitor(
        connections: CloudStorageConnectionStore
    ) async {
        let observerID = UUID()
        serviceObserverIDs.insert(observerID)
        startIfNeeded(connections: connections)
        defer { removeServiceObserver(observerID) }

        do {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        } catch {
            // Cancellation releases this scene's service lease.
        }
    }

    /// Prevents the global cache updater from replacing a document currently
    /// owned by an Editor. The Editor applies remote candidates after its own
    /// unsaved-change and conflict checks.
    func monitorActiveDocument(
        _ reference: CloudStorageDocumentReference
    ) async {
        let observerID = UUID()
        activeDocumentObservers[reference.id, default: []].insert(observerID)
        defer {
            activeDocumentObservers[reference.id]?.remove(observerID)
            if activeDocumentObservers[reference.id]?.isEmpty == true {
                activeDocumentObservers.removeValue(forKey: reference.id)
            }
        }

        do {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        } catch {
            // Cancellation releases this Editor's active-document lease.
        }
    }

    func enqueueUpload(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore? = nil
    ) {
        let connections = connections ?? .shared
        documentStore.scheduleContentSynchronization(
            for: reference,
            connections: connections,
            priority: .userInitiated
        )
    }

    func prioritizeDocuments(
        in location: CloudStorageLocation,
        parentID: CloudStorageItemID,
        connections: CloudStorageConnectionStore? = nil
    ) async {
        let connections = connections ?? .shared
        do {
            _ = try await connections.ensureAccess(to: location)
        } catch CloudStorageError.authorizationCancelled {
            return
        } catch {
#if DEBUG
            logger.warning(
                "Unable to restore cloud storage access for user-initiated synchronization location=\(location.displayName) id=\(location.id) error=\(error)"
            )
#endif
            return
        }

        let refreshed = await documentStore.refresh(
            location,
            connections: connections,
            force: true
        )
        guard refreshed else { return }
        documentStore.scheduleDocumentSynchronizations(
            in: location,
            parentID: parentID,
            excludingDocumentIDs: Set(activeDocumentObservers.keys),
            connections: connections,
            priority: .userInitiated
        )
    }

    private func startIfNeeded(
        connections: CloudStorageConnectionStore
    ) {
        guard serviceTask == nil else { return }

        serviceTask = Task { @MainActor [weak self, weak connections] in
            guard let self, let connections else { return }

            await CloudStorageBootstrap.registerConfiguredProviders()
            await connections.refresh()
            self.observeLocationChanges(connections: connections)

            while !Task.isCancelled {
                for location in connections.locations {
                    self.requestSynchronization(
                        for: location,
                        connections: connections
                    )
                }

                do {
                    try await Task.sleep(nanoseconds: pollingIntervalNanoseconds)
                } catch {
                    return
                }
            }
        }
    }

    private func observeLocationChanges(
        connections: CloudStorageConnectionStore
    ) {
        observedLocationIDs = Set(connections.locations.map(\.id))
        locationObserver = connections.$locations
            .dropFirst()
            .sink { [weak self, weak connections] locations in
                Task { @MainActor [weak self, weak connections] in
                    guard let self, let connections else { return }
                    let currentLocationIDs = Set(locations.map(\.id))
                    let removedLocationIDs = self.observedLocationIDs
                        .subtracting(currentLocationIDs)
                    let addedLocations = locations.filter {
                        !self.observedLocationIDs.contains($0.id)
                    }
                    self.observedLocationIDs = currentLocationIDs

                    for locationID in removedLocationIDs {
                        self.cancelSynchronization(for: locationID)
                    }
                    for location in addedLocations {
                        self.requestSynchronization(
                            for: location,
                            connections: connections
                        )
                    }
                }
            }
    }

    private func cancelSynchronization(for locationID: UUID) {
        locationSynchronizationTasks.removeValue(forKey: locationID)?.cancel()
        locationSynchronizationTaskIDs.removeValue(forKey: locationID)
    }

    private func requestSynchronization(
        for location: CloudStorageLocation,
        connections: CloudStorageConnectionStore
    ) {
        guard locationSynchronizationTasks[location.id] == nil else { return }

        let taskID = UUID()
        let task = Task { @MainActor [weak self, weak connections] in
            guard let self, let connections else { return }
            defer {
                if self.locationSynchronizationTaskIDs[location.id] == taskID {
                    self.locationSynchronizationTasks[location.id] = nil
                    self.locationSynchronizationTaskIDs[location.id] = nil
                }
            }
            guard !Task.isCancelled else { return }
#if DEBUG
            let startedAt = ContinuousClock.now
            logger.debug(
                "Synchronizing cloud location location=\(location.displayName) id=\(location.id)"
            )
#endif
            let refreshed = await documentStore.refresh(
                location,
                connections: connections,
                force: true
            )
            guard !Task.isCancelled, refreshed else {
#if DEBUG
                logger.debug(
                    "Skipped document synchronization after cloud location refresh failed location=\(location.displayName) id=\(location.id)"
                )
#endif
                return
            }
            documentStore.scheduleDocumentSynchronizations(
                in: location,
                excludingDocumentIDs: Set(activeDocumentObservers.keys),
                connections: connections,
                priority: .background
            )
#if DEBUG
            logger.debug(
                "Finished cloud location synchronization location=\(location.displayName) id=\(location.id) metadataRevision=\(documentStore.metadataRevision(for: location.id)) duration=\(startedAt.duration(to: .now))"
            )
#endif
        }
        locationSynchronizationTasks[location.id] = task
        locationSynchronizationTaskIDs[location.id] = taskID
    }

    private func removeServiceObserver(_ observerID: UUID) {
        serviceObserverIDs.remove(observerID)
        guard serviceObserverIDs.isEmpty else { return }
        serviceTask?.cancel()
        serviceTask = nil
        locationObserver = nil
        observedLocationIDs = []
        locationSynchronizationTasks.values.forEach { $0.cancel() }
        locationSynchronizationTasks = [:]
        locationSynchronizationTaskIDs = [:]
    }
}
