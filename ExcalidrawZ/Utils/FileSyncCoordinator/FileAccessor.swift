//
//  FileAccessor.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/23/25.
//

import Foundation
import Logging

/// Safe file access coordinator for iCloud and local files
///
/// This actor provides safe file operations using NSFileCoordinator
/// and handles automatic downloading for iCloud files.
///
/// Usage:
/// ```swift
/// let accessor = FileAccessor.shared
///
/// // Open file (auto-downloads if needed)
/// let data = try await accessor.openFile(fileURL)
///
/// // Save file
/// try await accessor.saveFile(at: fileURL, data: data)
///
/// // Explicitly download
/// try await accessor.downloadFile(fileURL)
/// ```
actor FileAccessor {
    // MARK: - Singleton

    static let shared = FileAccessor()

    // MARK: - Properties

    private let logger = Logger(label: "FileAccessor")
    private let statusResolver = ICloudStatusResolver()

    /// Cache of ongoing file operations (for deduplication)
    /// Used by both openFile and downloadFile to prevent duplicate operations
    private var ongoingOperations: [URL: Task<Data, Error>] = [:]

    // MARK: - Initialization

    private init() {
        logger.info("FileAccessor initialized")
    }

    // MARK: - Public API

    /// Open a file safely, downloading if necessary with progress tracking
    ///
    /// This method ensures operation deduplication: if the same file is being
    /// opened/downloaded by another caller, this will wait for that operation
    /// to complete instead of starting a new one.
    ///
    /// - Parameter url: The file URL to open
    /// - Returns: File data
    /// - Throws: FileAccessError if unable to open file
    func openFile(_ url: URL) async throws -> Data {
        // If operation is already in progress, wait for existing task
        if let existingTask = ongoingOperations[url] {
            logger.info("File operation already in progress, waiting: \(url.lastPathComponent)")
            return try await existingTask.value
        }

        logger.info("Opening file: \(url.lastPathComponent)")

        // Check file status to determine if download/wait is needed
        let status = try await statusResolver.checkStatus(for: url)

        // Track progress for files that need downloading or are downloading
        let trackProgress = switch status {
            case .notDownloaded, .outdated, .downloading:
                true
            default:
                false
        }

        // Create new read task
        let readTask = Task<Data, Error> {
            defer {
                // Clean up cache after completion (success or failure)
                self.removeOperation(for: url)
            }

            return try await self.coordinatedRead(url: url, trackProgress: trackProgress)
        }

        // Cache the task
        ongoingOperations[url] = readTask

        // Wait for completion
        return try await readTask.value
    }

    /// Save data to a file safely
    /// - Parameters:
    ///   - url: The file URL to save to
    ///   - data: The data to write
    /// - Throws: FileAccessError if unable to save file
    func saveFile(at url: URL, data: Data) async throws {
        logger.info("Saving file: \(url.lastPathComponent) (\(data.count) bytes)")

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
                    logger.info("Successfully saved file: \(url.lastPathComponent)")
                    continuation.resume()
                } catch {
                    logger.error("Failed to save file: \(url.lastPathComponent) - \(error)")
                    continuation.resume(throwing: FileAccessError.writeFailed(error))
                }
            }

            if let coordinationError = coordinationError {
                logger.error("File coordination error: \(coordinationError)")
                continuation.resume(throwing: FileAccessError.coordinationFailed(coordinationError))
            }
        }
    }

    /// Download an iCloud file with progress tracking
    ///
    /// This method shares the same deduplication cache as openFile:
    /// - If another caller is opening/downloading the same file, waits for that operation
    /// - If this triggers a new download, subsequent openFile calls will wait for it
    ///
    /// - Parameter url: The file URL to download
    /// - Throws: FileAccessError if unable to download
    func downloadFile(_ url: URL) async throws {
        // Check if file is in iCloud first (before checking cache)
        let status = try await statusResolver.checkStatus(for: url)
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
                // Clean up cache after completion (success or failure)
                self.removeOperation(for: url)
            }

            let data = try await self.coordinatedRead(url: url, trackProgress: true)
            self.logger.info("Download completed: \(url.lastPathComponent)")
            return data
        }

        // Cache the task
        ongoingOperations[url] = readTask

        // Wait for completion, ignore returned data
        _ = try await readTask.value
    }

    /// Remove operation task from cache
    private func removeOperation(for url: URL) {
        ongoingOperations.removeValue(forKey: url)
    }

    
    /// 移除 iCloud 文件的本地下载（保留云端）
    func evictLocalCopy(of url: URL) async throws {
        // 1. 确保是 iCloud 文件
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
        guard values.isUbiquitousItem == true else {
            return // 本地文件，直接忽略
        }

        // 2. 请求 iCloud 移除本地副本
        try FileManager.default.evictUbiquitousItem(at: url)

        // 3. 更新状态（不要假设立即完成）
        await FileSyncCoordinator.shared.updateFileStatus(
            for: url,
            status: .notDownloaded
        )
    }
    
    /// Delete a file safely
    /// - Parameter url: The file URL to delete
    /// - Throws: FileAccessError if unable to delete
    func deleteFile(_ url: URL) async throws {
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
                    continuation.resume(throwing: FileAccessError.deleteFailed(error))
                }
            }

            if let coordinationError = coordinationError {
                logger.error("File coordination error: \(coordinationError)")
                continuation.resume(throwing: FileAccessError.coordinationFailed(coordinationError))
            }
        }
    }

    // MARK: - Private Helpers

    /// Coordinated read with optional progress tracking
    ///
    /// This method uses NSFileCoordinator to safely read a file.
    /// If the file is in iCloud and not downloaded, coordinate will automatically
    /// trigger the download. Progress.current() provides download progress tracking.
    ///
    /// - Parameters:
    ///   - url: The file URL to read
    ///   - trackProgress: Whether to track and report download progress
    /// - Returns: File data
    /// - Throws: FileAccessError if unable to read file
    func coordinatedRead(
        url: URL,
        trackProgress: Bool
    ) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {

                var coordinationError: NSError?
                let coordinator = NSFileCoordinator()
                coordinator.coordinate(
                    readingItemAt: url,
                    options: [],
                    error: &coordinationError
                ) { coordinatedURL in

                    // ✅ progressHolder 只存在于这个并发域
                    var observation: NSKeyValueObservation?
                    Task {
                        await FileSyncCoordinator.shared.updateFileStatus(
                            for: url,
                            status: .downloading(progress: nil)
                        )
                    }
                    if trackProgress, let progress = Progress.current() {
                        self.logger.info("Tracking download progress: \(progress)")
                        Task {
                            await FileSyncCoordinator.shared.updateFileStatus(
                                for: url,
                                status: .downloading(progress: progress.fractionCompleted)
                            )
                        }

                        observation = progress.observe(
                            \.fractionCompleted,
                            options: [.new]
                        ) { prog, _ in
                            Task {
                                await FileSyncCoordinator.shared.updateFileStatus(
                                    for: url,
                                    status: .downloading(progress: prog.fractionCompleted)
                                )
                            }
                        }
                    }

                    do {
                        let data = try Data(contentsOf: coordinatedURL)

                        // ✅ observation 生命周期在同一线程内
                        observation?.invalidate()

                        Task {
                            await FileSyncCoordinator.shared.updateFileStatus(
                                for: url,
                                status: .downloaded
                            )
                        }

                        continuation.resume(returning: data)
                    } catch {
                        observation?.invalidate()
                        continuation.resume(throwing: error)
                    }
                }

                if let error = coordinationError {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - File Access Errors

enum FileAccessError: LocalizedError {
    case readFailed(Error)
    case writeFailed(Error)
    case deleteFailed(Error)
    case downloadFailed(Error)
    case coordinationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .readFailed(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to write file: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete file: \(error.localizedDescription)"
        case .downloadFailed(let error):
            return "Failed to download file: \(error.localizedDescription)"
        case .coordinationFailed(let error):
            return "File coordination failed: \(error.localizedDescription)"
        }
    }
}


final class DownloadProgressHolder {
    var observation: NSKeyValueObservation?
}
