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
    private let connectivity: CloudStorageConnectivityMonitor
    private let pollingIntervalNanoseconds: UInt64
    private let activeDocumentPollingIntervalNanoseconds: UInt64
    private let logger = Logger(label: "CloudStorageSyncService")

    private var serviceTask: Task<Void, Never>?
    private var locationObserver: AnyCancellable?
    private var connectivityObserver: AnyCancellable?
    private var observedLocationIDs: Set<UUID> = []
    private var locationSynchronizationTasks: [UUID: Task<Void, Never>] = [:]
    private var locationSynchronizationTaskIDs: [UUID: UUID] = [:]
    private var pendingLocationSynchronizationIDs: Set<UUID> = []
    private var activeDocumentObservers: [String: Set<UUID>] = [:]

    private init() {
        self.documentStore = .shared
        self.connectivity = .shared
        self.pollingIntervalNanoseconds = 20_000_000_000
        self.activeDocumentPollingIntervalNanoseconds = 10_000_000_000
    }

    /// Starts the process-wide synchronization service. Its task is owned by
    /// the App rather than any WindowGroup, so closing the last window does not
    /// suspend provider synchronization while the process remains alive.
    func start() {
        start(connections: .shared)
    }

    func start(connections: CloudStorageConnectionStore) {
        startIfNeeded(connections: connections)
    }

    /// Prevents the global cache updater from replacing a document currently
    /// owned by an Editor, while asking that Editor to perform a safe remote
    /// check periodically. The Editor remains responsible for unsaved-change
    /// and conflict checks before applying a candidate.
    func monitorActiveDocument(
        _ reference: CloudStorageDocumentReference,
        requestRefresh: @escaping @MainActor () -> Void
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
            if connectivity.canAttemptNetworkRequests {
                requestRefresh()
            }
            while !Task.isCancelled {
                try await Task.sleep(
                    nanoseconds: activeDocumentPollingIntervalNanoseconds
                )
                guard connectivity.canAttemptNetworkRequests else { continue }
                requestRefresh()
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
        connectivity.startIfNeeded()
        documentStore.scheduleContentSynchronization(
            for: reference,
            connections: connections,
            priority: .userInitiated,
            queueAfterActiveSynchronization: true
        )
    }

    func enqueueMetadataSynchronization(
        for location: CloudStorageLocation,
        connections: CloudStorageConnectionStore? = nil
    ) {
        let connections = connections ?? .shared
        connectivity.startIfNeeded()
        requestSynchronization(
            for: location,
            connections: connections,
            queueAfterActiveSynchronization: true
        )
    }

    func removeConnection(
        for location: CloudStorageLocation,
        connections: CloudStorageConnectionStore? = nil
    ) async {
        let connections = connections ?? .shared
        cancelSynchronization(for: location.id)
        connections.removeLocation(location)
        await documentStore.removeCachedState(for: location.id)
    }

    func disconnect(
        _ account: CloudStorageAccount,
        connections: CloudStorageConnectionStore? = nil
    ) async throws {
        let connections = connections ?? .shared
        let locations = connections.locations.filter {
            $0.providerID == account.providerID && $0.accountID == account.id
        }
        try await connections.disconnect(account)
        for location in locations {
            cancelSynchronization(for: location.id)
            await documentStore.removeCachedState(for: location.id)
        }
    }

    func prioritizeDocuments(
        in location: CloudStorageLocation,
        parentID: CloudStorageItemID,
        connections: CloudStorageConnectionStore? = nil
    ) async {
        let connections = connections ?? .shared
        connectivity.startIfNeeded()
        guard connectivity.canAttemptNetworkRequests else { return }
        guard await documentStore.refresh(
            location,
            connections: connections,
            force: true
        ) else { return }
        scheduleDocumentSynchronizations(
            in: location,
            parentID: parentID,
            connections: connections
        )
    }

    /// A user explicitly entered or retried a cloud location, so restoring
    /// access may present the provider's authorization UI.
    func prioritizeDocumentsAfterUserEntry(
        in location: CloudStorageLocation,
        parentID: CloudStorageItemID,
        connections: CloudStorageConnectionStore? = nil
    ) async {
        let connections = connections ?? .shared
        connectivity.startIfNeeded()
        guard connectivity.canAttemptNetworkRequests else { return }
        guard await refreshForUserInitiatedSynchronization(
            location,
            connections: connections,
            reason: "folder"
        ) else { return }
        scheduleDocumentSynchronizations(
            in: location,
            parentID: parentID,
            connections: connections
        )
    }

    private func scheduleDocumentSynchronizations(
        in location: CloudStorageLocation,
        parentID: CloudStorageItemID,
        connections: CloudStorageConnectionStore
    ) {
        documentStore.scheduleDocumentSynchronizations(
            in: location,
            parentID: parentID,
            excludingDocumentIDs: Set(activeDocumentObservers.keys),
            connections: connections,
            priority: .userInitiated
        )
    }

    /// Refreshes linked-storage metadata for Recently, then promotes the most
    /// recently modified documents ahead of background content synchronization.
    func prioritizeRecentlyModifiedDocuments(
        connections: CloudStorageConnectionStore? = nil,
        limit: Int = 20
    ) async {
        let connections = connections ?? .shared
        connectivity.startIfNeeded()
        guard connectivity.canAttemptNetworkRequests else { return }
        let locations = connections.locations
        guard !locations.isEmpty else { return }

        // Home appears automatically during launch. Refresh Recently without
        // allowing a missing or expired credential to present OAuth UI.
        for location in locations {
            _ = await documentStore.refresh(
                location,
                connections: connections,
                force: true
            )
        }

        let recentReferences = documentStore
            .indexedDocumentReferences(in: locations)
            .filter {
                documentStore.capabilities(for: $0).contains(.download)
                    && activeDocumentObservers[$0.id] == nil
            }
            .sorted {
                ($0.lastKnownModifiedAt ?? .distantPast)
                    > ($1.lastKnownModifiedAt ?? .distantPast)
            }
            .prefix(max(0, limit))

        for reference in recentReferences {
            documentStore.scheduleContentSynchronizationIfNeeded(
                for: reference,
                connections: connections,
                priority: .userInitiated
            )
        }
    }

    private func refreshForUserInitiatedSynchronization(
        _ location: CloudStorageLocation,
        connections: CloudStorageConnectionStore,
        reason: String
    ) async -> Bool {
        guard connectivity.canAttemptNetworkRequests else { return false }
        do {
            _ = try await connections.ensureAccess(to: location)
        } catch CloudStorageError.authorizationCancelled {
            return false
        } catch {
#if DEBUG
            logger.warning(
                "Unable to restore cloud storage access reason=\(reason) location=\(location.displayName) id=\(location.id) error=\(error)"
            )
#endif
            return false
        }

        return await documentStore.refresh(
            location,
            connections: connections,
            force: true
        )
    }

    private func startIfNeeded(
        connections: CloudStorageConnectionStore
    ) {
        guard serviceTask == nil else { return }
        connectivity.startIfNeeded()

        serviceTask = Task { @MainActor [weak self, weak connections] in
            guard let self, let connections else { return }

            await CloudStorageBootstrap.registerConfiguredProviders()
            await connections.refresh()
            self.observeLocationChanges(connections: connections)
            self.observeConnectivity(connections: connections)

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

    private func observeConnectivity(
        connections: CloudStorageConnectionStore
    ) {
        connectivityObserver = connectivity.$status
            .removeDuplicates()
            // The service loop already performs the initial synchronization.
            // Skip CurrentValueSubject's replay so launch does not queue a
            // second pass for every connected location.
            .dropFirst()
            .sink { [weak self, weak connections] status in
                Task { @MainActor [weak self, weak connections] in
                    guard let self, let connections else { return }
                    switch status {
                        case .available:
                            self.documentStore.resumeQueuedContentSynchronizations()
                            for location in connections.locations {
                                self.requestSynchronization(
                                    for: location,
                                    connections: connections
                                )
                            }
                        case .unavailable:
                            for locationID in Array(self.locationSynchronizationTasks.keys) {
                                self.cancelSynchronization(for: locationID)
                            }
                        case .unknown:
                            break
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
        pendingLocationSynchronizationIDs.remove(locationID)
    }

    private func requestSynchronization(
        for location: CloudStorageLocation,
        connections: CloudStorageConnectionStore,
        queueAfterActiveSynchronization: Bool = false
    ) {
        guard connectivity.canAttemptNetworkRequests else { return }
        guard locationSynchronizationTasks[location.id] == nil else {
            if queueAfterActiveSynchronization {
                pendingLocationSynchronizationIDs.insert(location.id)
            }
            return
        }
        if let retryDate = documentStore.automaticRetryDate(for: location.id),
           retryDate > Date() {
            return
        }

        let taskID = UUID()
        let task = Task { @MainActor [weak self, weak connections] in
            guard let self, let connections else { return }
            defer {
                self.finishSynchronization(
                    for: location,
                    taskID: taskID,
                    connections: connections
                )
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

    private func finishSynchronization(
        for location: CloudStorageLocation,
        taskID: UUID,
        connections: CloudStorageConnectionStore
    ) {
        guard locationSynchronizationTaskIDs[location.id] == taskID else { return }
        locationSynchronizationTasks[location.id] = nil
        locationSynchronizationTaskIDs[location.id] = nil
        guard pendingLocationSynchronizationIDs.remove(location.id) != nil else { return }
        requestSynchronization(for: location, connections: connections)
    }

}
