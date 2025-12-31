//
//  File+iCloudDrive.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import Foundation
import CoreData
import Logging

extension File {
    private static let logger = Logger(label: "File+FileStorage")

    /// Load file content from storage (local/iCloud)
    /// Automatically checks iCloud for newer versions before returning
    /// Falls back to CoreData content if storage is unavailable
    func loadContent() async throws -> Data {
        // Try to load from storage first (local/iCloud with bidirectional sync)
        if let filePath = self.filePath, let fileID = self.id {
            do {
                return try await FileStorageManager.shared.loadContent(relativePath: filePath, fileID: fileID.uuidString)
            } catch {
                Self.logger.warning("\(error.localizedDescription), falling back to CoreData.")
            }
        }

        // Fallback to CoreData content
        if let content = self.content {
            return content
        }

        throw AppError.fileError(.contentNotAvailable(filename: self.name ?? String(localizable: .generalUnknown)))
    }

    /// Update file path and clear content (call this after successfully saving to storage)
    /// Must be called on the entity's managedObjectContext
    func updateAfterSavingToStorage(filePath: String) {
        self.filePath = filePath
        self.content = nil // Clear CoreData content to save space
        self.updatedAt = .now
    }

    /// Update content when iCloud is unavailable (fallback)
    /// Must be called on the entity's managedObjectContext
    func updateContentFallback(data: Data) {
        self.content = data
        self.updatedAt = .now
    }

    /// Clear all content references
    /// Must be called on the entity's managedObjectContext
    func clearContentReferences() {
        self.content = nil
        self.filePath = nil
    }
}
