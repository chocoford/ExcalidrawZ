//
//  CloudStorageFolderPickerModel.swift
//  ExcalidrawZ
//

import Combine
import SwiftUI

@MainActor
final class CloudStorageFolderPickerModel: ObservableObject {
    @Published private(set) var path: [CloudStorageItem] = []
    @Published private(set) var folders: [CloudStorageItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let session: any CloudStorageSession
    private var folderCache: [CloudStorageItemID: [CloudStorageItem]] = [:]
    private var folderRequests: [CloudStorageItemID: Task<[CloudStorageItem], Error>] = [:]
    private var prefetchTask: Task<Void, Never>?

    init(session: any CloudStorageSession) {
        self.session = session
    }

    var currentFolder: CloudStorageItem? {
        path.last
    }

    func start() async {
        guard path.isEmpty else { return }
        await load {
            let root = try await session.rootItem()
            let folders = try await folders(in: root.id)
            withAnimation(.smooth(duration: 0.28)) {
                path = [root]
                self.folders = folders
            }
            prefetchChildren(of: folders)
        }
    }

    func open(_ folder: CloudStorageItem) async {
        guard folder.kind == .folder, !isLoading else { return }

        if let cachedFolders = folderCache[folder.id] {
            show(folder: folder, folders: cachedFolders)
            return
        }

        withAnimation(.smooth(duration: 0.28)) {
            path.append(folder)
            folders = []
        }
        await load {
            let folders = try await folders(in: folder.id)
            guard currentFolder?.id == folder.id else { return }
            withAnimation(.smooth(duration: 0.2)) {
                self.folders = folders
            }
            prefetchChildren(of: folders)
        }
    }

    func goBack() async {
        guard path.count > 1 else { return }
        let previousFolder = path[path.count - 2]

        if let cachedFolders = folderCache[previousFolder.id] {
            showPreviousFolder(folders: cachedFolders)
            return
        }

        await load {
            let folders = try await folders(in: previousFolder.id)
            showPreviousFolder(folders: folders)
        }
    }

    func cancelPendingRequests() {
        prefetchTask?.cancel()
        prefetchTask = nil
        folderRequests.values.forEach { $0.cancel() }
        folderRequests.removeAll()
    }

    private func show(folder: CloudStorageItem, folders: [CloudStorageItem]) {
        withAnimation(.smooth(duration: 0.28)) {
            path.append(folder)
            self.folders = folders
        }
        prefetchChildren(of: folders)
    }

    private func showPreviousFolder(folders: [CloudStorageItem]) {
        withAnimation(.smooth(duration: 0.28)) {
            path.removeLast()
            self.folders = folders
        }
        prefetchChildren(of: folders)
    }

    private func load(_ operation: () async throws -> Void) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await operation()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func folders(in folderID: CloudStorageItemID) async throws -> [CloudStorageItem] {
        if let cachedFolders = folderCache[folderID] {
            return cachedFolders
        }
        if let request = folderRequests[folderID] {
            return try await request.value
        }

        let session = session
        let request = Task<[CloudStorageItem], Error> {
            var nextPageToken: String?
            var loadedFolders: [CloudStorageItem] = []

            repeat {
                let page = try await session.listChildren(
                    of: folderID,
                    pageToken: nextPageToken
                )
                loadedFolders.append(contentsOf: page.items.filter { $0.kind == .folder })
                nextPageToken = page.nextPageToken
            } while nextPageToken != nil

            return loadedFolders.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        folderRequests[folderID] = request
        defer { folderRequests[folderID] = nil }

        let folders = try await request.value
        folderCache[folderID] = folders
        return folders
    }

    private func prefetchChildren(of folders: [CloudStorageItem]) {
        prefetchTask?.cancel()
        let folderIDs = Array(folders.prefix(12).map(\.id))
        prefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for batchStart in stride(from: 0, to: folderIDs.count, by: 4) {
                guard !Task.isCancelled else { return }
                let batchEnd = min(batchStart + 4, folderIDs.count)
                let batch = folderIDs[batchStart..<batchEnd]
                await withTaskGroup(of: Void.self) { group in
                    for folderID in batch {
                        group.addTask { [weak self] in
                            guard let self else { return }
                            _ = try? await self.folders(in: folderID)
                        }
                    }
                }
            }
        }
    }
}
