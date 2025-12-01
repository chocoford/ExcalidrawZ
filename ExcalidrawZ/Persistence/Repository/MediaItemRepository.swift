//
//  MediaItemRepository.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/21.
//

import Foundation
import CoreData
import Logging

/// Actor responsible for MediaItem entity operations with iCloud Drive integration
actor MediaItemRepository {
    private let logger = Logger(label: "MediaItemRepository")

    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Create MediaItem

    /// Create a new media item with data URL and save to iCloud Drive
    /// - Parameters:
    ///   - resource: The resource file containing media data
    ///   - fileObjectID: The file to add the media item to
    /// - Returns: The objectID of the created media item
    func createMediaItem(
        resource: ExcalidrawFile.ResourceFile,
        fileObjectID: NSManagedObjectID
    ) async throws -> NSManagedObjectID {
        // Create media item entity with dataURL as fallback
        let mediaItemObjectID = try await context.perform {
            guard let file = self.context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }

            let mediaItem = MediaItem(resource: resource, context: self.context)
            mediaItem.file = file
            self.context.insert(mediaItem)
            try self.context.save()

            return mediaItem.objectID
        }

        // Save media data URL to storage
        try await saveMediaItemToStorage(mediaItemObjectID: mediaItemObjectID, dataURL: resource.dataURL)

        return mediaItemObjectID
    }

    /// Create multiple media items in batch
    /// - Parameters:
    ///   - resources: Array of resource files
    ///   - fileObjectID: The file to add the media items to
    /// - Returns: Array of created media item objectIDs
    func createMediaItems(
        resources: [ExcalidrawFile.ResourceFile],
        fileObjectID: NSManagedObjectID
    ) async throws -> [NSManagedObjectID] {
        var mediaItemObjectIDs: [NSManagedObjectID] = []

        // Get existing media items to avoid duplicates
        let allMediaItems = try await context.perform {
            try self.context.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
        }

        // Filter resources that need to be imported
        let resourcesToImport = resources.filter { resource in
            !allMediaItems.contains(where: { $0.id == resource.id })
        }

        // Create media items
        for resource in resourcesToImport {
            let mediaItemObjectID = try await createMediaItem(resource: resource, fileObjectID: fileObjectID)
            mediaItemObjectIDs.append(mediaItemObjectID)
        }

        return mediaItemObjectIDs
    }

    /// Create a new media item for CollaborationFile with data URL and save to iCloud Drive
    /// - Parameters:
    ///   - resource: The resource file containing media data
    ///   - collaborationFileObjectID: The collaboration file to add the media item to
    /// - Returns: The objectID of the created media item
    func createMediaItemForCollaborationFile(
        resource: ExcalidrawFile.ResourceFile,
        collaborationFileObjectID: NSManagedObjectID
    ) async throws -> NSManagedObjectID {
        // Create media item entity with dataURL as fallback
        let mediaItemObjectID = try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                throw AppError.fileError(.notFound)
            }

            let mediaItem = MediaItem(resource: resource, context: self.context)
            mediaItem.collaborationFile = collaborationFile
            self.context.insert(mediaItem)
            try self.context.save()

            return mediaItem.objectID
        }

        // Save media data URL to storage
        try await saveMediaItemToStorage(mediaItemObjectID: mediaItemObjectID, dataURL: resource.dataURL)

        return mediaItemObjectID
    }

    /// Create multiple media items for CollaborationFile in batch
    /// - Parameters:
    ///   - resources: Array of resource files
    ///   - collaborationFileObjectID: The collaboration file to add the media items to
    /// - Returns: Array of created media item objectIDs
    func createMediaItemsForCollaborationFile(
        resources: [ExcalidrawFile.ResourceFile],
        collaborationFileObjectID: NSManagedObjectID
    ) async throws -> [NSManagedObjectID] {
        var mediaItemObjectIDs: [NSManagedObjectID] = []

        // Get existing media items to avoid duplicates
        let allMediaItems = try await context.perform {
            try self.context.fetch(NSFetchRequest<MediaItem>(entityName: "MediaItem"))
        }

        // Filter resources that need to be imported
        let resourcesToImport = resources.filter { resource in
            !allMediaItems.contains(where: { $0.id == resource.id })
        }

        // Create media items
        for resource in resourcesToImport {
            let mediaItemObjectID = try await createMediaItemForCollaborationFile(
                resource: resource,
                collaborationFileObjectID: collaborationFileObjectID
            )
            mediaItemObjectIDs.append(mediaItemObjectID)
        }

        return mediaItemObjectIDs
    }

    /// Sync media items from ExcalidrawFile to File
    /// Creates new MediaItems for resources that don't exist yet
    /// - Parameters:
    ///   - excalidrawFile: The ExcalidrawFile containing resources
    ///   - fileObjectID: The File to sync media items to
    /// - Returns: Array of created media item objectIDs
    func syncMediaItemsForFile(
        excalidrawFile: ExcalidrawFile,
        fileObjectID: NSManagedObjectID
    ) async throws -> [NSManagedObjectID] {
        // Get new medias that don't exist yet
        let newMedias = try await context.perform {
            guard let file = self.context.object(with: fileObjectID) as? File else {
                throw AppError.fileError(.notFound)
            }

            return excalidrawFile.files.filter { (id, _) in
                file.medias?.contains(where: {
                    ($0 as? MediaItem)?.id == id
                }) != true
            }
        }

        // Create media items through repository (will save to iCloud Drive)
        guard !newMedias.isEmpty else {
            return []
        }

        let resources = Array(newMedias.values)
        return try await createMediaItems(
            resources: resources,
            fileObjectID: fileObjectID
        )
    }

    /// Sync media items from ExcalidrawFile to CollaborationFile
    /// Creates new MediaItems for resources that don't exist yet
    /// - Parameters:
    ///   - excalidrawFile: The ExcalidrawFile containing resources
    ///   - collaborationFileObjectID: The CollaborationFile to sync media items to
    /// - Returns: Array of created media item objectIDs
    func syncMediaItemsForCollaborationFile(
        excalidrawFile: ExcalidrawFile,
        collaborationFileObjectID: NSManagedObjectID
    ) async throws -> [NSManagedObjectID] {
        // Get new medias that don't exist yet
        let newMedias = try await context.perform {
            guard let collaborationFile = self.context.object(with: collaborationFileObjectID) as? CollaborationFile else {
                throw AppError.fileError(.notFound)
            }

            return excalidrawFile.files.filter { (id, _) in
                collaborationFile.medias?.contains(where: {
                    ($0 as? MediaItem)?.id == id
                }) != true
            }
        }

        // Create media items through repository (will save to iCloud Drive)
        guard !newMedias.isEmpty else {
            return []
        }

        let resources = Array(newMedias.values)
        return try await createMediaItemsForCollaborationFile(
            resources: resources,
            collaborationFileObjectID: collaborationFileObjectID
        )
    }

    // MARK: - Load MediaItem

    /// Load media item data URL from iCloud Drive or CoreData
    /// - Parameter mediaItemObjectID: The media item objectID
    /// - Returns: The media item data URL
    func loadMediaDataURL(
        mediaItemObjectID: NSManagedObjectID
    ) async throws -> String {
        guard let mediaItem = context.object(with: mediaItemObjectID) as? MediaItem else {
            throw MediaItemError.missingID
        }

        return try await mediaItem.loadDataURL()
    }

    /// Convert a media item to ResourceFile representation
    /// - Parameter mediaItemObjectID: The media item objectID
    /// - Returns: ResourceFile representation
    func toResourceFile(
        mediaItemObjectID: NSManagedObjectID
    ) async throws -> ExcalidrawFile.ResourceFile {
        guard let mediaItem = context.object(with: mediaItemObjectID) as? MediaItem else {
            throw MediaItemError.missingID
        }

        return try await mediaItem.toResourceFile()
    }

    // MARK: - Update MediaItem

    /// Update media item with resource file data
    /// This updates metadata and saves data URL to iCloud Drive
    /// - Parameters:
    ///   - mediaItemObjectID: The media item objectID
    ///   - resource: The resource file with updated data
    func updateMediaItem(
        mediaItemObjectID: NSManagedObjectID,
        resource: ExcalidrawFile.ResourceFile
    ) async throws {
        // Verify ID matches
        let idMatches = await context.perform {
            guard let mediaItem = self.context.object(with: mediaItemObjectID) as? MediaItem else {
                return false
            }
            return mediaItem.id == resource.id
        }

        guard idMatches else {
            self.logger.warning("MediaItem ID mismatch, skipping update")
            return
        }

        // Update metadata in CoreData
        try await context.perform {
            guard let mediaItem = self.context.object(with: mediaItemObjectID) as? MediaItem else {
                return
            }

            mediaItem.createdAt = resource.createdAt
            mediaItem.mimeType = resource.mimeType
            mediaItem.lastRetrievedAt = resource.lastRetrievedAt

            try self.context.save()
        }

        // Save data URL to storage
        try await saveMediaItemToStorage(mediaItemObjectID: mediaItemObjectID, dataURL: resource.dataURL)
    }

    /// Update media item data URL and save to iCloud Drive
    /// - Parameters:
    ///   - mediaItemObjectID: The media item objectID
    ///   - dataURL: The new data URL
    func updateMediaDataURL(
        mediaItemObjectID: NSManagedObjectID,
        dataURL: String
    ) async throws {
        // Save to storage
        try await saveMediaItemToStorage(mediaItemObjectID: mediaItemObjectID, dataURL: dataURL)
    }

    // MARK: - Private Helper Methods

    /// Save media item data URL to storage (local + auto iCloud sync)
    /// - Parameters:
    ///   - mediaItemObjectID: The media item objectID
    ///   - dataURL: The data URL to save
    private func saveMediaItemToStorage(
        mediaItemObjectID: NSManagedObjectID,
        dataURL: String
    ) async throws {
        // Get media item ID and metadata from CoreData
        let mediaItemID = try await context.perform {
            guard let mediaItem = self.context.object(with: mediaItemObjectID) as? MediaItem,
                  let mediaItemID = mediaItem.id else {
                throw MediaItemError.missingID
            }
            return mediaItemID
        }

        // MediaItem doesn't have updatedAt, use current time
        let updatedAt = Date()

        // Save to storage (local + iCloud sync)
        let relativePath = try await FileStorageManager.shared.saveMediaItem(
            dataURL: dataURL,
            mediaID: mediaItemID,
            updatedAt: updatedAt
        )

        // Update after successful save
        try await context.perform {
            guard let mediaItem = self.context.object(with: mediaItemObjectID) as? MediaItem else { return }
            mediaItem.updateAfterSavingToStorage(filePath: relativePath)
            try self.context.save()
        }
        logger.info("Saved media item to storage: \(relativePath)")
    }

    // MARK: - Delete MediaItem

    /// Delete a media item
    /// - Parameter mediaItemObjectID: The media item objectID to delete
    func deleteMediaItem(
        mediaItemObjectID: NSManagedObjectID
    ) async throws {
        // Extract media item info before deletion
        let (filePath, mediaID): (String?, String?) = try await context.perform {
            guard let mediaItem = self.context.object(with: mediaItemObjectID) as? MediaItem else {
                return (nil, nil)
            }
            let path = mediaItem.filePath
            let id = mediaItem.id

            // Delete database record first
            self.context.delete(mediaItem)
            try self.context.save()

            return (path, id)
        }

        // Delete physical file from storage (local + iCloud)
        if let relativePath = filePath, let mediaIDString = mediaID {
            do {
                try await FileStorageManager.shared.deleteContent(relativePath: relativePath, fileID: mediaIDString)
            } catch {
                // Log but don't throw - database record is already deleted
                print("Warning: Failed to delete media item file from storage: \(error)")
            }
        }
    }

    // MARK: - Query MediaItems

    /// Get all media items for a file
    /// - Parameter fileObjectID: The file objectID
    /// - Returns: Array of media item objectIDs
    func getMediaItems(
        forFile fileObjectID: NSManagedObjectID
    ) async throws -> [NSManagedObjectID] {
        try await context.perform {
            guard let file = self.context.object(with: fileObjectID) as? File else {
                return []
            }

            let fetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
            fetchRequest.predicate = NSPredicate(format: "file == %@", file)

            let mediaItems = try self.context.fetch(fetchRequest)
            return mediaItems.map { $0.objectID }
        }
    }

    /// Get all media items as ResourceFiles for a file
    /// - Parameter fileObjectID: The file objectID
    /// - Returns: Array of ResourceFiles
    func getResourceFiles(
        forFile fileObjectID: NSManagedObjectID
    ) async throws -> [ExcalidrawFile.ResourceFile] {
        let mediaItemObjectIDs = try await getMediaItems(forFile: fileObjectID)

        var resourceFiles: [ExcalidrawFile.ResourceFile] = []
        for mediaItemObjectID in mediaItemObjectIDs {
            if let resourceFile = try? await toResourceFile(mediaItemObjectID: mediaItemObjectID) {
                resourceFiles.append(resourceFile)
            }
        }

        return resourceFiles
    }
}
