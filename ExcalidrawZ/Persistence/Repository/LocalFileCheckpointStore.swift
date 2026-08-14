//
//  LocalFileCheckpointStore.swift
//  ExcalidrawZ
//

import CoreData
import Foundation

/// Device-managed user history for Linked Folder and provider-backed files.
enum LocalFileCheckpointStore {
    private static let maximumUserCheckpointCount = 50

    static func recordUserEdit(
        content: Data,
        for fileURL: URL,
        newCheckpoint: Bool
    ) async throws {
        let context = PersistenceController.shared.container.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<LocalFileCheckpoint> = LocalFileCheckpoint.fetchRequest()
            request.predicate = NSPredicate(
                format: "url == %@ AND (source == nil OR source == %@)",
                fileURL as NSURL,
                FileCheckpointSource.user.rawValue
            )
            request.sortDescriptors = [
                NSSortDescriptor(key: "updatedAt", ascending: false)
            ]
            let checkpoints = try context.fetch(request)

            if !newCheckpoint, let latest = checkpoints.first {
                latest.content = content
                latest.updatedAt = .now
                if latest.source == nil {
                    latest.source = FileCheckpointSource.user.rawValue
                }
            } else {
                let checkpoint = LocalFileCheckpoint(context: context)
                checkpoint.id = UUID()
                checkpoint.url = fileURL
                checkpoint.updatedAt = .now
                checkpoint.content = content
                checkpoint.source = FileCheckpointSource.user.rawValue

                let excessCount = max(
                    0,
                    checkpoints.count + 1 - maximumUserCheckpointCount
                )
                for checkpoint in checkpoints.suffix(excessCount) {
                    context.delete(checkpoint)
                }
            }
            try context.save()
        }
    }
}
