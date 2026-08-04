//
//  CloudStorageDocumentStore.swift
//  ExcalidrawZ
//
//  Owns the device-local index and document cache for provider-backed files.
//  Sidebar views consume its snapshots; editor sessions never treat remote
//  identity as a local URL.
//

import Combine
import Foundation
import Logging

@MainActor
final class CloudStorageDocumentStore: ObservableObject {
    static let shared = CloudStorageDocumentStore()

    struct RemoteContentCandidate {
        let data: Data
        fileprivate let item: CloudStorageItem
    }

    @Published private(set) var itemsByLocationID: [UUID: [CloudStorageItemID: CloudStorageItem]] = [:]
    @Published private(set) var metadataRevisionsByLocationID: [UUID: Int] = [:]
    @Published private(set) var refreshingLocationIDs: Set<UUID> = []
    @Published private(set) var errorsByLocationID: [UUID: String] = [:]
    @Published private(set) var syncStatesByDocumentID: [String: CloudStorageDocumentSyncState] = [:]
    @Published private(set) var processingFolderIDsByLocationID: [
        UUID: Set<CloudStorageItemID>
    ] = [:]

    private struct PersistedLocationState: Codable {
        var cursor: CloudStorageChangeCursor?
        var items: [CloudStorageItem]
        var cachedRevisions: [CloudStorageItemID: String]
        var dirtyItemIDs: Set<CloudStorageItemID>
    }

    private struct MetadataMutationKey: Hashable {
        let locationID: UUID
        let itemID: CloudStorageItemID
    }

    private struct ContentSynchronizationRequest {
        let reference: CloudStorageDocumentReference
        let connections: CloudStorageConnectionStore
        var priority: CloudStorageContentSynchronizationPriority
        let sequence: Int
    }

    private let logger = Logger(label: "CloudStorageDocumentStore")
    private let fileManager: FileManager
    private let rootURL: URL
    private var persistedStates: [UUID: PersistedLocationState] = [:]
    private var loadedLocationIDs: Set<UUID> = []
    private var sessionsByLocationID: [UUID: any CloudStorageSession] = [:]
    private var refreshTasksByLocationID: [UUID: Task<Bool, Never>] = [:]
    private var refreshTaskIDsByLocationID: [UUID: UUID] = [:]
    private var saveTasks: [String: Task<Void, Error>] = [:]
    private var saveTaskIDs: [String: UUID] = [:]
    private var localContentGenerations: [String: UInt64] = [:]
    private var contentSynchronizationTasks: [String: Task<Void, Never>] = [:]
    private var activeContentSynchronizationPriorities: [String: CloudStorageContentSynchronizationPriority] = [:]
    private var contentSynchronizationQueue: [String: ContentSynchronizationRequest] = [:]
    private var nextContentSynchronizationSequence = 0
    private var retryScheduledDocumentIDs: Set<String> = []
    private var metadataMutationIDs: [MetadataMutationKey: UUID] = [:]

