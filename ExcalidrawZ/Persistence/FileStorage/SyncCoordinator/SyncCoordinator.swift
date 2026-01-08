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
    /// - Parameters:
    ///   - fileID: File identifier
    ///   - relativePath: Relative path for storage
    ///   - priority: Sync priority (.high for user-triggered operations, .normal for background DiffScan)
    func queueUpload(fileID: String, relativePath: String, priority: SyncPriority = .high) {
        let event = SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: .uploadToCloud,
            timestamp: Date(),
            priority: priority
        )
        Task {
            await enqueue(event)
        }
    }
    
    /// Queue a download operation
    /// - Parameters:
    ///   - fileID: File identifier
    ///   - relativePath: Relative path for storage
    ///   - priority: Sync priority (.high for user-triggered operations, .normal for background DiffScan)
    func queueDownload(fileID: String, relativePath: String, priority: SyncPriority = .high) {
        let event = SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: .downloadFromCloud,
            timestamp: Date(),
            priority: priority
        )
        Task {
            await enqueue(event)
        }
    }
    
    /// Queue a delete operation for cloud
    /// - Parameters:
    ///   - fileID: File identifier
    ///   - relativePath: Relative path for storage
    ///   - priority: Sync priority (.high for user-triggered operations, .normal for background DiffScan)
    func queueCloudDelete(fileID: String, relativePath: String, priority: SyncPriority = .high) {
        let event = SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: .deleteFromCloud,
            timestamp: Date(),
            priority: priority
        )
        Task {
            await enqueue(event)
        }
    }
    
    /// Get current queue count
    func getQueueCount() async -> Int {
        return await syncQueue.count()
    }
    
    // MARK: - Queue Management
    
    /// Add event to queue and persist
    /// Automatically triggers processing after a short debounce interval
    /// - Parameter autoProcess: If true, automatically schedules queue processing (default: true)
    func enqueue(_ event: SyncEvent, autoProcess: Bool = true) async {
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
    /// Uses dynamic dequeue to allow high-priority tasks to jump the queue
    func processQueue() async {
        guard !isSyncing else { return }
        
        let initialCount = await syncQueue.count()
        guard initialCount > 0 else { return }
        
        isSyncing = true
        
        logger.info("Processing \(initialCount) queued sync operations")
        
        var processedCount = 0
        var failedCount = 0
        
        // Initialize overall progress tracking
        await FileStatusService.shared.updateOverallProgress(current: 0, total: initialCount)
        
        // Process operations one by one from the queue
        // This allows high-priority tasks added during processing to be processed immediately
        while let event = await syncQueue.dequeueFirst() {
            processedCount += 1
            logger.info("Processing operation \(processedCount): \(event.operation) for \(event.relativePath)")
            
            // Mark as syncing
            let syncOp: FileSyncStatus.QueuedOperation = switch event.operation {
                case .uploadToCloud: .upload
                case .downloadFromCloud: .download
                case .deleteFromCloud, .deleteFromLocal: .delete
            }
            await FileStatusService.shared.markSyncInProgress(fileID: event.fileID, operation: syncOp)
            
            do {
                try await executeSyncOperation(event)
                // Success - mark as completed in UI
                await FileStatusService.shared.markSyncCompleted(fileID: event.fileID)
                
                // Update overall progress
                await FileStatusService.shared.updateOverallProgress(current: processedCount, total: initialCount)
            } catch {
                logger.error("Failed to execute sync operation: \(error.localizedDescription)")
                
                // Check retry count
                if event.retryCount < maxRetryCount {
                    // Re-queue with incremented retry count
                    let retryEvent = event.withIncrementedRetry()
                    // Use enqueue() to ensure proper status updates, but don't auto-process
                    // since we're already in processQueue
                    await enqueue(retryEvent, autoProcess: false)
                    failedCount += 1
                } else {
                    logger.warning("Max retry count reached for sync operation, dropping")
                    
                    // Mark as failed in UI
                    await FileStatusService.shared.markSyncFailed(fileID: event.fileID, error: error.localizedDescription)
                }
                
                // Update overall progress even on failure
                await FileStatusService.shared.updateOverallProgress(current: processedCount, total: initialCount)
            }
        }
        
        logger.info("Completed processing: \(processedCount) total, \(failedCount) failed and re-queued")
        
        // Release the lock before checking for more work
        isSyncing = false
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
    
    /// Upload file to iCloud (force overwrite)
    ///
    /// This method unconditionally uploads local content to iCloud, overwriting any existing file.
    /// It does NOT perform conflict detection - the caller is responsible for checking
    /// whether iCloud has a newer version before queueing this operation.
    ///
    /// Conflict detection should happen at the decision layer (DiffScan, FileState),
    /// not in the execution layer (SyncCoordinator).
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
    ///
    /// Downloads file content from iCloud and saves to local storage.
    /// Note: On iOS, the modificationDate read from iCloud may be cached/stale
    /// if metadata wasn't refreshed before calling this method.
    private func downloadFromCloud(event: SyncEvent) async throws {
        // Load from iCloud
        let iCloudData = try await iCloudManager.loadContent(relativePath: event.relativePath)
        
        // Get iCloud metadata
        let iCloudURL = try await iCloudManager.getFileURL(relativePath: event.relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: iCloudURL.filePath)
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
    /// 5. If many files are missing (possible first sync), trigger container download and retry once
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
        var missingCount = 0  // Track (nil, nil) cases
        let tolerance: TimeInterval = 2.0  // 2 seconds tolerance for filesystem precision
        
        for expectedFile in expectedFiles {
            let compositeKey = expectedFile.compositeKey
            let localFile = localMap[compositeKey]
            let iCloudFile = iCloudMap[compositeKey]
            
            switch (localFile, iCloudFile) {
                case (let local?, let cloud?):
                    // File exists in both
                    
#if os(macOS)
                    // macOS: For .notDownloaded files, compare timestamps first to avoid unnecessary downloads
                    // macOS placeholder metadata is synced from iCloud and is reliable for timestamp comparison
                    if let downloadStatus = cloud.downloadStatus, downloadStatus == .notDownloaded {
                        // Compare timestamps
                        let timeDifference = local.modifiedAt.timeIntervalSince(cloud.modifiedAt)

                        if timeDifference < -tolerance {
                            // Cloud is newer, download it
                            logger.info("Cloud file not downloaded but newer: \(compositeKey), local<\(local.modifiedAt)> cloud<\(cloud.modifiedAt)>, downloading")
                            syncOperations.append(SyncEvent(
                                fileID: cloud.fileID,
                                relativePath: cloud.relativePath,
                                operation: .downloadFromCloud,
                                timestamp: Date(),
                                priority: .normal  // DiffScan: background priority
                            ))
                        } else if timeDifference > tolerance {
                            // Local is newer, upload to ensure cloud has latest
                            logger.info("Cloud file not downloaded and older: \(compositeKey), local<\(local.modifiedAt)> cloud<\(cloud.modifiedAt)>, uploading")
                            syncOperations.append(SyncEvent(
                                fileID: local.fileID,
                                relativePath: local.relativePath,
                                operation: .uploadToCloud,
                                timestamp: Date(),
                                priority: .normal  // DiffScan: background priority
                            ))
                        } else {
                            // Within tolerance, in sync - skip download
                            logger.debug("Cloud file not downloaded but in sync: \(compositeKey), skipping")
                        }
                        continue
                    }
#endif
                    
                    // Compare timestamps
                    let timeDifference = local.modifiedAt.timeIntervalSince(cloud.modifiedAt)
                    
                    if timeDifference > tolerance {
                        logger.info("Local newer: \(compositeKey), local<\(local.modifiedAt)> cloud<\(cloud.modifiedAt)>")
                        syncOperations.append(SyncEvent(
                            fileID: local.fileID,
                            relativePath: local.relativePath,
                            operation: .uploadToCloud,
                            timestamp: Date(),
                            priority: .normal  // DiffScan: background priority
                        ))
                    } else if timeDifference < -tolerance {
                        logger.info("Cloud newer: \(compositeKey), local<\(local.modifiedAt)> cloud<\(cloud.modifiedAt)>")
                        syncOperations.append(SyncEvent(
                            fileID: cloud.fileID,
                            relativePath: cloud.relativePath,
                            operation: .downloadFromCloud,
                            timestamp: Date(),
                            priority: .normal  // DiffScan: background priority
                        ))
                    }
                    // If within tolerance, files are in sync - skip
                    
                case (let local?, nil):
                    // File exists locally but not in iCloud
                    if status.isAvailable {
                        logger.info("Local only: \(local.relativePath), uploading to cloud")
                        syncOperations.append(SyncEvent(
                            fileID: local.fileID,
                            relativePath: local.relativePath,
                            operation: .uploadToCloud,
                            timestamp: Date(),
                            priority: .normal  // DiffScan: background priority
                        ))
                    }
                    
                case (nil, let cloud?):
                    // File exists in iCloud but not locally
                    logger.info("Cloud only: \(cloud.relativePath), downloading from cloud")
                    syncOperations.append(SyncEvent(
                        fileID: cloud.fileID,
                        relativePath: cloud.relativePath,
                        operation: .downloadFromCloud,
                        timestamp: Date(),
                        priority: .normal  // DiffScan: background priority
                    ))
                    
                case (nil, nil):
                    // File missing from both local and iCloud
                    missingCount += 1
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
            await enqueue(operation, autoProcess: false)
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
                  FileManager.default.fileExists(at: iCloudURL) else {
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
        guard FileManager.default.fileExists(at: iCloudURL) else {
            return false
        }
        
#if os(iOS)
        // iOS: Force refresh metadata from iCloud before checking timestamps
        // On iOS, placeholder files may have cached/stale timestamps that don't reflect
        // the actual iCloud state. startDownloadingUbiquitousItem forces iOS to refresh
        // metadata from iCloud, ensuring we get accurate modification times.
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: iCloudURL)
            // Give it a moment to update metadata
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        } catch {
            logger.warning("Failed to refresh iCloud metadata for \(relativePath): \(error)")
            // Continue anyway and check with cached metadata
        }
#endif
        
        let attributes = try FileManager.default.attributesOfItem(atPath: iCloudURL.filePath)
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
