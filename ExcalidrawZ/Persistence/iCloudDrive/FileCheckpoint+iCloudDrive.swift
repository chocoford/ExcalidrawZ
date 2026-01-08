//
//  FileCheckpoint+iCloudDrive.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import Foundation
import CoreData
import Logging

extension FileCheckpoint {
    private static let logger = Logger(label: "FileCheckpoint+FileStorage")

    /// Load checkpoint content from storage (local/iCloud)
    /// Automatically checks iCloud for newer versions before returning
    /// Falls back to CoreData content if storage is unavailable
    func loadContent() async throws -> Data {
        guard let context = self.managedObjectContext else {
            struct NoContextError: LocalizedError {
                var errorDescription: String? { "FileCheckpoint object has no managed object context" }
            }
            throw NoContextError()
        }

        // Use objectID to safely access object across async boundary
        let objectID = self.objectID

        // Read all Core Data properties in context.perform for thread safety
        let (filePath, checkpointID, content, fileName): (String?, UUID?, Data?, String?) = await context.perform {
            guard let checkpoint = context.object(with: objectID) as? FileCheckpoint else {
                return (nil, nil, nil, nil)
            }
            return (checkpoint.filePath, checkpoint.id, checkpoint.content, checkpoint.file?.name)
        }

        // Try to load from storage first (local/iCloud with bidirectional sync)
        if let filePath = filePath, let checkpointID = checkpointID {
            do {
                return try await FileStorageManager.shared.loadContent(relativePath: filePath, fileID: checkpointID.uuidString)
            } catch {
                Self.logger.warning("Failed to load checkpoint from storage, falling back to CoreData: \(error.localizedDescription)")
            }
        }

        // Fallback to CoreData content
        if let content = content {
            return content
        }

        throw AppError.fileError(.contentNotAvailable(filename: fileName ?? String(localizable: .generalUnknown)))
    }

    /// Update file path and clear content (call this after successfully saving to storage)
    /// Must be called on the entity's managedObjectContext
    func updateAfterSavingToStorage(filePath: String) {
        self.filePath = filePath
        self.content = nil // Clear CoreData content to save space
        self.updatedAt = .now
    }
}

enum FileCheckpointError: LocalizedError {
    case contentNotAvailable
    case missingID
    
    var errorDescription: String? {
        switch self {
            case .contentNotAvailable:
                return "File checkpoint content is not available"
            case .missingID:
                return "File checkpoint ID is missing"
        }
    }
}
