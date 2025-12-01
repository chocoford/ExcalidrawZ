//
//  MediaItem+iCloudDrive.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import Foundation
import CoreData
import Logging

extension MediaItem {
    private static let logger = Logger(label: "MediaItem+FileStorage")

    /// Load media data URL from storage (local/iCloud)
    /// Automatically checks iCloud for newer versions before returning
    /// Falls back to CoreData dataURL if storage is unavailable
    func loadDataURL() async throws -> String {
        // Try to load from storage first (local/iCloud with bidirectional sync)
        if let filePath = self.filePath, let mediaID = self.id {
            do {
                // This will automatically check iCloud for updates and download if needed
                let _ = try await FileStorageManager.shared.loadContent(relativePath: filePath, fileID: mediaID)
                // Now load and convert to data URL
                return try await FileStorageManager.shared.loadMediaItem(relativePath: filePath)
            } catch {
                Self.logger.warning("Failed to load media from storage, falling back to CoreData: \(error.localizedDescription)")
            }
        }

        // Fallback to CoreData dataURL
        if let dataURL = self.dataURL {
            return dataURL
        }

        throw MediaItemError.dataURLNotAvailable
    }

    /// Update file path and clear dataURL (call this after successfully saving to storage)
    /// Must be called on the entity's managedObjectContext
    func updateAfterSavingToStorage(filePath: String) {
        self.filePath = filePath
        self.dataURL = nil // Clear CoreData dataURL to save space
        self.lastRetrievedAt = .now
    }

    /// Clear all data references
    /// Must be called on the entity's managedObjectContext
    func clearDataReferences() {
        self.dataURL = nil
        self.filePath = nil
    }

    /// Get ResourceFile representation, loading data from iCloud Drive if needed
    func toResourceFile() async throws -> ExcalidrawFile.ResourceFile {
        let dataURL = try await loadDataURL()

        return ExcalidrawFile.ResourceFile(
            mimeType: self.mimeType ?? "application/octet-stream",
            id: self.id ?? "",
            createdAt: self.createdAt,
            dataURL: dataURL,
            lastRetrievedAt: self.lastRetrievedAt
        )
    }
}

enum MediaItemError: LocalizedError {
    case dataURLNotAvailable
    case missingID

    var errorDescription: String? {
        switch self {
        case .dataURLNotAvailable:
            return "Media item data URL is not available"
        case .missingID:
            return "Media item ID is missing"
        }
    }
}
