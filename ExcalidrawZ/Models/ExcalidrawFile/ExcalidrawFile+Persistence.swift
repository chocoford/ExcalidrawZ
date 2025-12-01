//
//  ExcalidrawFile+Persistence.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2024/10/8.
//

import Foundation
import CoreData

protocol ExcalidrawFileRepresentable: NSManagedObject {
    var id: UUID? { get }
    var content: Data? { get }
    var name: String? { get }
}

extension File: ExcalidrawFileRepresentable {}
extension CollaborationFile: ExcalidrawFileRepresentable {}

extension ExcalidrawFile {
    /// Initialize from persistence file - synchronous version (deprecated)
    /// This method directly accesses content property and may not get latest data from iCloud Drive
    @available(*, deprecated, message: "Use async init(from:) instead for iCloud Drive support")
    init(from persistenceFile: ExcalidrawFileRepresentable) throws {
        guard let data = persistenceFile.content else {
            struct EmptyContentError: Error {}
            throw EmptyContentError()
        }
        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = persistenceFile.id ?? UUID()
        self.content = persistenceFile.content
        self.name = persistenceFile.name
        if let persistenceFile = persistenceFile as? CollaborationFile {
            self.roomID = persistenceFile.roomID
        }
    }

    /// Initialize from persistence file - async version with iCloud Drive support
    init(from persistenceFile: ExcalidrawFileRepresentable) async throws {
        let data: Data
        if let file = persistenceFile as? File {
            data = try await file.loadContent()
        } else {
            // CollaborationFile doesn't have iCloud Drive support yet
            guard let content = persistenceFile.content else {
                struct EmptyContentError: Error {}
                throw EmptyContentError()
            }
            data = content
        }

        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = persistenceFile.id ?? UUID()
        self.content = data
        self.name = persistenceFile.name
        if let persistenceFile = persistenceFile as? CollaborationFile {
            self.roomID = persistenceFile.roomID
        }
    }
    
    /// Initialize from persistence file ID - synchronous version (deprecated)
    @available(*, deprecated, message: "Use async init(from:context:) instead for iCloud Drive support")
    init(
        from persistenceFileID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) throws {
        guard let persistenceFile = context.object(with: persistenceFileID) as? ExcalidrawFileRepresentable else {
            struct FileNotFoundError: Error {}
            throw FileNotFoundError()
        }
        try self.init(from: persistenceFile)
    }

    /// Initialize from persistence file ID - async version with iCloud Drive support
    init(
        from persistenceFileID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) async throws {
        guard let persistenceFile = context.object(with: persistenceFileID) as? ExcalidrawFileRepresentable else {
            struct FileNotFoundError: Error {}
            throw FileNotFoundError()
        }
        try await self.init(from: persistenceFile)
    }
    
    /// Initialize from checkpoint - synchronous version (deprecated)
    @available(*, deprecated, message: "Use async init(from:) instead for iCloud Drive support")
    init(from checkpoint: FileCheckpoint) throws {
        guard let data = checkpoint.content else {
            struct EmptyContentError: Error {}
            throw EmptyContentError()
        }
        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = checkpoint.file?.id ?? UUID()
        self.content = checkpoint.content
        self.name = checkpoint.file?.name
    }

    /// Initialize from checkpoint - async version with iCloud Drive support
    init(from checkpoint: FileCheckpoint) async throws {
        let data = try await checkpoint.loadContent()
        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = checkpoint.file?.id ?? UUID()
        self.content = data
        self.name = checkpoint.file?.name
    }
    
    mutating func syncFiles(context: NSManagedObjectContext) async throws {
        let mediasFetchRequest = NSFetchRequest<MediaItem>(entityName: "MediaItem")
        mediasFetchRequest.predicate = NSPredicate(format: "file.id == %@", self.id as CVarArg)
        let medias: [MediaItem] = try context.fetch(mediasFetchRequest)

        // Load all ResourceFiles concurrently
        let resourceFiles = try await withThrowingTaskGroup(of: ExcalidrawFile.ResourceFile?.self) { group in
            for media in medias {
                group.addTask {
                    try? await ExcalidrawFile.ResourceFile(mediaItem: media)
                }
            }

            var files: [ExcalidrawFile.ResourceFile] = []
            for try await resourceFile in group {
                if let resourceFile {
                    files.append(resourceFile)
                }
            }
            return files
        }

        let files = resourceFiles
            .map{ [$0.id : $0] }
            .merged()
            .merging(self.files, uniquingKeysWith: {$1})
        self.files = files

        try self.updateContentFilesFromFiles()
    }
    
}

extension ExcalidrawFile.ResourceFile {
    /// Initialize from MediaItem - synchronous version (deprecated)
    @available(*, deprecated, message: "Use async init(mediaItem:) instead for iCloud Drive support")
    init?(mediaItem: MediaItem) {
        guard let id = mediaItem.id, let dataURL = mediaItem.dataURL else {
            return nil
        }
        self.id = id
        self.dataURL = dataURL
        self.createdAt = mediaItem.createdAt ?? Date.distantPast
        self.lastRetrievedAt = mediaItem.lastRetrievedAt ?? Date.distantPast
        self.mimeType = mediaItem.mimeType ?? "image/png"
    }

    /// Initialize from MediaItem - async version with iCloud Drive support
    init(mediaItem: MediaItem) async throws {
        guard let id = mediaItem.id else {
            struct MissingIDError: Error {}
            throw MissingIDError()
        }

        let dataURL = try await mediaItem.loadDataURL()

        self.id = id
        self.dataURL = dataURL
        self.createdAt = mediaItem.createdAt ?? Date.distantPast
        self.lastRetrievedAt = mediaItem.lastRetrievedAt ?? Date.distantPast
        self.mimeType = mediaItem.mimeType ?? "image/png"
    }
}
