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
        // Try to load from storage first (local/iCloud with bidirectional sync)
        if let filePath = self.filePath, let checkpointID = self.id {
            do {
                return try await FileStorageManager.shared.loadContent(relativePath: filePath, fileID: checkpointID.uuidString)
            } catch {
                Self.logger.warning("Failed to load checkpoint from storage, falling back to CoreData: \(error.localizedDescription)")
            }
        }

        // Fallback to CoreData content
        if let content = self.content {
            return content
        }

        throw AppError.fileError(.contentNotAvailable(filename: self.file?.name ?? String(localizable: .generalUnknown)))
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
