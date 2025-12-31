//
//  SyncCoordinator.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/26.
//

import Foundation
import Logging
import Combine
import CoreData

/// Coordinator for bidirectional file synchronization
actor SyncCoordinator {
    private let logger = Logger(label: "SyncCoordinator")

    // Dependencies
    private let localManager: LocalStorageManager
    private let iCloudManager: iCloudDriveFileManager

    // Components
    private let syncQueue: SyncQueue
    private let fileEnumerator: FileEnumerator
    private let orphanCleaner: OrphanCleaner

    // Sync state
    private var isSyncing = false
    private var lastKnownICloudAvailability: Bool? = nil
    private var iCloudStatusSubscription: AnyCancellable?

    // Debounce state
    private var pendingProcessTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 0.5  // 500ms debounce

    // Constants
    private let maxRetryCount = 3

    // MARK: - Initialization

    init(localManager: LocalStorageManager, iCloudManager: iCloudDriveFileManager) {
        self.localManager = localManager
        self.iCloudManager = iCloudManager

        // Initialize components
        self.syncQueue = SyncQueue()
        self.fileEnumerator = FileEnumerator(localManager: localManager, iCloudManager: iCloudManager)
        self.orphanCleaner = OrphanCleaner(localManager: localManager, iCloudManager: iCloudManager)

        // Start monitoring and process queued operations
        Task {
            await startMonitoring()

            // Process any queued operations loaded from persistent storage
            let queueCount = await syncQueue.count()
            if queueCount > 0 {
                logger.info("Processing \(queueCount) operations loaded from persistent storage")
                await processQueue()
            }
        }
    }

    // MARK: - Public Queue Methods

    /// Queue an upload operation
    func queueUpload(fileID: String, relativePath: String) {
        let event = SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: .uploadToCloud,
            timestamp: Date()
        )
        enqueue(event)
    }

    /// Queue a download operation
    func queueDownload(fileID: String, relativePath: String) {
        let event = SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: .downloadFromCloud,
            timestamp: Date()
        )
        enqueue(event)
    }

    /// Queue a delete operation for cloud
    func queueCloudDelete(fileID: String, relativePath: String) {
        let event = SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: .deleteFromCloud,
            timestamp: Date()
        )
        enqueue(event)
    }

    /// Get current queue count
    func getQueueCount() async -> Int {
        return await syncQueue.count()
    }

    // MARK: - Queue Management

    /// Add event to queue and persist
    /// Automatically triggers processing after a short debounce interval
    /// - Parameter autoProcess: If true, automatically schedules queue processing (default: true)
    func enqueue(_ event: SyncEvent, autoProcess: Bool = true) {
        Task {
            await syncQueue.enqueue(event)

            // Update UI status - mark as queued
            let queuedOp: FileSyncStatus.QueuedOperation = switch event.operation {
                case .uploadToCloud: .upload
                case .downloadFromCloud: .download
                case .deleteFromCloud, .deleteFromLocal: .delete
            }
            Task { @MainActor in
                FileStatusService.shared.markSyncQueued(fileID: event.fileID, operation: queuedOp)
            }

            guard autoProcess else { return }

            // Cancel pending task if exists
            pendingProcessTask?.cancel()

            // Schedule new processing task with debounce
            pendingProcessTask = Task { [weak self] in
                guard let self = self else { return }

                // Wait for debounce interval
                try? await Task.sleep(nanoseconds: UInt64(self.debounceInterval * 1_000_000_000))

                // Check if task was cancelled during sleep
                guard !Task.isCancelled else { return }

                // Process the queue
                await self.processQueue()
            }
        }
    }

    // MARK: - iCloud Monitoring

    /// Start monitoring iCloud availability
    private func startMonitoring() async {
        await iCloudManager.startMonitoringICloudAvailability()

        // Subscribe to status changes
        iCloudStatusSubscription = await iCloudManager.iCloudStatusPublisher
            .sink { [weak self] status in
                guard let self = self else { return }
                Task {
                    await self.handleICloudStatusChange(status)
                }
            }
    }

    /// Handle iCloud status changes
    private func handleICloudStatusChange(_ status: ICloudAvailabilityStatus) async {
        logger.info("iCloud status changed: \(String(describing: status))")

        let wasAvailable = lastKnownICloudAvailability ?? false
        let isNowAvailable = status.isAvailable

        // Update last known status
        lastKnownICloudAvailability = isNowAvailable

        if isNowAvailable {
            if !wasAvailable {
                // iCloud just became available - perform full DiffScan
                // to discover any files that exist only in iCloud
                logger.info("iCloud became available, triggering DiffScan")
                do {
                    try await performDiffScan()
                } catch {
                    logger.error("Failed to perform DiffScan after iCloud became available: \(error.localizedDescription)")
                }
            } else {
                // iCloud was already available - just process queue
                await processQueue()
            }
        }
    }

    // MARK: - Queue Processing

    /// Process all queued sync operations
    func processQueue() async {
        guard !isSyncing else { return }

        let queueCount = await syncQueue.count()
        guard queueCount > 0 else { return }

        isSyncing = true

        logger.info("Processing \(queueCount) queued sync operations")

        // Create a snapshot of the queue to iterate over
        let queueSnapshot = await syncQueue.getAll()
        var processedEventIDs: Set<UUID> = []
        var failedEvents: [SyncEvent] = []

        // Process operations from snapshot
        for event in queueSnapshot {
            // Mark as syncing
            let syncOp: FileSyncStatus.QueuedOperation = switch event.operation {
                case .uploadToCloud: .upload
                case .downloadFromCloud: .download
                case .deleteFromCloud, .deleteFromLocal: .delete
            }
            Task { @MainActor in
                FileStatusService.shared.markSyncInProgress(fileID: event.fileID, operation: syncOp)
            }

            do {
                try await executeSyncOperation(event)
                // Success - mark for removal and update UI
                processedEventIDs.insert(event.id)

                Task { @MainActor in
                    FileStatusService.shared.markSyncCompleted(fileID: event.fileID)
                }
            } catch {
                logger.error("Failed to execute sync operation: \(error.localizedDescription)")

                // Mark original for removal
                processedEventIDs.insert(event.id)

                // Check retry count
                if event.retryCount < maxRetryCount {
                    // Re-queue with incremented retry count
                    let retryEvent = event.withIncrementedRetry()
                    failedEvents.append(retryEvent)
                } else {
                    logger.warning("Max retry count reached for sync operation, dropping")

                    // Mark as failed in UI
                    Task { @MainActor in
                        FileStatusService.shared.markSyncFailed(fileID: event.fileID, error: error.localizedDescription)
                    }
                }
            }
        }

        // Remove all processed events from queue
        await syncQueue.removeEvents(withIDs: processedEventIDs)

        // Add failed events back to queue
        for event in failedEvents {
            await syncQueue.enqueue(event)
        }

        // Release the lock before checking for more work
        isSyncing = false

        // Check if there are more events to process
        let remainingCount = await syncQueue.count()
        if remainingCount > 0 {
            logger.debug("Queue still has \(remainingCount) events, continuing processing")
            await processQueue()
        }
    }

    /// Execute a single sync operation
    private func executeSyncOperation(_ event: SyncEvent) async throws {
        let status = await iCloudManager.checkICloudAvailability()

        switch event.operation {
            case .uploadToCloud:
                guard status.isAvailable else {
                    throw FileStorageError.storageUnavailable
                }
                try await uploadToCloud(event: event)

            case .downloadFromCloud:
                guard status.isAvailable else {
                    throw FileStorageError.storageUnavailable
                }
                try await downloadFromCloud(event: event)

            case .deleteFromCloud:
                guard status.isAvailable else {
                    throw FileStorageError.storageUnavailable
                }
                try await iCloudManager.deleteContent(relativePath: event.relativePath)

            case .deleteFromLocal:
                try await localManager.deleteContent(relativePath: event.relativePath)
        }
    }

    // MARK: - Sync Operations

    /// Upload file to iCloud
    private func uploadToCloud(event: SyncEvent) async throws {
        // Load from local storage
        let localData = try await localManager.loadContent(relativePath: event.relativePath)
        let metadata = try await localManager.getFileMetadata(relativePath: event.relativePath)

        // Determine content type from file extension
        guard let contentType = FileStorageContentType.from(relativePath: event.relativePath) else {
            throw FileStorageError.writeFailed("Unknown file type for path: \(event.relativePath)")
        }

        // Upload to iCloud with conflict resolution
        let _ = try await iCloudManager.uploadToICloud(
            fileID: event.fileID,
            localData: localData,
            localUpdatedAt: metadata.modifiedAt,
            type: contentType
        )
    }

    /// Download file from iCloud
    private func downloadFromCloud(event: SyncEvent) async throws {
        // Load from iCloud
        let iCloudData = try await iCloudManager.loadContent(relativePath: event.relativePath)

        // Get iCloud metadata
        let iCloudURL = try await iCloudManager.getFileURL(relativePath: event.relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: iCloudURL.path)
        let iCloudModifiedAt = attributes[.modificationDate] as? Date ?? Date()

        // Determine content type from file extension
        guard let contentType = FileStorageContentType.from(relativePath: event.relativePath) else {
            logger.error("Unknown file type for path: \(event.relativePath), skipping download")
            return
        }

        // Save to local storage
        let saveResult = try await localManager.saveContent(
            iCloudData,
            fileID: event.fileID,
            type: contentType,
            updatedAt: iCloudModifiedAt
        )

        logger.info("Downloaded from iCloud: \(saveResult)")
    }

    // MARK: - DiffScan

    /// Perform differential scan between local and iCloud storage
    /// Call this on app startup to synchronize state
    ///
    /// Logic (以 CoreData 为 Source of Truth):
    /// 1. Enumerate all files that should exist from CoreData
    /// 2. For each expected file, check if it exists locally and in iCloud
    /// 3. Create sync operations based on the state
    /// 4. Clean up orphaned files (filesystem has but CoreData doesn't)
    func performDiffScan() async throws {
        logger.info("Starting DiffScan...")

        // Check iCloud availability
        let status = await iCloudManager.checkICloudAvailability()
        lastKnownICloudAvailability = status.isAvailable

        // Step 1: Get all files that should exist from CoreData
        let expectedFiles = await fileEnumerator.enumerateExpectedFiles()
        logger.info("Expected \(expectedFiles.count) files from CoreData")

        // Step 2: Enumerate actual files in local and iCloud
        let localFiles = try await fileEnumerator.enumerateLocalFiles()
        logger.info("Found \(localFiles.count) local files")

        var iCloudFiles: [SyncFileState] = []
        if status.isAvailable {
            iCloudFiles = try await fileEnumerator.enumerateICloudFiles()
            logger.info("Found \(iCloudFiles.count) iCloud files")
        } else {
            logger.warning("iCloud unavailable, skipping cloud comparison")
        }

        // Step 3: Build maps for quick lookup
        let localMap = Dictionary(uniqueKeysWithValues: localFiles.map { ($0.compositeKey, $0) })
        let iCloudMap = Dictionary(uniqueKeysWithValues: iCloudFiles.map { ($0.compositeKey, $0) })

        // Step 4: Compare expected files against actual files
        var syncOperations: [SyncEvent] = []
        let tolerance: TimeInterval = 2.0  // 2 seconds tolerance for filesystem precision

        for expectedFile in expectedFiles {
            let compositeKey = expectedFile.compositeKey
            let localFile = localMap[compositeKey]
            let iCloudFile = iCloudMap[compositeKey]

            switch (localFile, iCloudFile) {
                case (let local?, let cloud?):
                    // File exists in both - compare timestamps
                    let timeDifference = local.modifiedAt.timeIntervalSince(cloud.modifiedAt)

                    if timeDifference > tolerance {
                        logger.info("Local newer: \(compositeKey), local<\(local.modifiedAt)> cloud<\(cloud.modifiedAt)>")
                        syncOperations.append(SyncEvent(
                            fileID: local.fileID,
                            relativePath: local.relativePath,
                            operation: .uploadToCloud,
                            timestamp: Date()
                        ))
                    } else if timeDifference < -tolerance {
                        logger.info("Cloud newer: \(compositeKey), local<\(local.modifiedAt)> cloud<\(cloud.modifiedAt)>")
                        syncOperations.append(SyncEvent(
                            fileID: cloud.fileID,
                            relativePath: cloud.relativePath,
                            operation: .downloadFromCloud,
                            timestamp: Date()
                        ))
                    }
                    // If within tolerance, files are in sync - skip

                case (let local?, nil):
                    // File exists locally but not in iCloud
                    if status.isAvailable {
                        logger.info("Local only: \(compositeKey), uploading to cloud")
                        syncOperations.append(SyncEvent(
                            fileID: local.fileID,
                            relativePath: local.relativePath,
                            operation: .uploadToCloud,
                            timestamp: Date()
                        ))
                    }

                case (nil, let cloud?):
                    // File exists in iCloud but not locally
                    logger.info("Cloud only: \(compositeKey), downloading from cloud")
                    syncOperations.append(SyncEvent(
                        fileID: cloud.fileID,
                        relativePath: cloud.relativePath,
                        operation: .downloadFromCloud,
                        timestamp: Date()
                    ))

                case (nil, nil):
                    // File missing from both local and iCloud
                    logger.warning("File missing from both: \(compositeKey) (fileID: \(expectedFile.fileID))")

                    // Mark as missing in UI
                    Task { @MainActor in
                        FileStatusService.shared.markMissing(fileID: expectedFile.fileID, failureCount: 3)
                    }
            }
        }

        // Step 5: Clean up orphaned files (files without CoreData entities)
        await orphanCleaner.cleanupOrphanedFiles(
            localFiles: localFiles,
            iCloudFiles: iCloudFiles
        )

        logger.info("DiffScan complete: found \(syncOperations.count) sync operations")

        // Queue all sync operations without auto-processing
        for operation in syncOperations {
            enqueue(operation, autoProcess: false)
        }

        // Process queue once after all operations are queued
        await processQueue()
    }

    // MARK: - Helper Methods

    /// Check if iCloud has newer version than local
    func checkForICloudUpdate(relativePath: String) async throws -> Bool {
        // Check if file exists locally
        guard await localManager.fileExists(relativePath: relativePath) else {
            // File doesn't exist locally, check if it exists in iCloud
            let status = await iCloudManager.checkICloudAvailability()
            guard status.isAvailable else {
                return false
            }

            // Check if file actually exists in iCloud
            guard let iCloudURL = try? await iCloudManager.getFileURL(relativePath: relativePath),
                  FileManager.default.fileExists(atPath: iCloudURL.path) else {
                return false  // File doesn't exist in iCloud either
            }

            // File exists in iCloud but not locally - should download
            return true
        }

        // Get local modification date
        let metadata = try await localManager.getFileMetadata(relativePath: relativePath)
        let localModifiedAt = metadata.modifiedAt

        // Check iCloud availability
        let status = await iCloudManager.checkICloudAvailability()
        guard status.isAvailable else {
            return false
        }

        // Get iCloud modification date
        let iCloudURL = try await iCloudManager.getFileURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: iCloudURL.path) else {
            return false
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: iCloudURL.path)
        guard let iCloudModifiedAt = attributes[.modificationDate] as? Date else {
            return false
        }

        // Compare dates with tolerance
        let timeDifference = iCloudModifiedAt.timeIntervalSince(localModifiedAt)
        let tolerance: TimeInterval = 2.0  // 2 seconds tolerance for filesystem precision
        let hasNewerVersion = timeDifference > tolerance

        if hasNewerVersion {
            logger.info("iCloud has newer version: \(relativePath), local: \(localModifiedAt), iCloud: \(iCloudModifiedAt), diff: \(String(format: "%.2f", timeDifference))s")
        }

        return hasNewerVersion
    }

    /// Load content with iCloud version check
    func loadContentWithSync(relativePath: String, fileID: String) async throws -> Data {
        // Check if iCloud has newer version
        if try await checkForICloudUpdate(relativePath: relativePath) {
            logger.info("iCloud has newer version, downloading: \(relativePath)")

            // Download from iCloud
            let downloadEvent = SyncEvent(
                fileID: fileID,
                relativePath: relativePath,
                operation: .downloadFromCloud,
                timestamp: Date()
            )
            try await downloadFromCloud(event: downloadEvent)
        }

        // Load from local storage
        return try await localManager.loadContent(relativePath: relativePath)
    }
}
