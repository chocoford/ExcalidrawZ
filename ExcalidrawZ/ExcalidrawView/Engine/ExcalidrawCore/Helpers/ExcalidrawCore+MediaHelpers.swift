//
//  ExcalidrawCore+MediaHelpers.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/18.
//

import CoreData
import Foundation

extension ExcalidrawCore {
    /// Get Excalidraw Indexed DB Data
    func getExcalidrawStore() async throws -> [ExcalidrawFile.ResourceFile] {
        let raw = try await webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.getAllMedias();",
            arguments: [:],
            contentWorld: .page
        )
        guard let dict = raw as? [String: Any], let filesAny = dict["files"] else {
            struct GetAllMediasFailed: Error {}
            throw GetAllMediasFailed()
        }
        let data = try JSONSerialization.data(withJSONObject: filesAny)
        return try JSONDecoder().decode([ExcalidrawFile.ResourceFile].self, from: data)
    }

    /// Insert media files to IndexedDB
    @MainActor
    func insertMediaFiles(_ files: [ExcalidrawFile.ResourceFile]) async throws {
        guard !files.isEmpty else { return }

        let jsonStringified = try files.jsonStringified()
        _ = try await webView.callAsyncJavaScript(
            """
            return await window.excalidrawZHelper.insertMedias(filesJSON);
            """,
            arguments: [
                "filesJSON": jsonStringified,
            ],
            contentWorld: .page
        )

        var loadedIDs = loadedMediaItemIDSnapshot()
        loadedIDs.formUnion(files.map(\.id))
        updateLoadedMediaItemIDs(loadedIDs)
    }

    /// Inject all MediaItems from CoreData to IndexedDB
    /// This method fetches all MediaItems and injects them into the WebView's IndexedDB
    /// Most work (fetching, loading files) runs on background threads for better performance
    /// - Returns: The count of injected MediaItems
    func injectAllMediaItems() async throws -> Int {
        let hasParent = await MainActor.run {
            parent != nil
        }
        guard hasParent else {
            return 0
        }

        let isReady = await MainActor.run {
            !isNavigating && (hasInjectIndexedDBData || isDocumentLoaded)
        }

        guard isReady else {
            logger.warning("WebView not ready for MediaItem injection, skipping")
            return 0
        }

        let context = PersistenceController.shared.newTaskContext()
        let allMedias = try await context.perform {
            let allMediasFetch = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            return try context.fetch(allMediasFetch)
        }
        let allMediaIDs = allMedias.compactMap(\.id)

        let mediaFiles = await withTaskGroup(of: ExcalidrawFile.ResourceFile?.self) { group in
            var files: [ExcalidrawFile.ResourceFile] = []

            for id in allMedias.map({ $0.objectID }) {
                group.addTask {
                    if let mediaItem = context.object(with: id) as? MediaItem {
                        return try? await ExcalidrawFile.ResourceFile(mediaItem: mediaItem)
                    }
                    return nil
                }
            }

            for await resourceFile in group {
                if let resourceFile = resourceFile {
                    files.append(resourceFile)
                }
            }

            return files
        }

        try await self.insertMediaFiles(mediaFiles)
        await MainActor.run {
            self.updateLoadedMediaItemIDs(Set(allMediaIDs))
            self.hasInjectIndexedDBData = true
        }

        return mediaFiles.count
    }

    /// Check if MediaItems have changed and re-inject if needed
    /// This is the public method that should be called when MediaItem changes are detected
    public func refreshMediaItemsIfNeeded() async throws {
        let (currentIDs, loadedIDs) = try await MainActor.run {
            let context = PersistenceController.shared.container.viewContext
            let fetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            fetchRequest.propertiesToFetch = ["id"]

            let currentMedias = try context.fetch(fetchRequest)
            let currentIDs = Set(currentMedias.compactMap { $0.id })

            return (currentIDs, self.loadedMediaItemIDSnapshot())
        }

        let hasChanges = currentIDs != loadedIDs

        if hasChanges {
            _ = try await injectAllMediaItems()
        }
    }

    @MainActor
    @discardableResult
    public func loadImageToExcalidrawCanvas(imageData: Data, type: String) async throws -> LoadImageResult? {
        var buffer = [UInt8].init(repeating: 0, count: imageData.count)
        imageData.copyBytes(to: &buffer, count: imageData.count)
        let buf = buffer
        let raw = try await webView.callAsyncJavaScript(
            "return await window.excalidrawZHelper.loadImageBuffer(\(buf), type);",
            arguments: ["type": type],
            contentWorld: .page
        )
        let result = LoadImageResult(fromJS: raw)
        documentSyncController.scheduleProgrammaticMutationCommit(reason: "loadImageToExcalidrawCanvas")
        return result
    }
}
