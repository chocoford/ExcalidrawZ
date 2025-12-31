//
//  OrphanCleaner.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/12/31.
//

import Foundation
import CoreData
import Logging

/// Clean up orphaned files (files without corresponding CoreData entities)
struct OrphanCleaner {
    private let logger = Logger(label: "OrphanCleaner")
    private let localManager: LocalStorageManager
    private let iCloudManager: iCloudDriveFileManager

    init(localManager: LocalStorageManager, iCloudManager: iCloudDriveFileManager) {
        self.localManager = localManager
        self.iCloudManager = iCloudManager
    }

    // MARK: - Cleanup Operations

    /// Remove files that don't have corresponding CoreData entities
    func cleanupOrphanedFiles(
        localFiles: [SyncFileState],
        iCloudFiles: [SyncFileState]
    ) async {
        let validFileIDs = await getValidFileIDs()
        var deletedCount = 0

        // Clean up local orphaned files
        for file in localFiles {
            let validIDs = getValidIDs(for: file.contentType, from: validFileIDs)
            if !validIDs.contains(file.fileID) {
                logger.info("Removing orphaned local file: \(file.relativePath)")
                try? await localManager.deleteContent(relativePath: file.relativePath)
                deletedCount += 1
            }
        }

        // Clean up iCloud orphaned files
        for file in iCloudFiles {
            let validIDs = getValidIDs(for: file.contentType, from: validFileIDs)
            if !validIDs.contains(file.fileID) {
                logger.info("Removing orphaned iCloud file: \(file.relativePath)")
                try? await iCloudManager.deleteContent(relativePath: file.relativePath)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            logger.info("Cleaned up \(deletedCount) orphaned file(s)")
        }
    }

    // MARK: - Helper Methods

    /// Get all valid file IDs from CoreData entities
    private func getValidFileIDs() async -> [FileStorageContentType: Set<String>] {
        let context = PersistenceController.shared.newTaskContext()
        var result: [FileStorageContentType: Set<String>] = [:]

        // Fetch File IDs
        do {
            let fileRequest: NSFetchRequest<NSFetchRequestResult> = File.fetchRequest()
            fileRequest.propertiesToFetch = ["id"]
            fileRequest.resultType = .dictionaryResultType
            let fileResults = try context.fetch(fileRequest) as? [[String: Any]] ?? []
            let fileIDs = fileResults.compactMap { ($0["id"] as? UUID)?.uuidString }
            result[.file] = Set(fileIDs)
        } catch {
            result[.file] = Set()
        }

        // Fetch CollaborationFile IDs
        do {
            let collabRequest: NSFetchRequest<NSFetchRequestResult> = CollaborationFile.fetchRequest()
            collabRequest.propertiesToFetch = ["id"]
            collabRequest.resultType = .dictionaryResultType
            let collabResults = try context.fetch(collabRequest) as? [[String: Any]] ?? []
            let collabIDs = collabResults.compactMap { ($0["id"] as? UUID)?.uuidString }
            result[.collaborationFile] = Set(collabIDs)
        } catch {
            result[.collaborationFile] = Set()
        }

        // Fetch FileCheckpoint IDs
        do {
            let checkpointRequest: NSFetchRequest<NSFetchRequestResult> = FileCheckpoint.fetchRequest()
            checkpointRequest.propertiesToFetch = ["id"]
            checkpointRequest.resultType = .dictionaryResultType
            let checkpointResults = try context.fetch(checkpointRequest) as? [[String: Any]] ?? []
            let checkpointIDs = checkpointResults.compactMap { ($0["id"] as? UUID)?.uuidString }
            result[.checkpoint] = Set(checkpointIDs)
        } catch {
            result[.checkpoint] = Set()
        }

        // Fetch MediaItem IDs
        do {
            let mediaRequest: NSFetchRequest<NSFetchRequestResult> = MediaItem.fetchRequest()
            mediaRequest.propertiesToFetch = ["id"]
            mediaRequest.resultType = .dictionaryResultType
            let mediaResults = try context.fetch(mediaRequest) as? [[String: Any]] ?? []
            let mediaIDs = mediaResults.compactMap { $0["id"] as? String }
            result[.mediaItem(extension: "")] = Set(mediaIDs)
        } catch {
            result[.mediaItem(extension: "")] = Set()
        }

        return result
    }

    /// Get valid IDs for a specific content type
    private func getValidIDs(
        for contentType: FileStorageContentType,
        from validFileIDs: [FileStorageContentType: Set<String>]
    ) -> Set<String> {
        // For media items, use the base media item key (ignoring extension)
        if case .mediaItem = contentType {
            return validFileIDs[.mediaItem(extension: "")] ?? []
        }
        return validFileIDs[contentType] ?? []
    }
}