    private let maximumConcurrentBackgroundContentSynchronizations = 2
    private let maximumConcurrentContentSynchronizations = 6

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.rootURL = (supportURL ?? fileManager.temporaryDirectory)
            .appending(path: "CloudStorage", directoryHint: .isDirectory)
            .appending(path: "v1", directoryHint: .isDirectory)
    }

    // MARK: - Metadata Index

    func items(
        in location: CloudStorageLocation,
        parentID: CloudStorageItemID
    ) -> [CloudStorageItem]? {
        guard let items = itemsByLocationID[location.id] else { return nil }
        return items.values
            .filter { $0.parentID == parentID && Self.shouldDisplay($0) }
    }

    func item(for reference: CloudStorageDocumentReference) -> CloudStorageItem? {
        return itemsByLocationID[reference.locationID]?[reference.itemID]
    }

    func item(for folder: CloudStorageFolderReference) -> CloudStorageItem? {
        itemsByLocationID[folder.location.id]?[folder.itemID]
    }

    func capabilities(
        for reference: CloudStorageDocumentReference
    ) -> CloudStorageItemCapabilities {
        item(for: reference)?.effectiveCapabilities ?? .writableFile
    }

    func capabilities(
        for folder: CloudStorageFolderReference
    ) -> CloudStorageItemCapabilities {
        if folder.isLocationRoot {
            return folder.location.effectiveRootCapabilities
        }
        return item(for: folder)?.effectiveCapabilities ?? .writableFolder
    }

    func remoteURL(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> URL {
        try await remoteURL(
            locationID: reference.locationID,
            itemID: reference.itemID,
            connections: connections
        )
    }

    func remoteURL(
        for folder: CloudStorageFolderReference,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> URL {
        try await remoteURL(
            locationID: folder.location.id,
            itemID: folder.itemID,
            connections: connections
        )
    }

    private func remoteURL(
        locationID: UUID,
        itemID: CloudStorageItemID,
        connections: CloudStorageConnectionStore?
    ) async throws -> URL {
        let connections = connections ?? .shared
        guard let location = connections.locations.first(where: { $0.id == locationID }) else {
            throw CloudStorageError.itemNotFound(itemID)
        }
        ensureLocationStateLoaded(locationID)
        if let remoteURL = itemsByLocationID[locationID]?[itemID]?.remoteURL {
            return remoteURL
        }

        let session = try await resolvedSession(for: location, connections: connections)
        let item = try await session.item(for: itemID)
        upsert(item, in: locationID)
        return try await session.remoteURL(for: item)
    }

    func latestReference(
        for reference: CloudStorageDocumentReference
    ) -> CloudStorageDocumentReference {
        guard let item = item(for: reference) else { return reference }
        return CloudStorageDocumentReference(
            locationID: reference.locationID,
            providerID: reference.providerID,
            accountID: reference.accountID,
            itemID: reference.itemID,
            lastKnownName: item.name,
            lastKnownModifiedAt: item.modifiedAt
        )
    }

    func displayName(for reference: CloudStorageDocumentReference) -> String {
        item(for: reference)?.name ?? reference.lastKnownName
    }

    func modifiedAt(for reference: CloudStorageDocumentReference) -> Date? {
        item(for: reference)?.modifiedAt ?? reference.lastKnownModifiedAt
    }

    func metadataRevision(for locationID: UUID) -> Int {
        metadataRevisionsByLocationID[locationID, default: 0]
    }

    func folderPath(for folder: CloudStorageFolderReference) -> [CloudStorageFolderReference] {
        guard !folder.isLocationRoot else { return [folder] }

        let items = itemsByLocationID[folder.location.id] ?? [:]
        var path = [folder]
        var parentID = folder.parentID
        var visited = Set<CloudStorageItemID>([folder.itemID])

        while let currentParentID = parentID,
              currentParentID != folder.location.rootItemID,
              !visited.contains(currentParentID),
              let parent = items[currentParentID],
              parent.kind == .folder {
            visited.insert(currentParentID)
            path.append(CloudStorageFolderReference(location: folder.location, item: parent))
            parentID = parent.parentID
        }

        path.append(.root(of: folder.location))
        return path.reversed()
    }

    func parentFolder(
        for document: CloudStorageDocumentReference
    ) -> CloudStorageFolderReference? {
        guard let location = CloudStorageConnectionStore.shared.locations.first(where: {
            $0.id == document.locationID
        }),
        let item = itemsByLocationID[document.locationID]?[document.itemID],
        let parentID = item.parentID else {
            return nil
        }

        if parentID == location.rootItemID {
            return .root(of: location)
        }
        guard let parent = itemsByLocationID[document.locationID]?[parentID],
              parent.kind == .folder else {
            return nil
        }
        return CloudStorageFolderReference(location: location, item: parent)
    }

    func isRefreshing(_ location: CloudStorageLocation) -> Bool {
        refreshingLocationIDs.contains(location.id)
    }

    func errorMessage(for location: CloudStorageLocation) -> String? {
        errorsByLocationID[location.id]
    }

    // MARK: - Synchronization State

    func folderSyncStates(
        in location: CloudStorageLocation
    ) -> [CloudStorageItemID: CloudStorageFolderSyncState] {
        guard let items = itemsByLocationID[location.id] else { return [:] }

        var parentIDByFolderID: [CloudStorageItemID: CloudStorageItemID] = [:]
        var states: [CloudStorageItemID: CloudStorageFolderSyncState] = [
            location.rootItemID: .idle
        ]
        for item in items.values where item.kind == .folder {
            states[item.id] = .idle
            if let parentID = item.parentID {
                parentIDByFolderID[item.id] = parentID
            }
        }

        for item in items.values where item.kind == .file {
            guard let folderID = item.parentID else { continue }
            let reference = CloudStorageDocumentReference(
                locationID: location.id,
                providerID: location.providerID,
                accountID: location.accountID,
                itemID: item.id,
                lastKnownName: item.name,
                lastKnownModifiedAt: item.modifiedAt
            )
            let documentState = syncState(for: reference)
            let folderState: CloudStorageFolderSyncState
            if documentState.isActivelySynchronizing {
                folderState = .synchronizing
            } else if documentState == .queued {
                folderState = .queued
            } else {
                continue
            }

            propagateFolderState(
                folderState,
                from: folderID,
                rootID: location.rootItemID,
                parentIDByFolderID: parentIDByFolderID,
                states: &states
            )
        }

        for folderID in processingFolderIDsByLocationID[location.id] ?? [] {
            propagateFolderState(
                .synchronizing,
                from: folderID,
                rootID: location.rootItemID,
                parentIDByFolderID: parentIDByFolderID,
                states: &states
            )
        }
        return states
    }

    func syncState(
        for reference: CloudStorageDocumentReference
    ) -> CloudStorageDocumentSyncState {
        if let state = syncStatesByDocumentID[reference.id] {
            return state
        }

        guard let persistedState = persistedStates[reference.locationID] else {
            return .local
        }
        if persistedState.dirtyItemIDs.contains(reference.itemID) {
            return .queued
        }

        let cacheExists = fileManager.fileExists(
            atPath: cachedDocumentURL(for: reference).path
        )
        guard cacheExists else {
            return .queued
        }

        let cachedRevision = persistedState.cachedRevisions[reference.itemID]
        let indexedRevision = persistedState.items.first(where: {
            $0.id == reference.itemID
        })?.revision
        if cachedRevision != nil, cachedRevision == indexedRevision {
            return .synced(lastVerifiedAt: .distantPast)
        }
        return .queued
    }

    // MARK: - Metadata Refresh

    @discardableResult
    func refresh(
        _ location: CloudStorageLocation,
        connections: CloudStorageConnectionStore,
        force: Bool = false
    ) async -> Bool {
        ensureLocationStateLoaded(location.id)
        guard force || itemsByLocationID[location.id] == nil else { return true }

        if let refreshTask = refreshTasksByLocationID[location.id] {
            return await refreshTask.value
        }

        let refreshTaskID = UUID()
        let refreshTask = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performRefresh(location, connections: connections)
        }
        refreshTasksByLocationID[location.id] = refreshTask
        refreshTaskIDsByLocationID[location.id] = refreshTaskID
        let succeeded = await refreshTask.value

        if refreshTaskIDsByLocationID[location.id] == refreshTaskID {
            refreshTasksByLocationID[location.id] = nil
            refreshTaskIDsByLocationID[location.id] = nil
        }
        return succeeded
    }

    private func performRefresh(
        _ location: CloudStorageLocation,
        connections: CloudStorageConnectionStore
    ) async -> Bool {

        refreshingLocationIDs.insert(location.id)
        errorsByLocationID[location.id] = nil
        defer { refreshingLocationIDs.remove(location.id) }

        do {
            let session = try await resolvedSession(for: location, connections: connections)
            var state = persistedStates[location.id] ?? Self.emptyState

            if session.capabilities.contains(.deltaChanges) {
                do {
                    state = try await refreshedDeltaState(
                        state,
                        location: location,
                        session: session
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch where Self.isCancellationError(error) {
                    throw CancellationError()
                } catch CloudStorageError.changeTrackingResetRequired {
                    logger.info(
                        "Cloud change cursor requires reset for \(location.displayName); rebuilding its remote index"
                    )
                    state = try await rebuiltStateAfterChangeTrackingReset(
                        state,
                        location: location,
                        session: session
                    )
                } catch where state.cursor == nil {
                    logger.warning(
                        "Initial delta enumeration failed for \(location.displayName); falling back to recursive listing: \(error)"
                    )
                    state = try await recursivelyEnumeratedState(
                        preservingCacheFrom: state,
                        location: location,
                        session: session
                    )
                }
            } else {
                state = try await recursivelyEnumeratedState(
                    preservingCacheFrom: state,
                    location: location,
                    session: session
                )
            }

            apply(state, to: location.id)
            try persist(state, for: location.id)
            connections.clearAuthenticationRequirement(for: location)
            return true
        } catch is CancellationError {
            return false
        } catch {
            if Self.isCancellationError(error) {
                return false
            }
            connections.recordAccessFailure(error, for: location)
            errorsByLocationID[location.id] = error.localizedDescription
            logger.error("Failed to refresh cloud location \(location.displayName): \(error)")
            return false
        }
    }

    // MARK: - Content Synchronization

    func content(
        for reference: CloudStorageDocumentReference,
        checkingRemoteRevision: Bool
    ) async throws -> Data {
        try await content(
            for: reference,
            connections: .shared,
            checkingRemoteRevision: checkingRemoteRevision
        )
    }

    /// Returns the device-local document snapshot without resolving an
    /// account, creating a provider session, or performing network I/O.
    func cachedContent(for reference: CloudStorageDocumentReference) throws -> Data? {
        ensureLocationStateLoaded(reference.locationID)
        let cacheURL = cachedDocumentURL(for: reference)
        guard fileManager.fileExists(atPath: cacheURL.path) else { return nil }
        return try Data(contentsOf: cacheURL)
    }

    /// Starts provider synchronization without making the caller wait for
    /// authentication, metadata checks, downloads, or dirty upload retries.
    func scheduleContentSynchronization(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore? = nil,
        priority: CloudStorageContentSynchronizationPriority = .background
    ) {
        let synchronizationKey = reference.id
        guard contentSynchronizationTasks[synchronizationKey] == nil else { return }

        if var request = contentSynchronizationQueue[synchronizationKey] {
            guard priority > request.priority else { return }
            request.priority = priority
            contentSynchronizationQueue[synchronizationKey] = request
            processContentSynchronizationQueue()
            return
        }

        let connections = connections ?? .shared
        contentSynchronizationQueue[synchronizationKey] = ContentSynchronizationRequest(
            reference: reference,
            connections: connections,
            priority: priority,
            sequence: nextContentSynchronizationSequence
        )
        nextContentSynchronizationSequence &+= 1
        setSyncState(.queued, for: reference)
        processContentSynchronizationQueue()
    }

    private func processContentSynchronizationQueue() {
        while contentSynchronizationTasks.count < maximumConcurrentContentSynchronizations {
            let activeBackgroundCount = activeContentSynchronizationPriorities.values.reduce(into: 0) {
                if $1 == .background { $0 += 1 }
            }
            let nextRequest = contentSynchronizationQueue.values
                .filter { saveTasks[$0.reference.id] == nil }
                .sorted { lhs, rhs in
                    if lhs.priority != rhs.priority {
                        return lhs.priority > rhs.priority
                    }
                    return lhs.sequence < rhs.sequence
                }
                .first { request in
                    request.priority == .userInitiated
                        || activeBackgroundCount < maximumConcurrentBackgroundContentSynchronizations
                }

            guard let nextRequest else { return }
            let synchronizationKey = nextRequest.reference.id
            contentSynchronizationQueue.removeValue(forKey: synchronizationKey)
            activeContentSynchronizationPriorities[synchronizationKey] = nextRequest.priority

            let taskPriority: TaskPriority = nextRequest.priority == .userInitiated
                ? .userInitiated
                : .background
            contentSynchronizationTasks[synchronizationKey] = Task(
                priority: taskPriority
            ) { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    self.contentSynchronizationTasks[synchronizationKey] = nil
                    self.activeContentSynchronizationPriorities[synchronizationKey] = nil
                    self.processContentSynchronizationQueue()
                }
                do {
                    if let candidate = try await self.remoteContentCandidate(
                        for: nextRequest.reference,
                        connections: nextRequest.connections
                    ) {
                        _ = try self.installRemoteContentCandidate(
                            candidate,
                            for: nextRequest.reference
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.logger.warning(
                        "Background cloud document synchronization failed: \(self.displayName(for: nextRequest.reference)), error=\(error)"
                    )
                }
            }
        }
    }

    /// Persists a document to the device cache and marks it for provider
    /// upload without waiting for network availability.
    func saveToLocalCache(
        _ data: Data,
        for reference: CloudStorageDocumentReference
    ) throws {
        _ = try stageLocalSave(data, for: reference)
        setSyncState(.queued, for: reference)
    }

    /// Reconciles the provider index with the device cache. Background scans
    /// eventually mirror remote documents locally; visible folders can raise
    /// their pending work to user-initiated priority.
    func scheduleDocumentSynchronizations(
        in location: CloudStorageLocation,
        parentID: CloudStorageItemID? = nil,
        excludingDocumentIDs: Set<String>,
        connections: CloudStorageConnectionStore,
        priority: CloudStorageContentSynchronizationPriority
    ) {
        ensureLocationStateLoaded(location.id)
        let state = persistedStates[location.id] ?? Self.emptyState

        for item in state.items where item.kind == .file
            && item.effectiveCapabilities.contains(.download)
            && (parentID == nil || item.parentID == parentID) {
            let reference = CloudStorageDocumentReference(
                locationID: location.id,
                providerID: location.providerID,
                accountID: location.accountID,
                itemID: item.id,
                lastKnownName: item.name,
                lastKnownModifiedAt: item.modifiedAt
            )
            guard !excludingDocumentIDs.contains(reference.id) else { continue }

            let cacheExists = fileManager.fileExists(
                atPath: cachedDocumentURL(for: reference).path
            )

            if state.dirtyItemIDs.contains(item.id) {
                scheduleContentSynchronization(
                    for: reference,
                    connections: connections,
                    priority: priority
                )
                continue
            }

            let cachedRevision = state.cachedRevisions[item.id]
            if !cacheExists || cachedRevision != item.revision {
                scheduleContentSynchronization(
                    for: reference,
                    connections: connections,
                    priority: priority
                )
            } else if syncStatesByDocumentID[reference.id] == .local {
                setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
            }
        }
    }

    /// Downloads a changed remote revision into temporary storage. The local
    /// cache remains untouched until `installRemoteContentCandidate` succeeds.
    func remoteContentCandidate(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> RemoteContentCandidate? {
        let connections = connections ?? .shared
        setSyncState(.checking, for: reference)

        do {
            guard let location = connections.locations.first(where: { $0.id == reference.locationID }) else {
                throw CloudStorageError.itemNotFound(reference.itemID)
            }
            ensureLocationStateLoaded(location.id)
            let state = persistedStates[location.id] ?? Self.emptyState

            if state.dirtyItemIDs.contains(reference.itemID) {
                if case .conflict = syncStatesByDocumentID[reference.id] {
                    return nil
                }
                setSyncState(.queued, for: reference)
                if let data = try cachedContent(for: reference) {
                    retryDirtyUploadIfNeeded(
                        data,
                        reference: reference,
                        connections: connections
                    )
                }
                return nil
            }

            let session = try await resolvedSession(for: location, connections: connections)
            let remoteItem = try await session.item(for: reference.itemID)
            try Self.require(
                .download,
                for: remoteItem,
                operation: .download
            )
            let cacheURL = cachedDocumentURL(for: reference)
            if fileManager.fileExists(atPath: cacheURL.path),
               state.cachedRevisions[reference.itemID] == remoteItem.revision {
                setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
                return nil
            }

            setSyncState(.downloading(progress: nil), for: reference)
            let stagingURL = fileManager.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension(
                    (displayName(for: reference) as NSString).pathExtension
                )
            defer { try? fileManager.removeItem(at: stagingURL) }
            let downloadedItem = try await session.downloadFile(reference.itemID, to: stagingURL)
            return RemoteContentCandidate(
                data: try Data(contentsOf: stagingURL),
                item: downloadedItem
            )
        } catch is CancellationError {
            setSyncState(.local, for: reference)
            throw CancellationError()
        } catch {
            if Self.isCancellationError(error) {
                setSyncState(.local, for: reference)
                throw CancellationError()
            }
            setFailure(error, operation: .download, for: reference)
            throw error
        }
    }

    /// Installs a previously downloaded candidate only while the local cache
    /// is still clean. Returns false when a local save won the race.
    func installRemoteContentCandidate(
        _ candidate: RemoteContentCandidate,
        for reference: CloudStorageDocumentReference
    ) throws -> Bool {
        ensureLocationStateLoaded(reference.locationID)
        var state = persistedStates[reference.locationID] ?? Self.emptyState
        guard !state.dirtyItemIDs.contains(reference.itemID) else {
            setSyncState(.queued, for: reference)
            return false
        }

        let cacheURL = cachedDocumentURL(for: reference)
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try candidate.data.write(to: cacheURL, options: .atomic)
        state.items.removeAll { $0.id == reference.itemID }
        state.items.append(candidate.item)
        if let revision = candidate.item.revision {
            state.cachedRevisions[reference.itemID] = revision
        } else {
            state.cachedRevisions.removeValue(forKey: reference.itemID)
        }
        apply(state, to: reference.locationID)
        try persist(state, for: reference.locationID)
        setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
        notifyDocumentContentDidChange(reference)
        return true
    }

    func discardCachedContent(for reference: CloudStorageDocumentReference) throws {
        ensureLocationStateLoaded(reference.locationID)
        var state = persistedStates[reference.locationID] ?? Self.emptyState
        try? fileManager.removeItem(at: cachedDocumentURL(for: reference))
        state.cachedRevisions.removeValue(forKey: reference.itemID)
        apply(state, to: reference.locationID)
        try persist(state, for: reference.locationID)
        syncStatesByDocumentID.removeValue(forKey: reference.id)
    }

    func content(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore,
        checkingRemoteRevision: Bool
    ) async throws -> Data {
        do {
            return try await loadContent(
                for: reference,
                connections: connections,
                checkingRemoteRevision: checkingRemoteRevision
            )
        } catch is CancellationError {
            setSyncState(.local, for: reference)
            throw CancellationError()
        } catch {
            if Self.isCancellationError(error) {
                setSyncState(.local, for: reference)
                throw CancellationError()
            }
            setFailure(error, operation: .download, for: reference)
            throw error
        }
    }

    private func loadContent(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore,
        checkingRemoteRevision: Bool
    ) async throws -> Data {
        guard connections.locations.contains(where: { $0.id == reference.locationID }) else {
            throw CloudStorageError.itemNotFound(reference.itemID)
        }
        ensureLocationStateLoaded(reference.locationID)
        let state = persistedStates[reference.locationID] ?? Self.emptyState
        let cacheURL = cachedDocumentURL(for: reference)

        if state.dirtyItemIDs.contains(reference.itemID),
           fileManager.fileExists(atPath: cacheURL.path) {
            if case .conflict = syncStatesByDocumentID[reference.id] {
                return try Data(contentsOf: cacheURL)
            }
            setSyncState(.queued, for: reference)
            let data = try Data(contentsOf: cacheURL)
            retryDirtyUploadIfNeeded(
                data,
                reference: reference,
                connections: connections
            )
            return data
        }

        if !checkingRemoteRevision,
           fileManager.fileExists(atPath: cacheURL.path),
           let indexedItem = state.items.first(where: { $0.id == reference.itemID }),
           state.cachedRevisions[reference.itemID] == indexedItem.revision {
            setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
            return try Data(contentsOf: cacheURL)
        }

        if let candidate = try await remoteContentCandidate(
            for: reference,
            connections: connections
        ) {
            _ = try installRemoteContentCandidate(candidate, for: reference)
        }

        guard fileManager.fileExists(atPath: cacheURL.path) else {
            throw CloudStorageError.itemNotFound(reference.itemID)
        }
        return try Data(contentsOf: cacheURL)
    }

    private func retryDirtyUploadIfNeeded(
        _ data: Data,
        reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore
    ) {
        guard saveTasks[reference.id] == nil,
              retryScheduledDocumentIDs.insert(reference.id).inserted else { return }
        setSyncState(.queued, for: reference)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.retryScheduledDocumentIDs.remove(reference.id) }
            do {
                try await self.uploadCachedContent(
                    data,
                    for: reference,
                    connections: connections
                )
                self.logger.debug(
                    "Retried dirty cloud document upload: \(self.displayName(for: reference))"
                )
            } catch {
                self.logger.warning(
                    "Dirty cloud document remains queued after upload retry: \(self.displayName(for: reference)), error=\(error)"
                )
            }
        }
    }

    func save(
        _ data: Data,
        to reference: CloudStorageDocumentReference
    ) async throws {
        try await save(data, to: reference, connections: .shared)
    }

    func save(
        _ data: Data,
        to reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore
    ) async throws {
        let localGeneration = try stageLocalSave(data, for: reference)
        try await enqueueSave(
            data,
            to: reference,
            connections: connections,
            localGeneration: localGeneration
        )
    }

    private func uploadCachedContent(
        _ data: Data,
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore
    ) async throws {
        ensureLocationStateLoaded(reference.locationID)
        let localGeneration = localContentGenerations[reference.id, default: 0]
        try await enqueueSave(
            data,
            to: reference,
            connections: connections,
            localGeneration: localGeneration
        )
    }

    private func enqueueSave(
        _ data: Data,
        to reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore,
        localGeneration: UInt64
    ) async throws {
        let saveKey = reference.id
        let previousTask = saveTasks[saveKey]
        let taskID = UUID()
        let task = Task { @MainActor in
            if let previousTask {
                _ = try? await previousTask.value
            }
            self.setSyncState(.uploading(progress: nil), for: reference)
            do {
                let uploadedLatestContent = try await self.performSave(
                    data,
                    to: reference,
                    connections: connections,
                    localGeneration: localGeneration
                )
                if self.saveTaskIDs[saveKey] == taskID {
                    self.setSyncState(
                        uploadedLatestContent
                            ? .synced(lastVerifiedAt: Date())
                            : .queued,
                        for: reference
                    )
                }
            } catch {
                if self.saveTaskIDs[saveKey] == taskID {
                    self.setFailure(error, operation: .updateFile, for: reference)
                }
                throw error
            }
        }
        setSyncState(previousTask == nil ? .uploading(progress: nil) : .queued, for: reference)
        saveTasks[saveKey] = task
        saveTaskIDs[saveKey] = taskID
        defer {
            if saveTaskIDs[saveKey] == taskID {
                saveTasks[saveKey] = nil
                saveTaskIDs[saveKey] = nil
                processContentSynchronizationQueue()
            }
        }
        try await task.value
    }

    // MARK: - Item Mutations

    func createDocument(
        in folder: CloudStorageFolderReference,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> CloudStorageDocumentReference {
        let connections = connections ?? .shared
        ensureLocationStateLoaded(folder.location.id)
        try Self.require(
            .createChildren,
            in: capabilities(for: folder),
            operation: .createFile
        )
        guard let content = ExcalidrawFile().content else {
            throw CloudStorageError.invalidProviderResponse(
                "Unable to create an empty Excalidraw document."
            )
        }

        let name = uniqueName(
            baseName: String(localizable: .generalUntitled),
            pathExtension: "excalidraw",
            in: folder.itemID,
            locationID: folder.location.id
        )
        let stagingURL = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("excalidraw")
        defer { try? fileManager.removeItem(at: stagingURL) }
        try content.write(to: stagingURL, options: .atomic)

        let session = try await resolvedSession(
            for: folder.location,
            connections: connections
        )
        let item = try await session.createFile(
            named: name,
            in: folder.itemID,
            contentsAt: stagingURL,
            condition: .ifAbsent
        )
        let reference = CloudStorageDocumentReference(
            locationID: folder.location.id,
            providerID: folder.location.providerID,
            accountID: folder.location.accountID,
            itemID: item.id,
            lastKnownName: item.name,
            lastKnownModifiedAt: item.modifiedAt
        )

        var state = persistedStates[folder.location.id] ?? Self.emptyState
        state.items.removeAll { $0.id == item.id }
        state.items.append(item)
        if let revision = item.revision {
            state.cachedRevisions[item.id] = revision
        }
        let cacheURL = cachedDocumentURL(for: reference)
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: cacheURL, options: .atomic)
        apply(state, to: folder.location.id)
        try persist(state, for: folder.location.id)
        setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
        return reference
    }

    func duplicateDocuments(
        _ references: Set<CloudStorageDocumentReference>,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> [CloudStorageDocumentReference] {
        let connections = connections ?? .shared
        var duplicates: [CloudStorageDocumentReference] = []

        for reference in references {
            guard let location = connections.locations.first(where: {
                $0.id == reference.locationID
            }) else {
                throw CloudStorageError.itemNotFound(reference.itemID)
            }
            ensureLocationStateLoaded(location.id)
            guard let sourceItem = itemsByLocationID[location.id]?[reference.itemID],
                  let parentID = sourceItem.parentID else {
                throw CloudStorageError.itemNotFound(reference.itemID)
            }
            try Self.require(
                .download,
                for: sourceItem,
                operation: .download
            )
            if let parent = itemsByLocationID[location.id]?[parentID] {
                try Self.require(
                    .createChildren,
                    for: parent,
                    operation: .createFile
                )
            }

            let data = try await content(
                for: reference,
                connections: connections,
                checkingRemoteRevision: false
            )
            let sourceName = sourceItem.name as NSString
            let pathExtension = sourceName.pathExtension
            let baseName = sourceName.deletingPathExtension
            let name = uniqueName(
                baseName: baseName,
                pathExtension: pathExtension,
                in: parentID,
                locationID: location.id
            )
            let stagingURL = fileManager.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension(pathExtension)
            defer { try? fileManager.removeItem(at: stagingURL) }
            try data.write(to: stagingURL, options: .atomic)

            let session = try await resolvedSession(
                for: location,
                connections: connections
            )
            let item = try await session.createFile(
                named: name,
                in: parentID,
                contentsAt: stagingURL,
                condition: .ifAbsent
            )
            let duplicate = CloudStorageDocumentReference(
                locationID: location.id,
                providerID: location.providerID,
                accountID: location.accountID,
                itemID: item.id,
                lastKnownName: item.name,
                lastKnownModifiedAt: item.modifiedAt
            )

            var state = persistedStates[location.id] ?? Self.emptyState
            state.items.removeAll { $0.id == item.id }
            state.items.append(item)
            if let revision = item.revision {
                state.cachedRevisions[item.id] = revision
            }
            let cacheURL = cachedDocumentURL(for: duplicate)
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
            apply(state, to: location.id)
            try persist(state, for: location.id)
            setSyncState(.synced(lastVerifiedAt: Date()), for: duplicate)
            duplicates.append(duplicate)
        }

        return duplicates
    }

    func createFolder(
        named name: String,
        in folder: CloudStorageFolderReference,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> CloudStorageFolderReference {
        let connections = connections ?? .shared
        ensureLocationStateLoaded(folder.location.id)
        try Self.require(
            .createChildren,
            in: capabilities(for: folder),
            operation: .createFolder
        )
        let session = try await resolvedSession(
            for: folder.location,
            connections: connections
        )
        let item = try await session.createFolder(
            named: name,
            in: folder.itemID
        )
        upsert(item, in: folder.location.id)
        return CloudStorageFolderReference(location: folder.location, item: item)
    }

    func availableFolderName(in folder: CloudStorageFolderReference) -> String {
        ensureLocationStateLoaded(folder.location.id)
        let baseName = String(localizable: .generalNewFolderName)
        let names = Set(
            (itemsByLocationID[folder.location.id] ?? [:]).values
                .filter { $0.parentID == folder.itemID }
                .map { $0.name.lowercased() }
        )
        var index = 0
        while true {
            let candidate = index == 0 ? baseName : "\(baseName) \(index)"
            if !names.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }
    }

    func renameDocument(
        _ reference: CloudStorageDocumentReference,
        to displayName: String,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> CloudStorageDocumentReference {
        let connections = connections ?? .shared
        guard let location = connections.locations.first(where: { $0.id == reference.locationID }) else {
            throw CloudStorageError.itemNotFound(reference.itemID)
        }
        ensureLocationStateLoaded(location.id)
        guard let item = itemsByLocationID[location.id]?[reference.itemID] else {
            throw CloudStorageError.itemNotFound(reference.itemID)
        }
        try Self.require(.rename, for: item, operation: .moveItem)
        let name = Self.fileName(displayName, preservingExtensionsFrom: item.name)
        if name == item.name {
            return reference
        }
        let hasConflictingSibling = (itemsByLocationID[location.id] ?? [:]).values.contains {
            $0.id != item.id
                && $0.parentID == item.parentID
                && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if hasConflictingSibling {
            throw CloudStorageError.itemNameAlreadyExists(name)
        }
        let mutationID = beginOptimisticRename(
            item,
            to: name,
            locationID: location.id
        )
        setSyncState(.processing, for: reference)
#if DEBUG
        logger.debug(
            "Renaming cloud document itemID=\(item.id.rawValue) name=\(item.name) -> \(name)"
        )
#endif
        let updatedItem: CloudStorageItem
        do {
            let session = try await resolvedSession(
                for: location,
                connections: connections
            )
            updatedItem = try await session.moveItem(
                item.id,
                to: nil,
                newName: name
            )
        } catch {
            rollbackOptimisticRename(
                item,
                mutationID: mutationID,
                locationID: location.id
            )
            setFailure(error, operation: .moveItem, for: reference)
            logger.error(
                "Failed to rename cloud document itemID=\(item.id.rawValue) name=\(item.name) -> \(name): \(error)"
            )
            throw error
        }
#if DEBUG
        logger.debug(
            "Renamed cloud document itemID=\(updatedItem.id.rawValue) providerName=\(updatedItem.name)"
        )
#endif
        let didCompleteCurrentMutation = completeOptimisticRename(
            updatedItem,
            mutationID: mutationID,
            locationID: location.id
        )
        if didCompleteCurrentMutation {
            setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
        }
        let latestItem = itemsByLocationID[location.id]?[reference.itemID] ?? updatedItem
        return CloudStorageDocumentReference(
            locationID: location.id,
            providerID: location.providerID,
            accountID: location.accountID,
            itemID: latestItem.id,
            lastKnownName: latestItem.name,
            lastKnownModifiedAt: latestItem.modifiedAt
        )
    }

    func renameFolder(
        _ folder: CloudStorageFolderReference,
        to name: String,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> CloudStorageFolderReference {
        let connections = connections ?? .shared
        guard folder.parentID != nil else {
            throw CloudStorageError.unsupportedOperation(.moveItem)
        }
        ensureLocationStateLoaded(folder.location.id)
        guard let item = itemsByLocationID[folder.location.id]?[folder.itemID] else {
            throw CloudStorageError.itemNotFound(folder.itemID)
        }
        try Self.require(.rename, for: item, operation: .moveItem)
        if name == item.name {
            return folder
        }
        let hasConflictingSibling = (itemsByLocationID[folder.location.id] ?? [:]).values.contains {
            $0.id != item.id
                && $0.parentID == item.parentID
                && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        if hasConflictingSibling {
            throw CloudStorageError.itemNameAlreadyExists(name)
        }
        let mutationID = beginOptimisticRename(
            item,
            to: name,
            locationID: folder.location.id
        )
        let updatedItem: CloudStorageItem
        do {
            let session = try await resolvedSession(
                for: folder.location,
                connections: connections
            )
            updatedItem = try await session.moveItem(
                folder.itemID,
                to: nil,
                newName: name
            )
        } catch {
            rollbackOptimisticRename(
                item,
                mutationID: mutationID,
                locationID: folder.location.id
            )
            throw error
        }
        _ = completeOptimisticRename(
            updatedItem,
            mutationID: mutationID,
            locationID: folder.location.id
        )
        let latestItem = itemsByLocationID[folder.location.id]?[folder.itemID] ?? updatedItem
        return CloudStorageFolderReference(location: folder.location, item: latestItem)
    }

    func deleteDocuments(
        _ references: Set<CloudStorageDocumentReference>,
        connections: CloudStorageConnectionStore? = nil
    ) async throws {
        let connections = connections ?? .shared
        for reference in references {
            try await deleteItem(
                reference.itemID,
                locationID: reference.locationID,
                cacheReference: reference,
                connections: connections
            )
        }
    }

    func deleteFolder(
        _ folder: CloudStorageFolderReference,
        connections: CloudStorageConnectionStore? = nil
    ) async throws {
        guard processingFolderIDsByLocationID[folder.location.id]?.contains(folder.itemID) != true else {
            return
        }
        let connections = connections ?? .shared
        processingFolderIDsByLocationID[folder.location.id, default: []].insert(folder.itemID)
        defer {
            processingFolderIDsByLocationID[folder.location.id]?.remove(folder.itemID)
            if processingFolderIDsByLocationID[folder.location.id]?.isEmpty == true {
                processingFolderIDsByLocationID.removeValue(forKey: folder.location.id)
            }
        }
        try await deleteItem(
            folder.itemID,
            locationID: folder.location.id,
            cacheReference: nil,
            connections: connections
        )
    }

    func removeCachedState(for locationID: UUID) {
        refreshTasksByLocationID.removeValue(forKey: locationID)?.cancel()
        refreshTaskIDsByLocationID.removeValue(forKey: locationID)
        let locationMarker = ":\(locationID.uuidString):"
        for (key, task) in contentSynchronizationTasks where key.contains(locationMarker) {
            task.cancel()
        }
        activeContentSynchronizationPriorities = activeContentSynchronizationPriorities.filter {
            !$0.key.contains(locationMarker)
        }
        contentSynchronizationQueue = contentSynchronizationQueue.filter {
            !$0.key.contains(locationMarker)
        }
        loadedLocationIDs.remove(locationID)
        persistedStates.removeValue(forKey: locationID)
        itemsByLocationID.removeValue(forKey: locationID)
        metadataRevisionsByLocationID.removeValue(forKey: locationID)
        sessionsByLocationID.removeValue(forKey: locationID)
        errorsByLocationID.removeValue(forKey: locationID)
        processingFolderIDsByLocationID.removeValue(forKey: locationID)
        syncStatesByDocumentID = syncStatesByDocumentID.filter {
            !$0.key.contains(locationMarker)
        }
        try? fileManager.removeItem(at: locationDirectoryURL(locationID))
    }

    // MARK: - Save Pipeline

    private func performSave(
        _ data: Data,
        to reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore,
        localGeneration: UInt64
    ) async throws -> Bool {
        guard let location = connections.locations.first(where: { $0.id == reference.locationID }) else {
            throw CloudStorageError.itemNotFound(reference.itemID)
        }
        ensureLocationStateLoaded(location.id)
        var state = persistedStates[location.id] ?? Self.emptyState
        if let item = state.items.first(where: { $0.id == reference.itemID }) {
            try Self.require(
                .updateContent,
                for: item,
                operation: .updateFile
            )
        }
        let uploadURL = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(
                (displayName(for: reference) as NSString).pathExtension
            )
        defer { try? fileManager.removeItem(at: uploadURL) }
        try fileManager.createDirectory(
            at: uploadURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: uploadURL, options: .atomic)

        let session = try await resolvedSession(for: location, connections: connections)
        var revision = state.cachedRevisions[reference.itemID]
            ?? state.items.first(where: { $0.id == reference.itemID })?.revision
        if revision == nil {
            let remoteItem = try await session.item(for: reference.itemID)
            try Self.require(
                .updateContent,
                for: remoteItem,
                operation: .updateFile
            )
            state.items.removeAll { $0.id == reference.itemID }
            state.items.append(remoteItem)
            revision = remoteItem.revision
        }
        let condition = revision.map(CloudStorageWriteCondition.ifUnmodified)
            ?? .unconditional
        let updatedItem = try await session.updateFile(
            reference.itemID,
            contentsAt: uploadURL,
            condition: condition
        )

        state = persistedStates[location.id] ?? state
        state.items.removeAll { $0.id == reference.itemID }
        state.items.append(updatedItem)
        if let revision = updatedItem.revision {
            state.cachedRevisions[reference.itemID] = revision
        } else {
            state.cachedRevisions.removeValue(forKey: reference.itemID)
        }
        let uploadedLatestContent = localContentGenerations[reference.id] == localGeneration
        if uploadedLatestContent {
            state.dirtyItemIDs.remove(reference.itemID)
        }
        apply(state, to: location.id)
        try persist(state, for: location.id)
        notifyDocumentContentDidChange(reference)
        logger.debug("Uploaded cloud document \(displayName(for: reference))")
        return uploadedLatestContent
    }

    @discardableResult
    private func stageLocalSave(
        _ data: Data,
        for reference: CloudStorageDocumentReference
    ) throws -> UInt64 {
        ensureLocationStateLoaded(reference.locationID)
        var state = persistedStates[reference.locationID] ?? Self.emptyState
        let cacheURL = cachedDocumentURL(for: reference)
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)
        state.dirtyItemIDs.insert(reference.itemID)
        apply(state, to: reference.locationID)
        try persist(state, for: reference.locationID)

        let generation = localContentGenerations[reference.id, default: 0] &+ 1
        localContentGenerations[reference.id] = generation
        notifyDocumentContentDidChange(reference)
        return generation
    }

    private func deleteItem(
        _ itemID: CloudStorageItemID,
        locationID: UUID,
        cacheReference: CloudStorageDocumentReference?,
        connections: CloudStorageConnectionStore
    ) async throws {
        guard let location = connections.locations.first(where: { $0.id == locationID }) else {
            throw CloudStorageError.itemNotFound(itemID)
        }
        ensureLocationStateLoaded(locationID)
        var state = persistedStates[locationID] ?? Self.emptyState
        if let item = state.items.first(where: { $0.id == itemID }) {
            try Self.require(.delete, for: item, operation: .deleteItem)
        }
        let revision = state.items.first(where: { $0.id == itemID })?.revision
        let condition = revision.map(CloudStorageWriteCondition.ifUnmodified)
            ?? .unconditional
        if let cacheReference {
            setSyncState(.processing, for: cacheReference)
        }

        do {
            let session = try await resolvedSession(for: location, connections: connections)
            try await session.deleteItem(itemID, condition: condition)
        } catch {
            if let cacheReference {
                setFailure(error, operation: .deleteItem, for: cacheReference)
            }
            throw error
        }

        let descendantIDs = descendantItemIDs(of: itemID, in: state.items)
        let removedIDs = descendantIDs.union([itemID])
        let removedItems = state.items.filter { removedIDs.contains($0.id) }
        state.items.removeAll { removedIDs.contains($0.id) }
        removedIDs.forEach {
            state.cachedRevisions.removeValue(forKey: $0)
            state.dirtyItemIDs.remove($0)
        }
        if let cacheReference {
            try? fileManager.removeItem(at: cachedDocumentURL(for: cacheReference))
            syncStatesByDocumentID.removeValue(forKey: cacheReference.id)
            FileStatusService.shared.clearStatus(fileID: cacheReference.id)
        } else {
            for item in removedItems where item.kind == .file {
                let reference = CloudStorageDocumentReference(
                    locationID: location.id,
                    providerID: location.providerID,
                    accountID: location.accountID,
                    itemID: item.id,
                    lastKnownName: item.name,
                    lastKnownModifiedAt: item.modifiedAt
                )
                try? fileManager.removeItem(at: cachedDocumentURL(for: reference))
                syncStatesByDocumentID.removeValue(forKey: reference.id)
                FileStatusService.shared.clearStatus(fileID: reference.id)
            }
        }
        apply(state, to: locationID)
        try persist(state, for: locationID)
    }

    // MARK: - Remote Index Reconciliation

    private func refreshedDeltaState(
        _ existingState: PersistedLocationState,
        location: CloudStorageLocation,
        session: any CloudStorageSession,
        replacingExistingIndex: Bool = false
    ) async throws -> PersistedLocationState {
        let startedWithInitialCursor = existingState.cursor == nil
        var cursor = existingState.cursor
        var collectedChanges: [CloudStorageChange] = []
        repeat {
            let page = try await session.changes(in: location.rootItemID, since: cursor)
#if DEBUG
            let changedItems = page.changes.map { change in
                switch change {
                    case .upsert(let item):
                        return "upsert:\(item.id.rawValue.suffix(8)):\(item.name)"
                    case .deleted(let itemID):
                        return "delete:\(itemID.rawValue.suffix(8))"
                }
            }
            logger.debug(
                "Received cloud delta page location=\(location.displayName) cursor=\(cursor == nil ? "initial" : "existing") changes=\(page.changes.count) hasMore=\(page.hasMore) items=\(changedItems)"
            )
#endif
            collectedChanges.append(contentsOf: page.changes)
            cursor = page.nextCursor
            if !page.hasMore { break }
        } while true

        // Network requests suspend this MainActor-owned store. Merge the delta
        // into the latest state so a concurrent rename/save is not overwritten
        // by the snapshot captured before the request started.
        var state = persistedStates[location.id] ?? existingState
        if startedWithInitialCursor,
           (state.cursor == nil || replacingExistingIndex) {
            let protectedItemIDs = state.dirtyItemIDs.union(
                metadataMutationIDs.keys
                    .filter { $0.locationID == location.id }
                    .map(\.itemID)
            )
            state.items.removeAll { !protectedItemIDs.contains($0.id) }
        }
        var deletedItemIDs: [CloudStorageItemID] = []
        for change in collectedChanges {
            switch change {
                case .upsert(let item):
                    let mutationKey = MetadataMutationKey(
                        locationID: location.id,
                        itemID: item.id
                    )
                    guard metadataMutationIDs[mutationKey] == nil else { continue }
                    if let previousItem = state.items.first(where: { $0.id == item.id }),
                       previousItem.name != item.name {
                        logger.debug(
                            "Cloud storage item renamed: \(previousItem.name) -> \(item.name)"
                        )
                    }
                    state.items.removeAll { $0.id == item.id }
                    state.items.append(item)
                case .deleted(let itemID):
                    deletedItemIDs.append(itemID)
            }
        }
        // Apply removals after upserts so a child moved out of a deleted folder
        // keeps its new parent and is not removed as part of the old subtree.
        for itemID in deletedItemIDs {
            let mutationKey = MetadataMutationKey(
                locationID: location.id,
                itemID: itemID
            )
            guard metadataMutationIDs[mutationKey] == nil else { continue }
            let removedIDs = descendantItemIDs(of: itemID, in: state.items)
                .union([itemID])
            state.items.removeAll { removedIDs.contains($0.id) }
            for removedID in removedIDs {
                state.cachedRevisions.removeValue(forKey: removedID)
                state.dirtyItemIDs.remove(removedID)
            }
        }
        if startedWithInitialCursor,
           (state.cursor == nil || replacingExistingIndex) {
            let retainedItemIDs = Set(state.items.map(\.id))
            state.cachedRevisions = state.cachedRevisions.filter {
                retainedItemIDs.contains($0.key)
            }
        }
        state.cursor = cursor

        if !collectedChanges.isEmpty {
            logger.debug(
                "Applied \(collectedChanges.count) cloud storage change(s) for \(location.displayName)"
            )
        }
        return state
    }

    private func rebuiltStateAfterChangeTrackingReset(
        _ existingState: PersistedLocationState,
        location: CloudStorageLocation,
        session: any CloudStorageSession
    ) async throws -> PersistedLocationState {
        var resetState = existingState
        resetState.cursor = nil
        do {
            return try await refreshedDeltaState(
                resetState,
                location: location,
                session: session,
                replacingExistingIndex: true
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch where Self.isCancellationError(error) {
            throw CancellationError()
        } catch {
            logger.warning(
                "Delta rebuild failed for \(location.displayName); falling back to recursive listing: \(error)"
            )
            return try await recursivelyEnumeratedState(
                preservingCacheFrom: resetState,
                location: location,
                session: session
            )
        }
    }

    private func recursivelyEnumeratedState(
        preservingCacheFrom existingState: PersistedLocationState,
        location: CloudStorageLocation,
        session: any CloudStorageSession
    ) async throws -> PersistedLocationState {
        var queue = [location.rootItemID]
        var items: [CloudStorageItem] = []
        while let folderID = queue.first {
            queue.removeFirst()
            var pageToken: String?
            repeat {
                let page = try await session.listChildren(of: folderID, pageToken: pageToken)
                items.append(contentsOf: page.items)
                queue.append(contentsOf: page.items.filter { $0.kind == .folder }.map(\.id))
                pageToken = page.nextPageToken
            } while pageToken != nil
        }
        // Listing the complete subtree replaces the remote index, but local
        // dirty documents and optimistic metadata mutations must survive while
        // their provider requests are still pending.
        let latestState = persistedStates[location.id] ?? existingState
        let protectedItemIDs = latestState.dirtyItemIDs.union(
            metadataMutationIDs.keys
                .filter { $0.locationID == location.id }
                .map(\.itemID)
        )
        let protectedItems = latestState.items.filter {
            protectedItemIDs.contains($0.id)
        }
        let protectedIDs = Set(protectedItems.map(\.id))
        let mergedItems = items.filter { !protectedIDs.contains($0.id) }
            + protectedItems
        let retainedItemIDs = Set(mergedItems.map(\.id))

        return PersistedLocationState(
            cursor: nil,
            items: mergedItems,
            cachedRevisions: latestState.cachedRevisions.filter {
                retainedItemIDs.contains($0.key)
            },
            dirtyItemIDs: latestState.dirtyItemIDs
        )
    }

    // MARK: - Provider Sessions and Index Mutations

    private func resolvedSession(
        for location: CloudStorageLocation,
        connections: CloudStorageConnectionStore
    ) async throws -> any CloudStorageSession {
        if let session = sessionsByLocationID[location.id] {
            return session
        }
        if connections.account(for: location) == nil {
            await connections.refresh()
        }
        guard let account = connections.account(for: location) else {
            let error = CloudStorageError.accountUnavailable(location.accountID)
            connections.recordAccessFailure(error, for: location)
            throw error
        }
        let session: any CloudStorageSession
        do {
            session = try await connections.makeSession(
                providerID: location.providerID,
                account: account
            )
        } catch {
            connections.recordAccessFailure(error, for: location)
            throw error
        }
        sessionsByLocationID[location.id] = session
        return session
    }

    private func upsert(_ item: CloudStorageItem, in locationID: UUID) {
        var state = persistedStates[locationID] ?? Self.emptyState
        state.items.removeAll { $0.id == item.id }
        state.items.append(item)
        apply(state, to: locationID)
        try? persist(state, for: locationID)
    }

    private func beginOptimisticRename(
        _ item: CloudStorageItem,
        to name: String,
        locationID: UUID
    ) -> UUID {
        let key = MetadataMutationKey(locationID: locationID, itemID: item.id)
        let mutationID = UUID()
        metadataMutationIDs[key] = mutationID
        upsert(Self.renaming(item, to: name), in: locationID)
        return mutationID
    }

    private func completeOptimisticRename(
        _ item: CloudStorageItem,
        mutationID: UUID,
        locationID: UUID
    ) -> Bool {
        let key = MetadataMutationKey(locationID: locationID, itemID: item.id)
        guard metadataMutationIDs[key] == mutationID else { return false }
        metadataMutationIDs.removeValue(forKey: key)
        upsert(item, in: locationID)
        return true
    }

    private func rollbackOptimisticRename(
        _ item: CloudStorageItem,
        mutationID: UUID,
        locationID: UUID
    ) {
        let key = MetadataMutationKey(locationID: locationID, itemID: item.id)
        guard metadataMutationIDs[key] == mutationID else { return }
        metadataMutationIDs.removeValue(forKey: key)
        upsert(item, in: locationID)
    }

    private static func renaming(
        _ item: CloudStorageItem,
        to name: String
    ) -> CloudStorageItem {
        CloudStorageItem(
            id: item.id,
            parentID: item.parentID,
            name: name,
            kind: item.kind,
            contentType: item.contentType,
            size: item.size,
            createdAt: item.createdAt,
            modifiedAt: item.modifiedAt,
            remoteURL: item.remoteURL,
            revision: item.revision,
            capabilities: item.capabilities
        )
    }

    private static func require(
        _ capability: CloudStorageItemCapabilities,
        for item: CloudStorageItem,
        operation: CloudStorageOperation
    ) throws {
        try require(capability, in: item.effectiveCapabilities, operation: operation)
    }

    private static func require(
        _ capability: CloudStorageItemCapabilities,
        in capabilities: CloudStorageItemCapabilities,
        operation: CloudStorageOperation
    ) throws {
        guard capabilities.contains(capability) else {
            throw CloudStorageError.permissionDenied(operation)
        }
    }

    private func uniqueName(
        baseName: String,
        pathExtension: String,
        in parentID: CloudStorageItemID,
        locationID: UUID
    ) -> String {
        let names = Set(
            (itemsByLocationID[locationID] ?? [:]).values
                .filter { $0.parentID == parentID }
                .map { $0.name.lowercased() }
        )
        var index = 0
        while true {
            let suffix = index == 0 ? "" : " \(index)"
            let candidate = "\(baseName)\(suffix).\(pathExtension)"
            if !names.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }
    }

    private func descendantItemIDs(
        of folderID: CloudStorageItemID,
        in items: [CloudStorageItem]
    ) -> Set<CloudStorageItemID> {
        var result = Set<CloudStorageItemID>()
        var pending = [folderID]
        while let parentID = pending.popLast() {
            let children = items.filter { $0.parentID == parentID }
            for child in children where result.insert(child.id).inserted {
                if child.kind == .folder {
                    pending.append(child.id)
                }
            }
        }
        return result
    }

    // MARK: - Persistence and Runtime State

    private func ensureLocationStateLoaded(_ locationID: UUID) {
        guard !loadedLocationIDs.contains(locationID) else { return }
        loadedLocationIDs.insert(locationID)
        if let data = try? Data(contentsOf: stateURL(locationID)),
           let decoded = try? JSONDecoder().decode(PersistedLocationState.self, from: data) {
            persistedStates[locationID] = decoded
            itemsByLocationID[locationID] = Self.indexedItems(decoded.items)
            metadataRevisionsByLocationID[locationID, default: 0] += 1
        } else {
            persistedStates[locationID] = Self.emptyState
        }
    }

    private func apply(_ state: PersistedLocationState, to locationID: UUID) {
        persistedStates[locationID] = state
        let indexedItems = Self.indexedItems(state.items)
        if itemsByLocationID[locationID] != indexedItems {
            itemsByLocationID[locationID] = indexedItems
            metadataRevisionsByLocationID[locationID, default: 0] += 1
#if DEBUG
            logger.debug(
                "Updated cloud metadata index locationID=\(locationID) revision=\(metadataRevisionsByLocationID[locationID, default: 0]) items=\(indexedItems.count)"
            )
#endif
        }
    }

    func markConflict(for reference: CloudStorageDocumentReference) {
        setSyncState(.conflict, for: reference)
    }

    func markLocal(for reference: CloudStorageDocumentReference) {
        setSyncState(.local, for: reference)
    }

    func reportSyncFailure(
        _ error: Error,
        operation: CloudStorageOperation,
        for reference: CloudStorageDocumentReference
    ) {
        setFailure(error, operation: operation, for: reference)
    }

    private func setFailure(
        _ error: Error,
        operation: CloudStorageOperation,
        for reference: CloudStorageDocumentReference
    ) {
        if let cloudError = error as? CloudStorageError,
           cloudError == .conflict {
            setSyncState(.conflict, for: reference)
        } else {
            setSyncState(
                .failed(operation: operation, message: error.localizedDescription),
                for: reference
            )
        }
    }

    private func setSyncState(
        _ state: CloudStorageDocumentSyncState,
        for reference: CloudStorageDocumentReference
    ) {
        guard syncStatesByDocumentID[reference.id] != state else { return }
        syncStatesByDocumentID[reference.id] = state
    }

    private func notifyDocumentContentDidChange(
        _ reference: CloudStorageDocumentReference
    ) {
        NotificationCenter.default.post(
            name: .cloudStorageDocumentContentDidChange,
            object: reference
        )
    }

    // MARK: - Cache Paths and Utilities

    private func persist(_ state: PersistedLocationState, for locationID: UUID) throws {
        let url = stateURL(locationID)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    private func cachedDocumentURL(for reference: CloudStorageDocumentReference) -> URL {
        locationDirectoryURL(reference.locationID)
            .appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: Self.cacheFileName(for: reference.itemID))
    }

    private func stateURL(_ locationID: UUID) -> URL {
        locationDirectoryURL(locationID).appending(path: "index.json")
    }

    private func locationDirectoryURL(_ locationID: UUID) -> URL {
        rootURL.appending(path: locationID.uuidString, directoryHint: .isDirectory)
    }

    private static let emptyState = PersistedLocationState(
        cursor: nil,
        items: [],
        cachedRevisions: [:],
        dirtyItemIDs: []
    )

    private static func shouldDisplay(_ item: CloudStorageItem) -> Bool {
        guard item.kind != .folder else { return true }
        guard item.kind == .file else { return false }
        let name = item.name.lowercased()
        return name.hasSuffix(".excalidraw")
            || name.hasSuffix(".excalidraw.png")
            || name.hasSuffix(".excalidraw.svg")
    }

    private static func indexedItems(
        _ items: [CloudStorageItem]
    ) -> [CloudStorageItemID: CloudStorageItem] {
        items.reduce(into: [:]) { result, item in
            result[item.id] = item
        }
    }

    private static func cacheFileName(for itemID: CloudStorageItemID) -> String {
        Data(itemID.rawValue.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    private func propagateFolderState(
        _ state: CloudStorageFolderSyncState,
        from folderID: CloudStorageItemID,
        rootID: CloudStorageItemID,
        parentIDByFolderID: [CloudStorageItemID: CloudStorageItemID],
        states: inout [CloudStorageItemID: CloudStorageFolderSyncState]
    ) {
        var currentFolderID = folderID
        var visited = Set<CloudStorageItemID>()
        while visited.insert(currentFolderID).inserted {
            let currentState = states[currentFolderID, default: .idle]
            if currentState != .synchronizing {
                states[currentFolderID] = state
            }
            guard currentFolderID != rootID,
                  let parentID = parentIDByFolderID[currentFolderID] else {
                break
            }
            currentFolderID = parentID
        }
    }

    private static func fileName(
        _ displayName: String,
        preservingExtensionsFrom originalName: String
    ) -> String {
        let lowercased = originalName.lowercased()
        if lowercased.hasSuffix(".excalidraw.png") {
            return displayName + ".excalidraw.png"
        }
        if lowercased.hasSuffix(".excalidraw.svg") {
            return displayName + ".excalidraw.svg"
        }
        let pathExtension = (originalName as NSString).pathExtension
        return pathExtension.isEmpty ? displayName : displayName + "." + pathExtension
    }
}
