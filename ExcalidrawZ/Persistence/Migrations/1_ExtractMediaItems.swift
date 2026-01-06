//
//  1_ExtractMediaItems.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 11/21/25.
//

import CoreData
import Foundation
import Logging

struct Migration_ExtractMediaItems: MigrationVersion {
    static var name: String = String(localizable: .migrationExtractMediaItemsName)
    static var description: String = String(localizable: .migrationExtractMediaItemsDescription)

    let logger = Logger(label: "Migration_ExtractMediaItems")
    var context: NSManagedObjectContext
    init(context: NSManagedObjectContext) {
        self.context = context
    }

    private let filesFetch: NSFetchRequest<File> = NSFetchRequest(entityName: "File")
    private let checkpointsFetch: NSFetchRequest<FileCheckpoint> = NSFetchRequest(
        entityName: "FileCheckpoint")

    func checkIfShouldMigrate() async throws -> Bool {
        try await context.perform {
            let files = try filesFetch.execute()
            let checkpoints = try checkpointsFetch.execute()

            let needMigrate: Bool = {
                let excalidrawFiles =
                    files.compactMap {
                        try? ExcalidrawFile(__migrationLegacy_from: $0)
                    }
                    + checkpoints.compactMap {
                        try? ExcalidrawFile(__migrationLegacy_from: $0)
                    }
                return excalidrawFiles.contains(where: { !$0.files.isEmpty })
            }()

            return needMigrate
        }

    }

    /// Extract media items from inner JSON and convert them into MediaItem entities
    func migrate(
        autoResolveErrors: Bool,
        progressHandler: @escaping (_ description: String, _ progress: Double) async -> Void
    ) async throws -> [MigrationFailedItem] {
        let start = Date()
        #if os(macOS)
            try await backupFiles(context: context)
        #endif

        let failedItems = try await context.perform {
            let files = try filesFetch.execute()
            let checkpoints = try checkpointsFetch.execute()

            var insertedMediaID = Set<String>()
            var failedItems: [MigrationFailedItem] = []

            // Migrate files (0 - 1/2)
            logger.info("Need migrate \(files.count) files")
            for (i, file) in files.enumerated() {
                Task {
                    await progressHandler(
                        "Extracting media from file '\(file.name ?? String(localizable: .generalUntitled))'",
                        Double(i) / Double(files.count) / 2
                    )
                }
                do {
                    let excalidrawFile = try ExcalidrawFile(__migrationLegacy_from: file)
                    if excalidrawFile.files.isEmpty { continue }
                    logger.info(
                        "migrating \(excalidrawFile.files.count) files of \(excalidrawFile.name ?? "Untitled")"
                    )
                    for (id, media) in excalidrawFile.files {
                        if insertedMediaID.contains(id) { continue }

                        let mediaItem = MediaItem(resource: media, context: context)
                        mediaItem.file = file
                        // For migration, save dataURL to CoreData as fallback
                        // Will be migrated to iCloud Drive later via iCloudDriveMigrationViewModel
                        mediaItem.dataURL = media.dataURL
                        context.insert(mediaItem)
                        insertedMediaID.insert(id)
                    }
                    file.content = try excalidrawFile.contentWithoutFiles()
                } catch {
                    let fileName = file.name ?? "Untitled"
                    let errorMsg = "File migration failed: \(fileName)"
                    logger.error("\(errorMsg): \(error.localizedDescription)")
                    failedItems.append(
                        MigrationFailedItem(
                            id: file.id?.uuidString ?? UUID().uuidString,
                            name: fileName,
                            error: error.localizedDescription
                        )
                    )
                    continue
                }
            }

            // Migrate checkpoints (1/2 - 1)
            logger.info("Need migrate \(checkpoints.count) checkpoints")
            for (i, checkpoint) in checkpoints.enumerated() {
                Task {
                    await progressHandler(
                        "Extracting media from checkpoint '\(checkpoint.file?.name ?? String(localizable: .generalUntitled))'",
                        0.5 + Double(i) / Double(checkpoints.count) / 2
                    )
                }
                do {
                    guard let data = checkpoint.content else {
                        struct NoContentError: LocalizedError {
                            var errorDescription: String? { "Checkpoint has no content data." }
                        }
                        throw NoContentError()
                    }
                    let excalidrawFile = try ExcalidrawFile(data: data)
                    if excalidrawFile.files.isEmpty { continue }
                    logger.info(
                        "migrating \(excalidrawFile.files.count) files of checkpoint<\(checkpoint.file?.name ?? "Untitled")>"
                    )
                    for (id, media) in excalidrawFile.files {
                        if insertedMediaID.contains(id) { continue }
                        let mediaItem = MediaItem(resource: media, context: context)
                        mediaItem.file = checkpoint.file
                        // For migration, save dataURL to CoreData as fallback
                        // Will be migrated to iCloud Drive later via iCloudDriveMigrationViewModel
                        mediaItem.dataURL = media.dataURL
                        context.insert(mediaItem)
                    }
                    checkpoint.content = try excalidrawFile.contentWithoutFiles()
                } catch {
                    let fileName = checkpoint.file?.name ?? "Untitled"
                    let errorMsg = "Checkpoint migration failed: \(fileName)"
                    logger.error("\(errorMsg): \(error.localizedDescription)")
                    failedItems.append(
                        MigrationFailedItem(
                            id: checkpoint.id?.uuidString ?? UUID().uuidString,
                            name: "Checkpoint: \(fileName)",
                            error: error.localizedDescription
                        )
                    )
                    continue
                }
            }

            let timeCost = -start.timeIntervalSinceNow
            if failedItems.isEmpty {
                logger.info("🎉 Extract media items completed successfully. Time cost: \(timeCost) s")
            } else {
                logger.warning("⚠️ Extract media items completed with \(failedItems.count) failures. Time cost: \(timeCost) s")
            }

            return failedItems
        }

        return failedItems
    }
}

// ----------------------------------------
// MARK: - Legacy Migration Utilities
// ----------------------------------------

extension ExcalidrawFile {
    /// Deprecated init used only for migration
    fileprivate init(__migrationLegacy_from persistenceFile: ExcalidrawFileRepresentable) throws {
        guard let data = persistenceFile.content else {
            struct EmptyContentError: Error {}
            throw EmptyContentError()
        }

        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = persistenceFile.id?.uuidString ?? UUID().uuidString
        self.content = persistenceFile.content
        self.name = persistenceFile.name

        if let p = persistenceFile as? CollaborationFile {
            self.roomID = p.roomID
        }
    }

    fileprivate init(__migrationLegacy_from checkpoint: FileCheckpoint) throws {
        guard let data = checkpoint.content else {
            struct EmptyContentError: Error {}
            throw EmptyContentError()
        }
        let file = try JSONDecoder().decode(ExcalidrawFile.self, from: data)
        self = file
        self.id = checkpoint.file?.id?.uuidString ?? UUID().uuidString
        self.content = checkpoint.content
        self.name = checkpoint.file?.name
    }
}
