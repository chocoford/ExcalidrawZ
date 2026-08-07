//
//  CloudStorageSidebarBrowserModel.swift
//  ExcalidrawZ
//

import Combine
import Foundation
import Logging

@MainActor
final class CloudStorageSidebarBrowserModel: ObservableObject {
    @Published private(set) var stateRevision = 0

    let location: CloudStorageLocation

    private let documentStore: CloudStorageDocumentStore
    private let logger = Logger(label: "CloudStorageSidebarBrowserModel")
    private var storeCancellables = Set<AnyCancellable>()
    private var folderSyncStatesCache: [CloudStorageItemID: CloudStorageFolderSyncState]?

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
        let locationID = location.id

        documentStore.$metadataRevisionsByLocationID
            .map { revisions in revisions[locationID, default: 0] }
            .removeDuplicates()
            .sink { [weak self] metadataRevision in
                Task { @MainActor [weak self] in
                    self?.invalidate(reason: "metadataRevision=\(metadataRevision)")
                }
            }
            .store(in: &storeCancellables)

        documentStore.$refreshingLocationIDs
            .map { refreshingIDs in refreshingIDs.contains(locationID) }
            .removeDuplicates()
            .sink { [weak self] isRefreshing in
                Task { @MainActor [weak self] in
                    self?.invalidate(reason: "refreshing=\(isRefreshing)")
                }
            }
            .store(in: &storeCancellables)

        documentStore.$errorsByLocationID
            .map { errors in errors[locationID] }
            .removeDuplicates()
            .sink { [weak self] errorMessage in
                Task { @MainActor [weak self] in
                    self?.invalidate(reason: "error=\(errorMessage ?? "none")")
                }
            }
            .store(in: &storeCancellables)

        let locationMarker = ":\(locationID.uuidString):"
        documentStore.$syncStatesByDocumentID
            .map { states in
                Set(states.compactMap { documentID, state -> String? in
                    guard documentID.contains(locationMarker) else { return nil }
                    if state.isActivelySynchronizing {
                        return "active:\(documentID)"
                    }
                    if state == .queued {
                        return "queued:\(documentID)"
                    }
                    return nil
                })
            }
            .removeDuplicates()
            .sink { [weak self] synchronizationSignature in
                Task { @MainActor [weak self] in
                    self?.invalidate(reason: "syncStates=\(synchronizationSignature.count)")
                }
            }
            .store(in: &storeCancellables)

        documentStore.$processingFolderIDsByLocationID
            .map { folderIDsByLocationID in
                folderIDsByLocationID[locationID, default: []]
            }
            .removeDuplicates()
            .sink { [weak self] processingFolderIDs in
                Task { @MainActor [weak self] in
                    self?.invalidate(reason: "processingFolders=\(processingFolderIDs.count)")
                }
            }
            .store(in: &storeCancellables)
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

    func isFolder(
        _ folderID: CloudStorageItemID,
        inPathTo target: CloudStorageFolderReference
    ) -> Bool {
        guard target.location.id == location.id else { return false }
        return documentStore.folderPath(for: target).contains { folder in
            folder.itemID == folderID
        }
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
