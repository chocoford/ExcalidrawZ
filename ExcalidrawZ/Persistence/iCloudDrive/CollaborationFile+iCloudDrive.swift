//
//  CollaborationFile+iCloudDrive.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/23.
//

import Foundation
import CoreData
import Logging

extension CollaborationFile {
    private static let logger = Logger(label: "CollaborationFile+FileStorage")

    /// Load file content from storage (local/iCloud) or CoreData fallback
    /// Automatically checks iCloud for newer versions before returning
    func loadContent() async throws -> Data {
        guard let context = self.managedObjectContext else {
            struct NoContextError: LocalizedError {
                var errorDescription: String? { "CollaborationFile object has no managed object context" }
            }
            throw NoContextError()
        }

        // Use objectID to safely access object across async boundary
        let objectID = self.objectID

        // Read all Core Data properties in context.perform for thread safety
        let (filePath, fileID, content, name): (String?, UUID?, Data?, String?) = await context.perform {
            guard let collaborationFile = context.object(with: objectID) as? CollaborationFile else {
                return (nil, nil, nil, nil)
            }
            return (collaborationFile.filePath, collaborationFile.id, collaborationFile.content, collaborationFile.name)
        }

        // Try to load from storage first (local/iCloud with bidirectional sync)
        if let filePath = filePath, let fileID = fileID {
            do {
                return try await FileStorageManager.shared.loadContent(relativePath: filePath, fileID: fileID.uuidString)
            } catch {
                Self.logger.warning("\(error.localizedDescription), falling back to CoreData")
            }
        }

        // Fallback to CoreData content
        if let content = content {
            return content
        }

        throw AppError.fileError(.contentNotAvailable(filename: name ?? String(localizable: .generalUnknown)))
    }

    /// Update file path and clear content (call this after successfully saving to storage)
    /// Must be called on the entity's managedObjectContext
    func updateAfterSavingToStorage(filePath: String) {
        self.filePath = filePath
        self.content = nil // Clear CoreData content to save space
    }
}
