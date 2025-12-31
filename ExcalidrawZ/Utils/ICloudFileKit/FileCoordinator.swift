//
//  FileCoordinator.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/30/25.
//

import Foundation
import Logging

/// Safe file access coordinator for local and iCloud Drive files
///
/// This actor provides safe file operations using NSFileCoordinator
/// and handles automatic downloading for iCloud files.
///
/// **Design Philosophy**:
/// - Unified handling of local and iCloud files based on NSFileCoordinator
/// - iCloud-specific methods (downloadFile, evictLocalCopy) auto-check file type
/// - Progress tracking via optional callbacks
/// - Operation deduplication to prevent redundant downloads
///
/// Usage:
/// ```swift
/// // Read file (auto-downloads if iCloud file)
/// let data = try await FileCoordinator.shared.coordinatedRead(
///     url: fileURL,
///     trackProgress: true,
///     progressHandler: { progress in
///         print("Progress: \(progress)")
///     }
/// ) { url in
///     try Data(contentsOf: url)
/// }
///
/// // Write file
/// try await FileCoordinator.shared.coordinatedWrite(url: fileURL, data: data)
///
/// // Download iCloud file explicitly
/// try await FileCoordinator.shared.downloadFile(url: fileURL) { progress in
///     print("Download: \(progress)")
/// }
/// ```
public actor FileCoordinator {
    // MARK: - Singleton

    public static let shared = FileCoordinator()

    // MARK: - Properties

    private let logger = Logger(label: "FileCoordinator")
    private let statusChecker = ICloudStatusChecker.shared

    /// Cache of ongoing file operations (for deduplication)
    private var ongoingOperations: [URL: Task<Data, Error>] = [:]

    // MARK: - Initialization

    private init() {
        logger.info("FileCoordinator initialized")
    }

    // MARK: - Public API - Universal File Operations

    /// Read a file safely with coordinated access
    ///
    /// For iCloud files, this automatically triggers download if needed.
    /// Progress tracking is optional via the progressHandler callback.
    ///
    /// - Parameters:
    ///   - url: The file URL to read
    ///   - trackProgress: Whether to track download progress
    ///   - progressHandler: Optional callback for progress updates (0.0 to 1.0)
    ///   - accessor: Closure that reads the file and returns result
    /// - Returns: Result from accessor closure
    /// - Throws: Error if unable to read file
    public func coordinatedRead<T>(
        url: URL,
        trackProgress: Bool = false,
        progressHandler: (@Sendable (Double) -> Void)? = nil,
        accessor: @Sendable @escaping (URL) throws -> T
    ) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var coordinationError: NSError?
                let coordinator = NSFileCoordinator()

                coordinator.coordinate(
                    readingItemAt: url,
                    options: [],
                    error: &coordinationError
                ) { coordinatedURL in
                    var observation: NSKeyValueObservation?

                    // Track progress if requested
                    if trackProgress, let progress = Progress.current(), let handler = progressHandler {
                        self.logger.info("Tracking download progress for \(url.lastPathComponent)")

                        // Initial progress report
                        Task { @MainActor in
                            handler(progress.fractionCompleted)
                        }

                        // Observe progress changes
                        observation = progress.observe(
                            \.fractionCompleted,
                            options: [.new]
                        ) { prog, _ in
                            Task { @MainActor in
                                handler(prog.fractionCompleted)
                            }
                        }
                    }

                    do {
                        let result = try accessor(coordinatedURL)
                        observation?.invalidate()
                        continuation.resume(returning: result)
                    } catch {
                        observation?.invalidate()
                        self.logger.error("Failed to read file \(url.lastPathComponent): \(error)")
                        continuation.resume(throwing: error)
                    }
                }

                if let error = coordinationError {
                    self.logger.error("File coordination error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Convenience method to read file data with coordinated access
    ///
    /// This is a convenience wrapper that returns Data directly.
    /// For iCloud files, this automatically triggers download if needed.
    ///
    /// - Parameters:
    ///   - url: The file URL to read
    ///   - trackProgress: Whether to track download progress
    ///   - progressHandler: Optional callback for progress updates (0.0 to 1.0)
    /// - Returns: File data
    /// - Throws: Error if unable to read file
    public func coordinatedRead(
        url: URL,
        trackProgress: Bool = false,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        return try await coordinatedRead(
            url: url,
            trackProgress: trackProgress,
            progressHandler: progressHandler
        ) { url in
            try Data(contentsOf: url)
        }
    }

    /// Write data to a file safely with coordinated access
    ///
    /// Works for both local and iCloud files.
    ///
    /// - Parameters:
    ///   - url: The file URL to write to
    ///   - data: The data to write
    /// - Throws: Error if unable to write file
    public func coordinatedWrite(url: URL, data: Data) async throws {
        logger.info("Writing file: \(url.lastPathComponent) (\(data.count) bytes)")

        return try await withCheckedThrowingContinuation { continuation in
            var coordinationError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL, options: .atomic)
                    logger.info("Successfully wrote file: \(url.lastPathComponent)")
                    continuation.resume()
                } catch {
                    logger.error("Failed to write file: \(url.lastPathComponent) - \(error)")
                    continuation.resume(throwing: FileCoordinatorError.writeFailed(error))
                }
            }

            if let coordinationError = coordinationError {
                logger.error("File coordination error: \(coordinationError)")
                continuation.resume(throwing: FileCoordinatorError.coordinationFailed(coordinationError))
            }
        }
    }

    /// Delete a file safely with coordinated access
    ///
    /// Works for both local and iCloud files.
    ///
    /// - Parameter url: The file URL to delete
    /// - Throws: Error if unable to delete file
    public func deleteFile(url: URL) async throws {
        logger.info("Deleting file: \(url.lastPathComponent)")

        return try await withCheckedThrowingContinuation { continuation in
            var coordinationError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(
                writingItemAt: url,
                options: .forDeleting,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try FileManager.default.removeItem(at: coordinatedURL)
                    logger.info("Successfully deleted file: \(url.lastPathComponent)")
                    continuation.resume()
                } catch {
                    logger.error("Failed to delete file: \(url.lastPathComponent) - \(error)")
                    continuation.resume(throwing: FileCoordinatorError.deleteFailed(error))
                }
            }

            if let coordinationError = coordinationError {
                logger.error("File coordination error: \(coordinationError)")
                continuation.resume(throwing: FileCoordinatorError.coordinationFailed(coordinationError))
            }
        }
    }

    // MARK: - Public API - iCloud-Specific Operations

    /// Download an iCloud file explicitly with progress tracking
    ///
    /// **Auto-check**: If the file is local (not in iCloud), this returns immediately without error.
    ///
    /// This method shares deduplication cache with coordinatedRead - if another
    /// operation is already downloading/reading this file, it waits for completion.
    ///
    /// - Parameters:
    ///   - url: The file URL to download
    ///   - progressHandler: Optional callback for progress updates (0.0 to 1.0)
    /// - Throws: Error if unable to download
    public func downloadFile(
        url: URL,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        // Check if file is in iCloud first
        let status = try await statusChecker.checkStatus(for: url)
        guard status.isICloudFile else {
            logger.info("File is not in iCloud, skipping download: \(url.lastPathComponent)")
            return
        }

        // If operation is already in progress, wait for existing task
        if let existingTask = ongoingOperations[url] {
            logger.info("File operation already in progress, waiting: \(url.lastPathComponent)")
            _ = try await existingTask.value  // Ignore returned data
            return
        }

        logger.info("Starting download: \(url.lastPathComponent)")

        // Create new read task with progress tracking
        let readTask = Task<Data, Error> {
            defer {
                self.removeOperation(for: url)
            }

            let data = try await self.coordinatedRead(
                url: url,
                trackProgress: true,
                progressHandler: progressHandler
            ) { url in
                try Data(contentsOf: url)
            }

            self.logger.info("Download completed: \(url.lastPathComponent)")
            return data
        }

        // Cache the task
        ongoingOperations[url] = readTask

        // Wait for completion, ignore returned data
        _ = try await readTask.value
    }

    /// Remove local copy of an iCloud file (keeps cloud version)
    ///
    /// **Auto-check**: If the file is local (not in iCloud), this returns immediately without error.
    ///
    /// - Parameter url: The iCloud file URL
    /// - Throws: Error if unable to evict
    public func evictLocalCopy(of url: URL) async throws {
        // Check if file is in iCloud
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values.isUbiquitousItem == true else {
            logger.info("File is not in iCloud, skipping eviction: \(url.lastPathComponent)")
            return
        }

        logger.info("Evicting local copy: \(url.lastPathComponent)")
        try FileManager.default.evictUbiquitousItem(at: url)
    }

    // MARK: - Private Helpers

    /// Remove operation task from cache
    private func removeOperation(for url: URL) {
        ongoingOperations.removeValue(forKey: url)
    }
}

// MARK: - Errors

public enum FileCoordinatorError: LocalizedError {
    case writeFailed(Error)
    case deleteFailed(Error)
    case coordinationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .writeFailed(let error):
            return "Failed to write file: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete file: \(error.localizedDescription)"
        case .coordinationFailed(let error):
            return "File coordination failed: \(error.localizedDescription)"
        }
    }
}
