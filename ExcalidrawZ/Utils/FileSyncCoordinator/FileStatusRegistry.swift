//
//  FileStatusRegistry.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/23/25.
//

import Foundation
import Logging

/// Main-actor isolated registry for managing FileStatusBox instances.
///
/// This class ensures that:
/// - Each file URL has exactly one FileStatusBox instance
/// - All operations run on the main thread (for UI safety)
/// - Memory is managed efficiently (boxes can be removed when files are deleted)
@MainActor
final class FileStatusRegistry {
    private let logger = Logger(label: "FileStatusRegistry")

    /// Internal storage: URL -> FileStatusBox
    private var boxes: [URL: FileStatusBox] = [:]

    /// Get or create a FileStatusBox for the given URL
    /// - Parameter url: The file URL
    /// - Returns: The FileStatusBox for this file
    func box(for url: URL) -> FileStatusBox {
        if let existing = boxes[url] {
            return existing
        }

        let newBox = FileStatusBox(url: url)
        boxes[url] = newBox
        logger.info("Created new FileStatusBox for: \(url.lastPathComponent)")
        return newBox
    }

    /// Update the status for a file
    /// - Parameters:
    ///   - url: The file URL
    ///   - status: The new status
    func updateStatus(for url: URL, status: FileStatus) {
        let statusBox = box(for: url)
        statusBox.updateStatus(status)
        logger.info("Updated status for \(url.lastPathComponent): \(String(describing: status))")
    }

    /// Remove a FileStatusBox (e.g., when file is deleted)
    /// - Parameter url: The file URL to remove
    func removeBox(for url: URL) {
        boxes.removeValue(forKey: url)
        logger.info("Removed FileStatusBox for: \(url.lastPathComponent)")
    }

    /// Remove all boxes for files within a folder
    /// - Parameter folderURL: The folder URL
    func removeBoxes(inFolder folderURL: URL) {
        let folderPath = folderURL.path
        let keysToRemove = boxes.keys.filter { $0.path.hasPrefix(folderPath) }

        for key in keysToRemove {
            boxes.removeValue(forKey: key)
        }

        logger.info("Removed \(keysToRemove.count) FileStatusBox(es) in folder: \(folderURL.lastPathComponent)")
    }

    /// Get all tracked file URLs
    var trackedURLs: [URL] {
        Array(boxes.keys)
    }

    /// Get the count of tracked files
    var count: Int {
        boxes.count
    }

    /// Clear all boxes (e.g., for cleanup)
    func clear() {
        let count = boxes.count
        boxes.removeAll()
        logger.info("Cleared \(count) FileStatusBox(es)")
    }
}
