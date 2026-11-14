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
    func injectAllMediaItems(onlyMissing: Bool = false, matching requiredIDs: Set<String>? = nil) async throws -> Int {
        let hasParent = await MainActor.run {
            parent != nil
        }
        guard hasParent else {
            return 0
        }

        let isReady = await MainActor.run {
            !isNavigating && isDocumentLoaded
        }

        guard isReady else {
            logger.warning("WebView not ready for MediaItem injection, skipping")
            return 0
        }

        let loadedIDs = await MainActor.run { loadedMediaItemIDSnapshot() }
        let context = PersistenceController.shared.newTaskContext()
        let mediaObjectIDs = try await context.perform {
            let allMediasFetch = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            if let requiredIDs { allMediasFetch.predicate = NSPredicate(format: "id IN %@", Array(requiredIDs)) }
            return try context.fetch(allMediasFetch).filter { item in
                !onlyMissing || item.id.map { !loadedIDs.contains($0) } == true
            }.map(\.objectID)
        }

        let mediaFiles = await withTaskGroup(of: ExcalidrawFile.ResourceFile?.self) { group in
            var files: [ExcalidrawFile.ResourceFile] = []

            for id in mediaObjectIDs {
                group.addTask {
                    guard let mediaItem = try? await context.perform({
                        try context.existingObject(with: id) as? MediaItem
                    }) else { return nil }
                    return try? await ExcalidrawFile.ResourceFile(mediaItem: mediaItem)
                }
            }

            for await resourceFile in group {
                if let resourceFile = resourceFile {
                    files.append(resourceFile)
                }
            }

            return files
        }

        try Task.checkCancellation()
        try await self.insertMediaFiles(mediaFiles)
        await MainActor.run {
            // insertMediaFiles records only successfully injected IDs. Failed reads
            // must remain missing so reopening the file can retry them.
            self.hasInjectIndexedDBData = true
        }
        let failedCount = mediaObjectIDs.count - mediaFiles.count
        if failedCount > 0 {
            logger.warning("Could not restore \(failedCount) MediaItems; they remain eligible for retry")
        }

        return mediaFiles.count
    }

    /// Check if MediaItems have changed and re-inject if needed
    /// This is the public method that should be called when MediaItem changes are detected
    public func refreshMediaItemsIfNeeded(referencedBy data: Data? = nil) async throws {
        let requiredIDs: Set<String>?
        if let data {
            let references = try JSONDecoder().decode(MediaReferences.self, from: data)
            // External documents can already contain their image data. Native
            // hydration is needed for references whose bytes live in app storage.
            let embeddedIDs = references.files?.compactMap { id, file in
                file.dataURL?.isEmpty == false ? id : nil
            } ?? []
            requiredIDs = Set(references.elements?.compactMap(\.fileId) ?? []).subtracting(embeddedIDs)
        } else {
            requiredIDs = nil
        }
        let context = PersistenceController.shared.newTaskContext()
        let currentIDs = try await context.perform {
            let fetchRequest = NSFetchRequest<NSDictionary>(entityName: "MediaItem")
            fetchRequest.resultType = .dictionaryResultType
            fetchRequest.propertiesToFetch = ["id"]
            if let requiredIDs { fetchRequest.predicate = NSPredicate(format: "id IN %@", Array(requiredIDs)) }
            return Set(try context.fetch(fetchRequest).compactMap { $0["id"] as? String })
        }
        let needsInjection = await MainActor.run {
            !hasInjectIndexedDBData || !currentIDs.isSubset(of: loadedMediaItemIDSnapshot())
        }
        if needsInjection {
            _ = try await injectAllMediaItems(onlyMissing: true, matching: requiredIDs)
        }
    }

    private struct MediaReferences: Decodable {
        struct Element: Decodable { var fileId: String? }
        struct EmbeddedFile: Decodable { var dataURL: String? }
        var elements: [Element]?
        var files: [String: EmbeddedFile]?
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
