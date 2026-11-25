//
//  CloudStorageSidebarBrowserModel.swift
//  ExcalidrawZ
//

import Observation
import Combine
import Foundation
import Logging

@MainActor
@Observable
final class CloudStorageSidebarBrowserModel {
    private(set) var stateRevision = 0

    let location: CloudStorageLocation

    private let documentStore: CloudStorageDocumentStore
    private let logger = Logger(label: "CloudStorageSidebarBrowserModel")
    @ObservationIgnored private var storeObservation: ObservationSubscription?
    @ObservationIgnored private var folderSyncStatesCache: [CloudStorageItemID: CloudStorageFolderSyncState]?

    convenience init(location: CloudStorageLocation) {
        self.init(
            location: location,
            documentStore: CloudStorageDocumentStore.shared
        )
    }

    init(
        location: CloudStorageLocation,
        documentStore: CloudStorageDocumentStore
    ) {
        self.location = location
        self.documentStore = documentStore
        self.stateRevision = documentStore.metadataRevision(for: location.id)
        storeObservation = ObservationSubscription { [documentStore, location] in
            let locationMarker = ":\(location.id.uuidString):"
            let synchronizing = Set(documentStore.syncStatesByDocumentID.compactMap { documentID, state -> String? in
                guard documentID.contains(locationMarker) else { return nil }
                if state.isVisiblySynchronizing { return "active:\(documentID)" }
                if state == .queued { return "queued:\(documentID)" }
                return nil
            })
            return CloudBrowserSnapshot(
                metadataRevision: documentStore.metadataRevision(for: location.id),
                isRefreshing: documentStore.isRefreshing(location),
                error: documentStore.errorMessage(for: location),
                synchronizing: synchronizing,
                processingFolders: documentStore.processingFolderIDsByLocationID[location.id, default: []]
            )
        } onChange: { [weak self] _ in
            self?.invalidate(reason: "observedStateChanged")
        }
    }

    private struct CloudBrowserSnapshot: Equatable {
        var metadataRevision: Int
        var isRefreshing: Bool
        var error: String?
        var synchronizing: Set<String>
        var processingFolders: Set<CloudStorageItemID>
    }

    private func invalidate(reason: String) {
        folderSyncStatesCache = nil
        stateRevision &+= 1
#if DEBUG
        logger.debug(
            "Observed cloud browser state location=\(location.displayName) id=\(location.id) \(reason)"
        )
#endif
    }

    func items(
        in folderID: CloudStorageItemID,
        sortedBy sortField: ExcalidrawFileSortField
    ) -> [CloudStorageItem]? {
        _ = stateRevision
        guard let items = documentStore.items(in: location, parentID: folderID) else {
            return nil
        }
        return sorted(items.filter { $0.kind == .folder }, by: .name)
            + sorted(items.filter { $0.kind != .folder }, by: sortField)
    }

    private func sorted(
        _ items: [CloudStorageItem],
        by sortField: ExcalidrawFileSortField
    ) -> [CloudStorageItem] {
        ExcalidrawFileSortProvider.sorted(items, by: sortField) { item in
            ExcalidrawFileSortProvider.Values(
                name: item.name,
                updatedAt: item.modifiedAt,
                createdAt: item.createdAt
            )
        }
    }

    var isRefreshing: Bool {
        _ = stateRevision
        return documentStore.isRefreshing(location)
    }

    var errorMessage: String? {
        _ = stateRevision
        return documentStore.errorMessage(for: location)
    }

    func folderIDs(inPathTo folder: CloudStorageFolderReference) -> Set<CloudStorageItemID> {
        Set(documentStore.folderPath(for: folder).map(\.itemID))
    }

    func folderSyncState(in folderID: CloudStorageItemID) -> CloudStorageFolderSyncState {
        _ = stateRevision
        if folderSyncStatesCache == nil {
            folderSyncStatesCache = documentStore.folderSyncStates(in: location)
        }
        return folderSyncStatesCache?[folderID] ?? .idle
    }

    func refresh(
        connections: CloudStorageConnectionStore,
        force: Bool = true
    ) async {
        await documentStore.refresh(location, connections: connections, force: force)
    }

}
