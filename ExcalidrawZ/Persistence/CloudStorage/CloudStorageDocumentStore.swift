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
        var metadataOperations: [CloudStorageMetadataOperation]

        private enum CodingKeys: String, CodingKey {
            case cursor
            case items
            case cachedRevisions
            case dirtyItemIDs
            case metadataOperations
        }

        init(
            cursor: CloudStorageChangeCursor?,
            items: [CloudStorageItem],
            cachedRevisions: [CloudStorageItemID: String],
            dirtyItemIDs: Set<CloudStorageItemID>,
            metadataOperations: [CloudStorageMetadataOperation] = []
        ) {
            self.cursor = cursor
            self.items = items
            self.cachedRevisions = cachedRevisions
            self.dirtyItemIDs = dirtyItemIDs
            self.metadataOperations = metadataOperations
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cursor = try container.decodeIfPresent(
                CloudStorageChangeCursor.self,
                forKey: .cursor
            )
            items = try container.decode([CloudStorageItem].self, forKey: .items)
            cachedRevisions = try container.decode(
                [CloudStorageItemID: String].self,
                forKey: .cachedRevisions
            )
            dirtyItemIDs = try container.decode(
                Set<CloudStorageItemID>.self,
                forKey: .dirtyItemIDs
            )
            metadataOperations = try container.decodeIfPresent(
                [CloudStorageMetadataOperation].self,
                forKey: .metadataOperations
            ) ?? []
        }
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
    private var automaticRetryDatesByLocationID: [UUID: Date] = [:]
    private var saveTasks: [String: Task<Void, Error>] = [:]
    private var saveTaskIDs: [String: UUID] = [:]
    private var localContentGenerations: [String: UInt64] = [:]
    private var contentSynchronizationTasks: [String: Task<Void, Never>] = [:]
    private var activeContentSynchronizationPriorities: [String: CloudStorageContentSynchronizationPriority] = [:]
    private var contentSynchronizationQueue: [String: ContentSynchronizationRequest] = [:]
    private var nextContentSynchronizationSequence = 0
    private var retryUploadTasks: [String: Task<Void, Never>] = [:]
    private var retryUploadTaskIDs: [String: UUID] = [:]
    private var replayingMetadataOperationIDs: Set<UUID> = []
    private var remoteContentMutationGeneration: UInt64 = 0
    private var remoteContentMutationGenerationByItem: [MetadataMutationKey: UInt64] = [:]
    private var resolvingConflictDocumentIDs: Set<String> = []

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

    func hasLoadedMetadataIndex(for locationID: UUID) -> Bool {
        itemsByLocationID[locationID] != nil
    }

    /// Returns provider-neutral document identities from the device-local
    /// metadata index. This never performs network IO; consumers update when
    /// the synchronization service publishes a newer index.
    func indexedDocumentReferences(
        in locations: [CloudStorageLocation]
    ) -> [CloudStorageDocumentReference] {
        var references: [CloudStorageDocumentReference] = []
        for location in locations {
            guard let indexedItems = itemsByLocationID[location.id] else { continue }
            for item in indexedItems.values
            where item.kind == .file && Self.shouldDisplay(item) {
                references.append(CloudStorageDocumentReference(
                    locationID: location.id,
                    providerID: location.providerID,
                    accountID: location.accountID,
                    itemID: item.id,
                    lastKnownName: item.name,
                    lastKnownModifiedAt: item.modifiedAt
                ))
            }
        }
        return references
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
    ) -> CloudStorageDocumentReference? {
        guard let item = item(for: reference) else { return nil }
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

    /// Returns the most specific folder currently available for navigation.
    /// The metadata index may not contain a WebDAV document's parent yet, so
    /// fall back to its linked root instead of leaving Sidebar navigation in
    /// the previously selected location.
    func bestKnownParentFolder(
        for document: CloudStorageDocumentReference
    ) -> CloudStorageFolderReference? {
        if let parent = parentFolder(for: document) {
            return parent
        }
        guard let location = CloudStorageConnectionStore.shared.locations.first(where: {
            $0.id == document.locationID
        }) else {
            return nil
        }
        return .root(of: location)
    }

    func isRefreshing(_ location: CloudStorageLocation) -> Bool {
        refreshingLocationIDs.contains(location.id)
    }

    func errorMessage(for location: CloudStorageLocation) -> String? {
        errorsByLocationID[location.id]
    }

    func automaticRetryDate(for locationID: UUID) -> Date? {
        automaticRetryDatesByLocationID[locationID]
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
            if documentState.isVisiblySynchronizing {
                folderState = .synchronizing
            } else if documentState == .queued {
                folderState = .queued(
                    pendingSyncDirection(for: reference)
                )
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

        for operation in persistedStates[location.id]?.metadataOperations ?? [] {
            let operationItem = items[operation.itemID]
            guard let folderID = operationItem?.kind == .folder
                ? operationItem?.id
                : operation.parentID else { continue }
            propagateFolderState(
                .queued(.upload),
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

    func pendingSyncDirection(
        for reference: CloudStorageDocumentReference
    ) -> CloudStoragePendingSyncDirection {
        guard let state = persistedStates[reference.locationID] else {
            return .download
        }
        let hasPendingUpload = state.dirtyItemIDs.contains(reference.itemID)
            || state.metadataOperations.contains { operation in
                operation.itemID == reference.itemID
                    || operation.parentID == reference.itemID
            }
        return hasPendingUpload ? .upload : .download
    }

    func syncState(
        for reference: CloudStorageDocumentReference
    ) -> CloudStorageDocumentSyncState {
        if let state = syncStatesByDocumentID[reference.id] {
            return state
        }

        if reference.itemID.isPendingLocalID {
            return .local
        }

        guard let persistedState = persistedStates[reference.locationID] else {
            return .local
        }
        if persistedState.metadataOperations.contains(where: {
            $0.itemID == reference.itemID
        }) {
            return .queued
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
            guard try await replayPendingMetadataOperations(
                in: location,
                connections: connections
            ) else {
                return false
            }
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
            automaticRetryDatesByLocationID.removeValue(forKey: location.id)
            connections.clearAuthenticationRequirement(for: location)
            return true
        } catch is CancellationError {
            return false
        } catch {
            if Self.isCancellationError(error) {
                return false
            }
            if case let CloudStorageError.rateLimited(retryAfter) = error {
                automaticRetryDatesByLocationID[location.id] = Date().addingTimeInterval(
                    max(retryAfter ?? 300, 60)
                )
            }
            connections.recordAccessFailure(error, for: location)
            if CloudStorageConnectivityMonitor.shared.status == .unavailable {
                errorsByLocationID[location.id] = nil
            } else {
                errorsByLocationID[location.id] = error.localizedDescription
            }
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
        priority: CloudStorageContentSynchronizationPriority = .background,
        queueAfterActiveSynchronization: Bool = false
    ) {
        let synchronizationKey = reference.id
        guard !resolvingConflictDocumentIDs.contains(synchronizationKey) else { return }
        let hasActiveSynchronization = contentSynchronizationTasks[synchronizationKey] != nil
        guard !hasActiveSynchronization || queueAfterActiveSynchronization else { return }

        if var request = contentSynchronizationQueue[synchronizationKey] {
            guard priority > request.priority else { return }
            request.priority = priority
            contentSynchronizationQueue[synchronizationKey] = request
            if !hasActiveSynchronization {
                processContentSynchronizationQueue()
            }
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
        setPendingSyncState(for: reference)

        if hasActiveSynchronization { return }
        processContentSynchronizationQueue()
    }

    /// Promotes a document only when its device cache actually needs work.
    /// This keeps visibility-driven prioritization from turning an already
    /// synchronized document back into a queued state.
    func scheduleContentSynchronizationIfNeeded(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore? = nil,
        priority: CloudStorageContentSynchronizationPriority = .background
    ) {
        ensureLocationStateLoaded(reference.locationID)
        guard !resolvingConflictDocumentIDs.contains(reference.id) else { return }
        if case .conflict = syncState(for: reference) { return }

        let state = persistedStates[reference.locationID] ?? Self.emptyState
        guard let item = state.items.first(where: { $0.id == reference.itemID }),
              item.kind == .file,
              item.effectiveCapabilities.contains(.download) else { return }

        let cacheExists = fileManager.fileExists(
            atPath: cachedDocumentURL(for: reference).path
        )
        let needsSynchronization = state.dirtyItemIDs.contains(reference.itemID)
            || !cacheExists
            || !Self.revisionsMatch(
                cached: state.cachedRevisions[reference.itemID],
                remote: item.revision
            )

        if needsSynchronization {
            scheduleContentSynchronization(
                for: reference,
                connections: connections,
                priority: priority
            )
        } else {
            setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
        }
    }

    private func processContentSynchronizationQueue() {
        guard CloudStorageConnectivityMonitor.shared.canAttemptNetworkRequests else {
            return
        }
        while contentSynchronizationTasks.count < maximumConcurrentContentSynchronizations {
            let activeBackgroundCount = activeContentSynchronizationPriorities.values.reduce(into: 0) {
                if $1 == .background { $0 += 1 }
            }
            let nextRequest = contentSynchronizationQueue.values
                .filter {
                    saveTasks[$0.reference.id] == nil
                        && retryUploadTasks[$0.reference.id] == nil
                }
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
    @discardableResult
    func saveToLocalCache(
        _ data: Data,
        for reference: CloudStorageDocumentReference
    ) throws -> Bool {
        // Conflict resolution owns the cache and remote revision until the
        // selected version is committed. Ignore stale canvas snapshots that
        // were scheduled before the conflict sheet appeared.
        guard !resolvingConflictDocumentIDs.contains(reference.id) else {
            return false
        }
        if case .conflict = syncState(for: reference) {
            throw CloudStorageError.conflict
        }
        let stagedSave = try stageLocalSave(data, for: reference)
        guard stagedSave.needsUpload else { return false }
        setPendingSyncState(for: reference)
        return true
    }

    /// Resumes requests that were deliberately left queued while the device
    /// had no usable network path.
    func resumeQueuedContentSynchronizations() {
        processContentSynchronizationQueue()
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
            let cacheExists = fileManager.fileExists(
                atPath: cachedDocumentURL(for: reference).path
            )

            if state.metadataOperations.contains(where: {
                $0.itemID == item.id
            }) {
                setPendingSyncState(for: reference)
                continue
            }

            if state.dirtyItemIDs.contains(item.id) {
                scheduleContentSynchronization(
                    for: reference,
                    connections: connections,
                    priority: priority
                )
                continue
            }

            guard !excludingDocumentIDs.contains(reference.id) else { continue }

            let cachedRevision = state.cachedRevisions[item.id]
            if !cacheExists || !Self.revisionsMatch(
                cached: cachedRevision,
                remote: item.revision
            ) {
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
        guard !resolvingConflictDocumentIDs.contains(reference.id) else {
            return nil
        }
        guard CloudStorageConnectivityMonitor.shared.canAttemptNetworkRequests else {
            setPendingSyncState(for: reference)
            return nil
        }
        let connections = connections ?? .shared
        setSyncState(.checking, for: reference)

        do {
            guard let location = connections.locations.first(where: { $0.id == reference.locationID }) else {
                throw CloudStorageError.itemNotFound(reference.itemID)
            }
            ensureLocationStateLoaded(location.id)
            let state = persistedStates[location.id] ?? Self.emptyState

            if state.metadataOperations.contains(where: {
                $0.itemID == reference.itemID
            }) {
                setPendingSyncState(for: reference)
                return nil
            }

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
               Self.revisionsMatch(
                   cached: state.cachedRevisions[reference.itemID],
                   remote: remoteItem.revision
               ) {
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

    func conflictSnapshot(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore? = nil
    ) async throws -> CloudStorageConflictSnapshot {
        let connections = connections ?? .shared
        guard let location = connections.locations.first(where: {
            $0.id == reference.locationID
        }) else {
            throw CloudStorageError.itemNotFound(reference.itemID)
        }
        ensureLocationStateLoaded(location.id)

        let cacheURL = cachedDocumentURL(for: reference)
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            throw CloudStorageError.itemNotFound(reference.itemID)
        }
        let localData = try Data(contentsOf: cacheURL)
        let localModifiedAt = try? cacheURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate

        let session = try await resolvedSession(for: location, connections: connections)
        let remoteItem = try await session.item(for: reference.itemID)
        try Self.require(.download, for: remoteItem, operation: .download)

        let stagingURL = fileManager.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(
                (displayName(for: reference) as NSString).pathExtension
            )
        defer { try? fileManager.removeItem(at: stagingURL) }
        let downloadedItem = try await session.downloadFile(reference.itemID, to: stagingURL)

        return CloudStorageConflictSnapshot(
            reference: reference,
            localData: localData,
            localModifiedAt: localModifiedAt,
            remoteData: try Data(contentsOf: stagingURL),
            remoteItem: downloadedItem
        )
    }

    func resolveConflict(
        _ snapshot: CloudStorageConflictSnapshot,
        keeping version: CloudStorageConflictVersion,
        connections: CloudStorageConnectionStore? = nil
    ) async throws {
        let reference = snapshot.reference
        guard resolvingConflictDocumentIDs.insert(reference.id).inserted else {
            return
        }
        defer {
            resolvingConflictDocumentIDs.remove(reference.id)
        }
        let connections = connections ?? .shared
        guard let location = connections.locations.first(where: {
            $0.id == reference.locationID
        }) else {
            throw CloudStorageError.itemNotFound(reference.itemID)
        }
        ensureLocationStateLoaded(location.id)

        // A retry started while the conflict sheet was open must not race the
        // explicit user choice and turn the resolved revision into a conflict
        // again. Cancel it before taking the final remote revision snapshot.
        await cancelPendingDocumentWork(for: reference)

        let session = try await resolvedSession(for: location, connections: connections)
        let currentRemoteItem = try await session.item(for: reference.itemID)
        guard Self.representsSameRemoteRevision(
            currentRemoteItem,
            snapshot.remoteItem
        ) else {
            setSyncState(.conflict, for: reference)
            throw CloudStorageError.conflict
        }

        switch version {
            case .local:
                let localData = snapshot.localData
                let cacheURL = cachedDocumentURL(for: reference)
                try fileManager.createDirectory(
                    at: cacheURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try localData.write(to: cacheURL, options: .atomic)
                localContentGenerations[reference.id, default: 0] &+= 1

                var state = persistedStates[location.id] ?? Self.emptyState
                state.items.removeAll { $0.id == reference.itemID }
                state.items.append(currentRemoteItem)
                if let revision = currentRemoteItem.revision {
                    state.cachedRevisions[reference.itemID] = revision
                } else {
                    state.cachedRevisions.removeValue(forKey: reference.itemID)
                }
                state.dirtyItemIDs.insert(reference.itemID)
                apply(state, to: location.id)
                try persist(state, for: location.id)

                try await uploadCachedContent(
                    localData,
                    for: reference,
                    connections: connections
                )
                notifyConflictDidResolve(
                    reference,
                    keptVersion: .local,
                    content: localData
                )

            case .remote:
                let cacheURL = cachedDocumentURL(for: reference)
                try fileManager.createDirectory(
                    at: cacheURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try snapshot.remoteData.write(to: cacheURL, options: .atomic)

                var state = persistedStates[location.id] ?? Self.emptyState
                state.items.removeAll { $0.id == reference.itemID }
                state.items.append(currentRemoteItem)
                if let revision = currentRemoteItem.revision {
                    state.cachedRevisions[reference.itemID] = revision
                } else {
                    state.cachedRevisions.removeValue(forKey: reference.itemID)
                }
                state.dirtyItemIDs.remove(reference.itemID)
                localContentGenerations[reference.id, default: 0] &+= 1
                apply(state, to: location.id)
                try persist(state, for: location.id)
                setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
                notifyDocumentContentDidChange(reference)
                notifyConflictDidResolve(
                    reference,
                    keptVersion: .remote,
                    content: snapshot.remoteData
                )
        }
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

        if state.metadataOperations.contains(where: {
            $0.itemID == reference.itemID
        }) {
            setPendingSyncState(for: reference)
            guard fileManager.fileExists(atPath: cacheURL.path) else {
                throw CloudStorageError.itemNotFound(reference.itemID)
            }
            return try Data(contentsOf: cacheURL)
        }

        if resolvingConflictDocumentIDs.contains(reference.id),
           fileManager.fileExists(atPath: cacheURL.path) {
            return try Data(contentsOf: cacheURL)
        }

        if state.dirtyItemIDs.contains(reference.itemID),
           fileManager.fileExists(atPath: cacheURL.path) {
            if case .conflict = syncStatesByDocumentID[reference.id] {
                return try Data(contentsOf: cacheURL)
            }
            setSyncState(.queued, for: reference)
            let data = try Data(contentsOf: cacheURL)
            if CloudStorageConnectivityMonitor.shared.canAttemptNetworkRequests {
                retryDirtyUploadIfNeeded(
                    data,
                    reference: reference,
                    connections: connections
                )
            }
            return data
        }

        if !checkingRemoteRevision,
           fileManager.fileExists(atPath: cacheURL.path),
           let indexedItem = state.items.first(where: { $0.id == reference.itemID }),
           Self.revisionsMatch(
               cached: state.cachedRevisions[reference.itemID],
               remote: indexedItem.revision
           ) {
            setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
            return try Data(contentsOf: cacheURL)
        }

        if !CloudStorageConnectivityMonitor.shared.canAttemptNetworkRequests {
            setSyncState(.queued, for: reference)
            guard fileManager.fileExists(atPath: cacheURL.path) else {
                throw NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorNotConnectedToInternet
                )
            }
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
        if deferContentUploadUntilMetadataReplayIfNeeded(
            for: reference,
            connections: connections
        ) {
            return
        }
        guard !resolvingConflictDocumentIDs.contains(reference.id),
              saveTasks[reference.id] == nil,
              retryUploadTasks[reference.id] == nil else { return }
        setPendingSyncState(for: reference)
        let taskID = UUID()
        retryUploadTaskIDs[reference.id] = taskID
        retryUploadTasks[reference.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.retryUploadTaskIDs[reference.id] == taskID {
                    self.retryUploadTasks[reference.id] = nil
                    self.retryUploadTaskIDs[reference.id] = nil
                    self.processContentSynchronizationQueue()
                }
            }
            do {
                try Task.checkCancellation()
                try await self.uploadCachedContent(
                    data,
                    for: reference,
                    connections: connections
                )
                self.logger.debug(
                    "Retried dirty cloud document upload: \(self.displayName(for: reference))"
                )
            } catch is CancellationError {
                return
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
        guard !resolvingConflictDocumentIDs.contains(reference.id) else {
            return
        }
        if case .conflict = syncState(for: reference) {
            throw CloudStorageError.conflict
        }
        let stagedSave = try stageLocalSave(data, for: reference)
        guard stagedSave.needsUpload else { return }
        if deferContentUploadUntilMetadataReplayIfNeeded(
            for: reference,
            connections: connections
        ) {
            return
        }
        guard CloudStorageConnectivityMonitor.shared.canAttemptNetworkRequests else {
            setSyncState(.queued, for: reference)
            return
        }
        try await enqueueSave(
            data,
            to: reference,
            connections: connections,
            localGeneration: stagedSave.generation
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
        if deferContentUploadUntilMetadataReplayIfNeeded(
            for: reference,
            connections: connections
        ) {
            return
        }
        let saveKey = reference.id
        if let activeTask = saveTasks[saveKey] {
            // The active worker reads the cache again after each upload. A
            // newer staged generation therefore joins that worker instead of
            // creating an upload for every intermediate canvas snapshot.
            try await activeTask.value
            return
        }

        let taskID = UUID()
        let task = Task { @MainActor in
            self.setSyncState(.uploading(progress: nil), for: reference)
            do {
                var pendingData = data
                var pendingGeneration = localGeneration
                while true {
                    try Task.checkCancellation()
                    let uploadedLatestContent = try await self.performSave(
                        pendingData,
                        to: reference,
                        connections: connections,
                        localGeneration: pendingGeneration
                    )
                    if uploadedLatestContent {
                        break
                    }

                    pendingData = try Data(
                        contentsOf: self.cachedDocumentURL(for: reference)
                    )
                    pendingGeneration = self.localContentGenerations[reference.id, default: 0]
                }
                if self.saveTaskIDs[saveKey] == taskID {
                    self.setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
                }
            } catch {
                if self.saveTaskIDs[saveKey] == taskID {
                    self.setFailure(error, operation: .updateFile, for: reference)
                }
                throw error
            }
        }
        setSyncState(.uploading(progress: nil), for: reference)
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

    /// A provider cannot address content by the provisional ID used by a
    /// local-first create. The metadata outbox resolves that identity first;
    /// its completion preserves dirty state and schedules the content upload.
    private func deferContentUploadUntilMetadataReplayIfNeeded(
        for reference: CloudStorageDocumentReference,
        connections: CloudStorageConnectionStore
    ) -> Bool {
        ensureLocationStateLoaded(reference.locationID)
        guard persistedStates[reference.locationID]?.metadataOperations.contains(where: {
            $0.itemID == reference.itemID
        }) == true else {
            return false
        }

        setSyncState(.local, for: reference)
        if let location = connections.locations.first(where: {
            $0.id == reference.locationID
        }) {
            CloudStorageSyncService.shared.enqueueMetadataSynchronization(
                for: location,
                connections: connections
            )
        }
        return true
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
        let item = Self.pendingItem(
            name: name,
            kind: .file,
            parentID: folder.itemID
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
        state.items.append(item)
        state.metadataOperations.append(
            CloudStorageMetadataOperation(
                kind: .createFile,
                itemID: item.id,
                parentID: folder.itemID,
                name: name
            )
        )
        let cacheURL = cachedDocumentURL(for: reference)
        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: cacheURL, options: .atomic)
        apply(state, to: folder.location.id)
        try persist(state, for: folder.location.id)
        setSyncState(.local, for: reference)
        CloudStorageSyncService.shared.enqueueMetadataSynchronization(
            for: folder.location,
            connections: connections
        )
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
            let item = Self.pendingItem(
                name: name,
                kind: .file,
                parentID: parentID
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
            state.items.append(item)
            state.metadataOperations.append(
                CloudStorageMetadataOperation(
                    kind: .createFile,
                    itemID: item.id,
                    parentID: parentID,
                    name: name
                )
            )
            let cacheURL = cachedDocumentURL(for: duplicate)
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
            apply(state, to: location.id)
            try persist(state, for: location.id)
            setSyncState(.local, for: duplicate)
            duplicates.append(duplicate)
        }

        for location in connections.locations where duplicates.contains(where: {
            $0.locationID == location.id
        }) {
            CloudStorageSyncService.shared.enqueueMetadataSynchronization(
                for: location,
                connections: connections
            )
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
        let item = Self.pendingItem(
            name: name,
            kind: .folder,
            parentID: folder.itemID
        )
        var state = persistedStates[folder.location.id] ?? Self.emptyState
        state.items.append(item)
        state.metadataOperations.append(
            CloudStorageMetadataOperation(
                kind: .createFolder,
                itemID: item.id,
                parentID: folder.itemID,
                name: name
            )
        )
        apply(state, to: folder.location.id)
        try persist(state, for: folder.location.id)
        CloudStorageSyncService.shared.enqueueMetadataSynchronization(
            for: folder.location,
            connections: connections
        )
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
        let latestItem = try enqueueMove(
            item,
            to: nil,
            newName: name,
            location: location
        )
        let updatedReference = CloudStorageDocumentReference(
            locationID: location.id,
            providerID: location.providerID,
            accountID: location.accountID,
            itemID: latestItem.id,
            lastKnownName: latestItem.name,
            lastKnownModifiedAt: latestItem.modifiedAt
        )
        setSyncState(.queued, for: updatedReference)
        CloudStorageSyncService.shared.enqueueMetadataSynchronization(
            for: location,
            connections: connections
        )
        return updatedReference
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
        let latestItem = try enqueueMove(
            item,
            to: nil,
            newName: name,
            location: folder.location
        )
        CloudStorageSyncService.shared.enqueueMetadataSynchronization(
            for: folder.location,
            connections: connections
        )
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

        var documentIDs = Set(syncStatesByDocumentID.keys)
        documentIDs.formUnion(localContentGenerations.keys)
        documentIDs.formUnion(saveTasks.keys)
        documentIDs.formUnion(saveTaskIDs.keys)
        documentIDs.formUnion(retryUploadTasks.keys)
        documentIDs.formUnion(retryUploadTaskIDs.keys)
        documentIDs.formUnion(contentSynchronizationTasks.keys)
        documentIDs.formUnion(contentSynchronizationQueue.keys)
        documentIDs.formUnion(activeContentSynchronizationPriorities.keys)
        documentIDs.formUnion(resolvingConflictDocumentIDs)
        documentIDs = documentIDs.filter {
            documentIDBelongsToLocation($0, locationID: locationID)
        }
        documentIDs.forEach(removeDocumentRuntimeState)
        loadedLocationIDs.remove(locationID)
        persistedStates.removeValue(forKey: locationID)
        itemsByLocationID.removeValue(forKey: locationID)
        metadataRevisionsByLocationID.removeValue(forKey: locationID)
        sessionsByLocationID.removeValue(forKey: locationID)
        errorsByLocationID.removeValue(forKey: locationID)
        automaticRetryDatesByLocationID.removeValue(forKey: locationID)
        processingFolderIDsByLocationID.removeValue(forKey: locationID)
        remoteContentMutationGenerationByItem = remoteContentMutationGenerationByItem.filter {
            $0.key.locationID != locationID
        }
        try? fileManager.removeItem(at: locationDirectoryURL(locationID))
        processContentSynchronizationQueue()
    }

    private func removeDocumentRuntimeState(_ documentID: String) {
        saveTasks.removeValue(forKey: documentID)?.cancel()
        saveTaskIDs.removeValue(forKey: documentID)
        retryUploadTasks.removeValue(forKey: documentID)?.cancel()
        retryUploadTaskIDs.removeValue(forKey: documentID)
        contentSynchronizationTasks.removeValue(forKey: documentID)?.cancel()
        contentSynchronizationQueue.removeValue(forKey: documentID)
        activeContentSynchronizationPriorities.removeValue(forKey: documentID)
        localContentGenerations.removeValue(forKey: documentID)
        syncStatesByDocumentID.removeValue(forKey: documentID)
        resolvingConflictDocumentIDs.remove(documentID)
        FileStatusService.shared.clearStatus(fileID: documentID)
    }

    /// Forces the next operation to rebuild its authenticated provider
    /// session while preserving the location index and document cache.
    func invalidateSession(for locationID: UUID) {
        sessionsByLocationID.removeValue(forKey: locationID)
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
#if DEBUG
        logger.debug(
            "Uploading cloud document \(displayName(for: reference)) expectedRevision=\(revision ?? "nil") localGeneration=\(localGeneration)"
        )
#endif
        let updatedItem = try await session.updateFile(
            reference.itemID,
            contentsAt: uploadURL,
            condition: condition
        )
        // Disconnecting a location cancels its workers. Some URLSession-backed
        // providers can still return a response after cancellation, so prevent
        // that result from rebuilding state which has already been removed.
        try Task.checkCancellation()
        guard connections.locations.contains(where: { $0.id == location.id }) else {
            throw CancellationError()
        }
        recordRemoteContentMutation(
            locationID: location.id,
            itemID: reference.itemID
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
        logger.debug(
            "Uploaded cloud document \(displayName(for: reference)) revision=\(updatedItem.revision ?? "nil") uploadedLatestContent=\(uploadedLatestContent)"
        )
        return uploadedLatestContent
    }

    @discardableResult
    private func stageLocalSave(
        _ data: Data,
        for reference: CloudStorageDocumentReference
    ) throws -> (generation: UInt64, needsUpload: Bool) {
        ensureLocationStateLoaded(reference.locationID)
        var state = persistedStates[reference.locationID] ?? Self.emptyState
        let cacheURL = cachedDocumentURL(for: reference)
        let generation = localContentGenerations[reference.id, default: 0]
        if fileManager.fileExists(atPath: cacheURL.path),
           try Data(contentsOf: cacheURL) == data {
            return (
                generation,
                state.dirtyItemIDs.contains(reference.itemID)
            )
        }

        try fileManager.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)
        state.dirtyItemIDs.insert(reference.itemID)
        apply(state, to: reference.locationID)
        try persist(state, for: reference.locationID)

        let nextGeneration = generation &+ 1
        localContentGenerations[reference.id] = nextGeneration
        notifyDocumentContentDidChange(reference)
        return (nextGeneration, true)
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
        guard let item = state.items.first(where: { $0.id == itemID }) else {
            throw CloudStorageError.itemNotFound(itemID)
        }
        try Self.require(.delete, for: item, operation: .deleteItem)

        let descendantIDs = descendantItemIDs(of: itemID, in: state.items)
        let removedIDs = descendantIDs.union([itemID])
        let removedItems = state.items.filter { removedIDs.contains($0.id) }
        let removedDocumentReferences = removedItems.compactMap { item in
            item.kind == .file
                ? Self.documentReference(for: item, in: location)
                : nil
        }
        let wasCreatedLocally = state.metadataOperations.contains {
            ($0.kind == .createFile || $0.kind == .createFolder)
                && $0.itemID == itemID
                && !replayingMetadataOperationIDs.contains($0.id)
        }
        state.metadataOperations.removeAll {
            !replayingMetadataOperationIDs.contains($0.id)
                && (
                    removedIDs.contains($0.itemID)
                        || $0.parentID.map(removedIDs.contains) == true
                )
        }
        if !wasCreatedLocally {
            state.metadataOperations.append(
                CloudStorageMetadataOperation(
                    kind: .deleteItem,
                    itemID: itemID,
                    parentID: item.parentID,
                    revision: item.revision
                )
            )
        }
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
        if !removedDocumentReferences.isEmpty {
            do {
                try await CloudStorageCheckpointStore.deleteCheckpoints(
                    for: removedDocumentReferences
                )
            } catch {
                logger.warning(
                    "Failed to delete cloud document checkpoints: \(error)"
                )
            }
            NotificationCenter.default.post(
                name: .cloudStorageDocumentsDidDelete,
                object: removedDocumentReferences
            )
        }
        CloudStorageSyncService.shared.enqueueMetadataSynchronization(
            for: location,
            connections: connections
        )
    }

    // MARK: - Remote Index Reconciliation

    private func refreshedDeltaState(
        _ existingState: PersistedLocationState,
        location: CloudStorageLocation,
        session: any CloudStorageSession,
        replacingExistingIndex: Bool = false
    ) async throws -> PersistedLocationState {
        let contentMutationGenerationAtStart = remoteContentMutationGeneration
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
                state.metadataOperations.map(\.itemID)
            ).union(
                itemIDsMutatedSince(
                    contentMutationGenerationAtStart,
                    in: location.id
                )
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
                    guard !state.metadataOperations.contains(where: {
                        $0.itemID == item.id
                    }),
                          !wasContentMutated(
                            mutationKey,
                            since: contentMutationGenerationAtStart
                          ) else { continue }
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
            guard !state.metadataOperations.contains(where: {
                $0.itemID == itemID
            }),
                  !wasContentMutated(
                    mutationKey,
                    since: contentMutationGenerationAtStart
                  ) else { continue }
            let removedIDs = descendantItemIDs(of: itemID, in: state.items)
                .union([itemID])
            state.items.removeAll { removedIDs.contains($0.id) }
            for removedID in removedIDs {
                state.cachedRevisions.removeValue(forKey: removedID)
                state.dirtyItemIDs.remove(removedID)
            }
        }
        state.items = Self.removingPendingDeletionTombstones(
            from: state.items,
            operations: state.metadataOperations
        )
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
        let contentMutationGenerationAtStart = remoteContentMutationGeneration
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
            latestState.metadataOperations.map(\.itemID)
        ).union(
            itemIDsMutatedSince(
                contentMutationGenerationAtStart,
                in: location.id
            )
        )
        let protectedItems = latestState.items.filter {
            protectedItemIDs.contains($0.id)
        }
        let protectedIDs = Set(protectedItems.map(\.id))
        let remoteItems = Self.removingPendingDeletionTombstones(
            from: items,
            operations: latestState.metadataOperations
        )
        let mergedItems = remoteItems.filter { !protectedIDs.contains($0.id) }
            + protectedItems
        let retainedItemIDs = Set(mergedItems.map(\.id))

        return PersistedLocationState(
            cursor: nil,
            items: mergedItems,
            cachedRevisions: latestState.cachedRevisions.filter {
                retainedItemIDs.contains($0.key)
            },
            dirtyItemIDs: latestState.dirtyItemIDs,
            metadataOperations: latestState.metadataOperations
        )
    }

    // MARK: - Provider Sessions and Index Mutations

    /// Replays local-first metadata mutations before accepting a newer remote
    /// index. Returning false keeps the optimistic local index intact until a
    /// later synchronization attempt can continue the queue.
    private func replayPendingMetadataOperations(
        in location: CloudStorageLocation,
        connections: CloudStorageConnectionStore
    ) async throws -> Bool {
        ensureLocationStateLoaded(location.id)
        guard CloudStorageConnectivityMonitor.shared.canAttemptNetworkRequests else {
            return false
        }
        guard persistedStates[location.id]?.metadataOperations.isEmpty == false else {
            return true
        }

        let session = try await resolvedSession(for: location, connections: connections)
        while let operation = persistedStates[location.id]?.metadataOperations.first {
            try Task.checkCancellation()
            replayingMetadataOperationIDs.insert(operation.id)
            let localItem = persistedStates[location.id]?.items.first {
                $0.id == operation.itemID
            }
            let documentReference = localItem.flatMap { item in
                item.kind == .file
                    ? Self.documentReference(for: item, in: location)
                    : nil
            }
            if let documentReference {
                setSyncState(
                    operation.kind == .createFile
                        ? .uploading(progress: nil)
                        : .processing,
                    for: documentReference
                )
            }
            let processingFolderID = localItem?.kind == .folder
                ? localItem?.id
                : operation.parentID ?? localItem?.parentID
            if let processingFolderID {
                processingFolderIDsByLocationID[location.id, default: []]
                    .insert(processingFolderID)
            }

            do {
                switch operation.kind {
                    case .createFile:
                        guard let localItem,
                              let parentID = operation.parentID,
                              let name = operation.name else {
                            throw CloudStorageError.invalidProviderResponse(
                                "A queued file creation is missing local metadata."
                            )
                        }
                        let cacheURL = cachedDocumentURL(
                            locationID: location.id,
                            itemID: operation.itemID
                        )
                        guard fileManager.fileExists(atPath: cacheURL.path) else {
                            throw CloudStorageError.itemNotFound(operation.itemID)
                        }
                        let localGeneration = localContentGenerations[
                            documentReference?.id ?? "",
                            default: 0
                        ]
                        let uploadURL = fileManager.temporaryDirectory
                            .appending(path: UUID().uuidString)
                            .appendingPathExtension(
                                (name as NSString).pathExtension
                            )
                        defer { try? fileManager.removeItem(at: uploadURL) }
                        try Data(contentsOf: cacheURL).write(
                            to: uploadURL,
                            options: .atomic
                        )
                        let remoteItem = try await session.createFile(
                            named: name,
                            in: parentID,
                            contentsAt: uploadURL,
                            condition: .ifAbsent
                        )
                        try await completeMetadataOperation(
                            operation,
                            replacing: localItem,
                            with: remoteItem,
                            location: location,
                            uploadedLocalGeneration: localGeneration
                        )

                    case .createFolder:
                        guard let localItem,
                              let parentID = operation.parentID,
                              let name = operation.name else {
                            throw CloudStorageError.invalidProviderResponse(
                                "A queued folder creation is missing local metadata."
                            )
                        }
                        let remoteItem = try await session.createFolder(
                            named: name,
                            in: parentID
                        )
                        try await completeMetadataOperation(
                            operation,
                            replacing: localItem,
                            with: remoteItem,
                            location: location
                        )

                    case .moveItem:
                        guard let localItem else {
                            throw CloudStorageError.itemNotFound(operation.itemID)
                        }
                        let remoteItem = try await session.moveItem(
                            operation.itemID,
                            to: operation.parentID,
                            newName: operation.name
                        )
                        try await completeMetadataOperation(
                            operation,
                            replacing: localItem,
                            with: remoteItem,
                            location: location
                        )

                    case .deleteItem:
                        let condition = operation.revision.map(
                            CloudStorageWriteCondition.ifUnmodified
                        ) ?? .unconditional
                        do {
                            try await session.deleteItem(
                                operation.itemID,
                                condition: condition
                            )
                        } catch CloudStorageError.itemNotFound(_) {
                            // The desired final state already exists remotely.
                        }
                        try removeMetadataOperation(
                            operation.id,
                            locationID: location.id
                        )
                }
            } catch is CancellationError {
                replayingMetadataOperationIDs.remove(operation.id)
                clearMetadataProcessingState(
                    processingFolderID,
                    locationID: location.id
                )
                throw CancellationError()
            } catch {
                replayingMetadataOperationIDs.remove(operation.id)
                clearMetadataProcessingState(
                    processingFolderID,
                    locationID: location.id
                )
                if let documentReference {
                    setFailure(error, operation: operation.cloudOperation, for: documentReference)
                }
                if Self.shouldRetrySynchronization(after: error) {
                    return false
                }
                connections.recordAccessFailure(error, for: location)
                errorsByLocationID[location.id] = error.localizedDescription
                return false
            }

            replayingMetadataOperationIDs.remove(operation.id)
            clearMetadataProcessingState(
                processingFolderID,
                locationID: location.id
            )
        }
        return true
    }

    private func enqueueMove(
        _ item: CloudStorageItem,
        to parentID: CloudStorageItemID?,
        newName: String?,
        location: CloudStorageLocation
    ) throws -> CloudStorageItem {
        var state = persistedStates[location.id] ?? Self.emptyState
        let updatedItem = Self.moving(item, to: parentID, newName: newName)
        state.items.removeAll { $0.id == item.id }
        state.items.append(updatedItem)

        if let createIndex = state.metadataOperations.firstIndex(where: {
            ($0.kind == .createFile || $0.kind == .createFolder)
                && $0.itemID == item.id
                && !replayingMetadataOperationIDs.contains($0.id)
        }) {
            if let parentID {
                state.metadataOperations[createIndex].parentID = parentID
            }
            if let newName {
                state.metadataOperations[createIndex].name = newName
            }
        } else if let moveIndex = state.metadataOperations.lastIndex(where: {
            $0.kind == .moveItem
                && $0.itemID == item.id
                && !replayingMetadataOperationIDs.contains($0.id)
        }) {
            if let parentID {
                state.metadataOperations[moveIndex].parentID = parentID
            }
            if let newName {
                state.metadataOperations[moveIndex].name = newName
            }
        } else {
            state.metadataOperations.append(
                CloudStorageMetadataOperation(
                    kind: .moveItem,
                    itemID: item.id,
                    parentID: parentID,
                    name: newName,
                    revision: item.revision
                )
            )
        }

        apply(state, to: location.id)
        try persist(state, for: location.id)
        return updatedItem
    }

    private func completeMetadataOperation(
        _ operation: CloudStorageMetadataOperation,
        replacing localItem: CloudStorageItem,
        with remoteItem: CloudStorageItem,
        location: CloudStorageLocation,
        uploadedLocalGeneration: UInt64? = nil
    ) async throws {
        let replacements = try migrateItemIdentities(
            replacing: localItem,
            with: remoteItem,
            locationID: location.id,
            removingMetadataOperationID: operation.id
        )
        var state = persistedStates[location.id] ?? Self.emptyState
        if let uploadedLocalGeneration {
            let reference = Self.documentReference(for: remoteItem, in: location)
            if localContentGenerations[reference.id, default: 0] == uploadedLocalGeneration {
                state.dirtyItemIDs.remove(remoteItem.id)
            } else {
                state.dirtyItemIDs.insert(remoteItem.id)
            }
            if let revision = remoteItem.revision {
                state.cachedRevisions[remoteItem.id] = revision
            }
            apply(state, to: location.id)
            try persist(state, for: location.id)
        } else if operation.kind == .moveItem,
                  remoteItem.kind == .file,
                  fileManager.fileExists(
                    atPath: cachedDocumentURL(
                        locationID: location.id,
                        itemID: remoteItem.id
                    ).path
                  ),
                  let revision = remoteItem.revision {
            // A provider may issue a new metadata revision for a rename or
            // move even though file bytes did not change.
            state.cachedRevisions[remoteItem.id] = revision
            apply(state, to: location.id)
            try persist(state, for: location.id)
        }

        let reference = Self.documentReference(for: remoteItem, in: location)
        if remoteItem.kind == .file {
            let persistedState = persistedStates[location.id]
            let hasPendingLocalWork = persistedState?.dirtyItemIDs.contains(remoteItem.id) == true
                || persistedState?.metadataOperations.contains(where: {
                    $0.itemID == remoteItem.id
                }) == true
            if hasPendingLocalWork {
                setSyncState(.queued, for: reference)
            } else {
                setSyncState(.synced(lastVerifiedAt: Date()), for: reference)
            }
        }
        await notifyIdentityChange(
            replacements: replacements,
            location: location
        )
    }

    private func removeMetadataOperation(
        _ operationID: UUID,
        locationID: UUID
    ) throws {
        var state = persistedStates[locationID] ?? Self.emptyState
        state.metadataOperations.removeAll { $0.id == operationID }
        apply(state, to: locationID)
        try persist(state, for: locationID)
    }

    private func clearMetadataProcessingState(
        _ folderID: CloudStorageItemID?,
        locationID: UUID
    ) {
        if let folderID {
            processingFolderIDsByLocationID[locationID]?.remove(folderID)
        }
        if processingFolderIDsByLocationID[locationID]?.isEmpty == true {
            processingFolderIDsByLocationID.removeValue(forKey: locationID)
        }
    }

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

    /// A provider refresh can start before an upload and finish after it. Keep
    /// the upload response authoritative over metadata captured by that older
    /// refresh so its stale revision cannot queue the document again.
    private func recordRemoteContentMutation(
        locationID: UUID,
        itemID: CloudStorageItemID
    ) {
        let key = MetadataMutationKey(locationID: locationID, itemID: itemID)
        remoteContentMutationGeneration &+= 1
        remoteContentMutationGenerationByItem[key] = remoteContentMutationGeneration
    }

    private func wasContentMutated(
        _ key: MetadataMutationKey,
        since generation: UInt64
    ) -> Bool {
        remoteContentMutationGenerationByItem[key, default: 0] > generation
    }

    private func itemIDsMutatedSince(
        _ generation: UInt64,
        in locationID: UUID
    ) -> Set<CloudStorageItemID> {
        Set(remoteContentMutationGenerationByItem.compactMap { key, itemGeneration in
            guard key.locationID == locationID,
                  itemGeneration > generation else { return nil }
            return key.itemID
        })
    }

    /// Some providers use the remote path as item identity. Moving a WebDAV
    /// resource therefore changes the file ID, and moving a folder changes
    /// every descendant ID. Keep the local index and document cache aligned
    /// with that new identity before the next provider refresh arrives.
    private func migrateItemIdentities(
        replacing originalItem: CloudStorageItem,
        with updatedItem: CloudStorageItem,
        locationID: UUID,
        removingMetadataOperationID: UUID? = nil
    ) throws -> [CloudStorageItemID: CloudStorageItem] {
        var state = persistedStates[locationID] ?? Self.emptyState
        let oldPrefix = originalItem.id.rawValue
        let newPrefix = updatedItem.id.rawValue
        var replacements: [CloudStorageItemID: CloudStorageItemID] = [
            originalItem.id: updatedItem.id,
        ]

        if originalItem.kind == .folder {
            for existingItem in state.items where existingItem.id.rawValue.hasPrefix(oldPrefix) {
                let suffix = existingItem.id.rawValue.dropFirst(oldPrefix.count)
                replacements[existingItem.id] = CloudStorageItemID(
                    rawValue: newPrefix + suffix
                )
            }
        }

        let hasFollowUpMutation = state.metadataOperations.contains {
            $0.id != removingMetadataOperationID
                && $0.itemID == originalItem.id
        }

        state.items = state.items.map { existingItem in
            if existingItem.id == originalItem.id {
                return hasFollowUpMutation
                    ? Self.replacingItemIdentity(existingItem, using: replacements)
                    : updatedItem
            }
            return Self.replacingItemIdentity(existingItem, using: replacements)
        }
        state.cachedRevisions = Dictionary(uniqueKeysWithValues: state.cachedRevisions.map { itemID, revision in
            (replacements[itemID] ?? itemID, revision)
        })
        state.dirtyItemIDs = Set(state.dirtyItemIDs.map { replacements[$0] ?? $0 })
        state.metadataOperations = state.metadataOperations
            .filter { $0.id != removingMetadataOperationID }
            .map { $0.replacingItemIDs(using: replacements) }

        for (oldID, newID) in replacements where oldID != newID {
            migrateCachedDocument(
                from: oldID,
                to: newID,
                locationID: locationID
            )
            migrateDocumentRuntimeState(from: oldID, to: newID)

            let oldMutationKey = MetadataMutationKey(locationID: locationID, itemID: oldID)
            let newMutationKey = MetadataMutationKey(locationID: locationID, itemID: newID)
            if let generation = remoteContentMutationGenerationByItem.removeValue(forKey: oldMutationKey) {
                remoteContentMutationGenerationByItem[newMutationKey] = generation
            }
        }

        apply(state, to: locationID)
        try persist(state, for: locationID)
        recordRemoteContentMutation(locationID: locationID, itemID: updatedItem.id)
        return Dictionary(uniqueKeysWithValues: replacements.compactMap { oldID, newID in
            state.items.first(where: { $0.id == newID }).map { (oldID, $0) }
        })
    }

    private static func replacingItemIdentity(
        _ item: CloudStorageItem,
        using replacements: [CloudStorageItemID: CloudStorageItemID]
    ) -> CloudStorageItem {
        let itemID = replacements[item.id] ?? item.id
        let parentID = item.parentID.map { replacements[$0] ?? $0 }
        let remoteURL = replacements[item.id].flatMap { URL(string: $0.rawValue) }
            ?? item.remoteURL
        guard itemID != item.id || parentID != item.parentID || remoteURL != item.remoteURL else {
            return item
        }
        return CloudStorageItem(
            id: itemID,
            parentID: parentID,
            name: item.name,
            kind: item.kind,
            contentType: item.contentType,
            size: item.size,
            createdAt: item.createdAt,
            modifiedAt: item.modifiedAt,
            remoteURL: remoteURL,
            revision: item.revision,
            capabilities: item.capabilities
        )
    }

    private func migrateCachedDocument(
        from oldID: CloudStorageItemID,
        to newID: CloudStorageItemID,
        locationID: UUID
    ) {
        let oldURL = cachedDocumentURL(locationID: locationID, itemID: oldID)
        guard fileManager.fileExists(atPath: oldURL.path) else { return }
        let newURL = cachedDocumentURL(locationID: locationID, itemID: newID)
        do {
            try fileManager.createDirectory(
                at: newURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: newURL)
            try fileManager.moveItem(at: oldURL, to: newURL)
        } catch {
            logger.warning(
                "Unable to migrate cloud document cache after remote rename: \(error)"
            )
        }
    }

    private func migrateDocumentRuntimeState(
        from oldID: CloudStorageItemID,
        to newID: CloudStorageItemID
    ) {
        let oldSuffix = ":\(oldID.rawValue)"
        let matchingDocumentIDs = syncStatesByDocumentID.keys.filter {
            $0.hasSuffix(oldSuffix)
        }
        for oldDocumentID in matchingDocumentIDs {
            let prefix = oldDocumentID.dropLast(oldID.rawValue.count)
            let newDocumentID = String(prefix) + newID.rawValue
            if let syncState = syncStatesByDocumentID.removeValue(forKey: oldDocumentID) {
                syncStatesByDocumentID[newDocumentID] = syncState
            }
            if let generation = localContentGenerations.removeValue(forKey: oldDocumentID) {
                localContentGenerations[newDocumentID] = generation
            }
            FileStatusService.shared.clearStatus(fileID: oldDocumentID)
        }
    }

    private static func moving(
        _ item: CloudStorageItem,
        to parentID: CloudStorageItemID?,
        newName: String?
    ) -> CloudStorageItem {
        CloudStorageItem(
            id: item.id,
            parentID: parentID ?? item.parentID,
            name: newName ?? item.name,
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

    private static func pendingItem(
        name: String,
        kind: CloudStorageItem.Kind,
        parentID: CloudStorageItemID
    ) -> CloudStorageItem {
        let now = Date()
        return CloudStorageItem(
            id: .pendingLocalID(),
            parentID: parentID,
            name: name,
            kind: kind,
            contentType: nil,
            size: nil,
            createdAt: now,
            modifiedAt: now,
            remoteURL: nil,
            revision: nil,
            capabilities: kind == .folder ? .writableFolder : .writableFile
        )
    }

    private static func documentReference(
        for item: CloudStorageItem,
        in location: CloudStorageLocation
    ) -> CloudStorageDocumentReference {
        CloudStorageDocumentReference(
            locationID: location.id,
            providerID: location.providerID,
            accountID: location.accountID,
            itemID: item.id,
            lastKnownName: item.name,
            lastKnownModifiedAt: item.modifiedAt
        )
    }

    private func notifyIdentityChange(
        replacements: [CloudStorageItemID: CloudStorageItem],
        location: CloudStorageLocation
    ) async {
        let changedReplacements = replacements.filter { $0.key != $0.value.id }
        guard !changedReplacements.isEmpty else { return }
        let change = CloudStorageItemIdentityChange(
            location: location,
            replacements: changedReplacements
        )
        do {
            try await CloudStorageCheckpointStore.migrateIdentities(change)
        } catch {
            logger.warning(
                "Failed to migrate cloud document checkpoint identities: \(error)"
            )
        }
        NotificationCenter.default.post(
            name: .cloudStorageItemIdentityDidChange,
            object: change
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
        } else if Self.shouldRetrySynchronization(after: error) {
            setPendingSyncState(for: reference)
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

    private func setPendingSyncState(
        for reference: CloudStorageDocumentReference
    ) {
        setSyncState(
            reference.itemID.isPendingLocalID ? .local : .queued,
            for: reference
        )
    }

    private static func revisionsMatch(
        cached: String?,
        remote: String?
    ) -> Bool {
        guard let cached, let remote else { return false }
        return cached == remote
    }

    private func notifyDocumentContentDidChange(
        _ reference: CloudStorageDocumentReference
    ) {
        NotificationCenter.default.post(
            name: .cloudStorageDocumentContentDidChange,
            object: reference
        )
    }

    private func notifyConflictDidResolve(
        _ reference: CloudStorageDocumentReference,
        keptVersion: CloudStorageConflictVersion,
        content: Data
    ) {
        NotificationCenter.default.post(
            name: .cloudStorageConflictDidResolve,
            object: CloudStorageConflictResolutionResult(
                reference: reference,
                keptVersion: keptVersion,
                content: content
            )
        )
    }

    private func cancelPendingDocumentWork(
        for reference: CloudStorageDocumentReference
    ) async {
        let retryTask = retryUploadTasks[reference.id]
        let saveTask = saveTasks[reference.id]
        let synchronizationTask = contentSynchronizationTasks[reference.id]

        retryTask?.cancel()
        retryUploadTasks[reference.id] = nil
        retryUploadTaskIDs[reference.id] = nil
        saveTask?.cancel()
        saveTasks[reference.id] = nil
        saveTaskIDs[reference.id] = nil
        synchronizationTask?.cancel()
        contentSynchronizationTasks[reference.id] = nil
        contentSynchronizationQueue[reference.id] = nil
        activeContentSynchronizationPriorities[reference.id] = nil

        await retryTask?.value
        _ = try? await saveTask?.value
        await synchronizationTask?.value
    }

    private static func representsSameRemoteRevision(
        _ lhs: CloudStorageItem,
        _ rhs: CloudStorageItem
    ) -> Bool {
        if lhs.revision != nil || rhs.revision != nil {
            return lhs.revision == rhs.revision
        }
        return lhs.modifiedAt == rhs.modifiedAt && lhs.size == rhs.size
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
        cachedDocumentURL(
            locationID: reference.locationID,
            itemID: reference.itemID
        )
    }

    private func cachedDocumentURL(
        locationID: UUID,
        itemID: CloudStorageItemID
    ) -> URL {
        locationDirectoryURL(locationID)
            .appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: Self.cacheFileName(for: itemID))
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
        dirtyItemIDs: [],
        metadataOperations: []
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

    /// A complete provider listing can finish after a local-first delete was
    /// staged. Keep that stale snapshot from resurrecting the deleted subtree
    /// while its durable metadata operation is still pending.
    private static func removingPendingDeletionTombstones(
        from items: [CloudStorageItem],
        operations: [CloudStorageMetadataOperation]
    ) -> [CloudStorageItem] {
        var removedIDs = Set(
            operations.lazy
                .filter { $0.kind == .deleteItem }
                .map(\.itemID)
        )
        guard !removedIDs.isEmpty else { return items }

        var didExpand = true
        while didExpand {
            didExpand = false
            for item in items where !removedIDs.contains(item.id) {
                guard let parentID = item.parentID,
                      removedIDs.contains(parentID) else { continue }
                removedIDs.insert(item.id)
                didExpand = true
            }
        }
        return items.filter { !removedIDs.contains($0.id) }
    }

    private static func cacheFileName(for itemID: CloudStorageItemID) -> String {
        Data(itemID.rawValue.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private func documentIDBelongsToLocation(
        _ documentID: String,
        locationID: UUID
    ) -> Bool {
        documentID.contains(":\(locationID.uuidString):")
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    private static func shouldRetrySynchronization(after error: Error) -> Bool {
        if let cloudError = error as? CloudStorageError,
           case .rateLimited = cloudError {
            return true
        }

        var currentError: NSError? = error as NSError
        while let candidate = currentError {
            if candidate.domain == NSURLErrorDomain,
               retryableURLRequestErrorCodes.contains(candidate.code) {
                return true
            }
            currentError = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    private static let retryableURLRequestErrorCodes: Set<Int> = [
        NSURLErrorTimedOut,
        NSURLErrorCannotFindHost,
        NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost,
        NSURLErrorDNSLookupFailed,
        NSURLErrorNotConnectedToInternet,
        NSURLErrorInternationalRoamingOff,
        NSURLErrorCallIsActive,
        NSURLErrorDataNotAllowed,
        NSURLErrorCannotLoadFromNetwork,
    ]

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
            if Self.folderSyncStatePriority(state) > Self.folderSyncStatePriority(currentState) {
                states[currentFolderID] = state
            }
            guard currentFolderID != rootID,
                  let parentID = parentIDByFolderID[currentFolderID] else {
                break
            }
            currentFolderID = parentID
        }
    }

    private static func folderSyncStatePriority(
        _ state: CloudStorageFolderSyncState
    ) -> Int {
        switch state {
            case .idle:
                0
            case .queued(.download):
                1
            case .queued(.upload):
                2
            case .synchronizing:
                3
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
