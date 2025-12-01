//
//  SyncCoordinator.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/26.
//

import Foundation
import Logging
import Combine

/// Sync operation type
enum SyncOperation: Codable, CustomStringConvertible {
    case uploadToCloud      // Local → iCloud
    case downloadFromCloud  // iCloud → Local
    case deleteFromCloud    // Remove from iCloud
    case deleteFromLocal    // Remove from local

    var description: String {
        switch self {
            case .uploadToCloud: return "upload to cloud"
            case .downloadFromCloud: return "download from cloud"
            case .deleteFromCloud: return "delete from cloud"
            case .deleteFromLocal: return "delete from local"
        }
    }
}

/// Sync event with operation details
struct SyncEvent: Codable, Identifiable {
    let id: UUID
    let fileID: String
    let relativePath: String
    let operation: SyncOperation
    let timestamp: Date
    let retryCount: Int

    init(fileID: String, relativePath: String, operation: SyncOperation, timestamp: Date = Date(), retryCount: Int = 0) {
        self.id = UUID()
        self.fileID = fileID
        self.relativePath = relativePath
        self.operation = operation
        self.timestamp = timestamp
        self.retryCount = retryCount
    }

    /// Create a new event with incremented retry count
    func withIncrementedRetry() -> SyncEvent {
        return SyncEvent(
            fileID: fileID,
            relativePath: relativePath,
            operation: operation,
            timestamp: timestamp,
            retryCount: retryCount + 1
        )
    }
}

/// File state for synchronization comparison
struct SyncFileState: Equatable, Hashable {
    let fileID: String
    let relativePath: String
    let contentType: FileStorageContentType
    let modifiedAt: Date
    let size: Int64

    enum Location {
        case local
        case iCloud
    }

    /// Composite key for unique identification
    var compositeKey: String {
        return "\(fileID):\(contentType.description)"
    }
}

/// Coordinator for bidirectional file synchronization
actor SyncCoordinator {
    private let logger = Logger(label: "SyncCoordinator")
    
    // Dependencies
    private let localManager: LocalStorageManager
    private let iCloudManager: iCloudDriveFileManager
    
    // Persistent sync queue
    private var syncQueue: [SyncEvent] = []
    private let queueKey = "com.excalidrawz.syncQueue"
    private let maxRetryCount = 3
    private var isQueueLoaded = false

    // Sync state
    private var isSyncing = false
    private var lastKnownICloudAvailability: Bool? = nil
    private var iCloudStatusSubscription: AnyCancellable?

    // Debounce state
    private var pendingProcessTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 0.5  // 500ms debounce

    // MARK: - Initialization

    init(localManager: LocalStorageManager, iCloudManager: iCloudDriveFileManager) {
        self.localManager = localManager
        self.iCloudManager = iCloudManager

        // Load queue synchronously during init to prevent race conditions
        if let data = UserDefaults.standard.data(forKey: queueKey) {
            do {
                let decoder = JSONDecoder()
                let loadedQueue = try decoder.decode([SyncEvent].self, from: data)
                self.syncQueue = loadedQueue
                self.isQueueLoaded = true
                let queueCount = loadedQueue.count
                logger.info("Loaded \(queueCount) queued sync operations")
            } catch {
                logger.error("Failed to load sync queue: \(error.localizedDescription)")
                self.syncQueue = []
                self.isQueueLoaded = true
            }
        } else {
            self.isQueueLoaded = true
        }

        // Capture queue state before entering Task
        let hasQueuedOperations = !syncQueue.isEmpty
        let initialQueueCount = syncQueue.count

        // Start monitoring iCloud asynchronously
        Task {
            await startMonitoring()

            // Process any queued operations loaded from persistent storage
            if hasQueuedOperations {
                logger.info("Processing \(initialQueueCount) operations loaded from persistent storage")
                await processQueue()
            }
        }
    }

    // MARK: - Queue Persistence
    
    /// Save sync queue to persistent storage
    private func saveQueue() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(syncQueue)
            UserDefaults.standard.set(data, forKey: queueKey)
        } catch {
            logger.error("Failed to save sync queue: \(error.localizedDescription)")
        }
    }
    
    /// Add event to queue and persist
    /// Automatically triggers processing after a short debounce interval
    /// - Parameter autoProcess: If true, automatically schedules queue processing (default: true)
    func enqueue(_ event: SyncEvent, autoProcess: Bool = true) {
        syncQueue.append(event)
        saveQueue()
        logger.debug("Queued sync operation: \(event.operation) for \(event.relativePath)")

        // Update UI status - mark as queued
        let queuedOp: FileSyncStatus.QueuedOperation = switch event.operation {
        case .uploadToCloud: .upload
        case .downloadFromCloud: .download
        case .deleteFromCloud, .deleteFromLocal: .delete
        }
        Task { @MainActor in
            SyncStatusState.shared.markQueued(fileID: event.fileID, operation: queuedOp)
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
    
    /// Remove event from queue and persist
    private func dequeue(_ event: SyncEvent) {
        syncQueue.removeAll { $0.id == event.id }
        saveQueue()
    }
    
    /// Get current queue count
    func getQueueCount() -> Int {
        return syncQueue.count
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
        guard !syncQueue.isEmpty else { return }

        isSyncing = true

        logger.info("Processing \(self.syncQueue.count) queued sync operations")

        // Create a snapshot of the queue to iterate over
        let queueSnapshot = syncQueue
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
                SyncStatusState.shared.markSyncing(fileID: event.fileID, operation: syncOp)
            }

            do {
                try await executeSyncOperation(event)
                // Success - mark for removal and update UI
                processedEventIDs.insert(event.id)

                Task { @MainActor in
                    SyncStatusState.shared.markCompleted(fileID: event.fileID)
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
                        SyncStatusState.shared.markFailed(fileID: event.fileID, error: error.localizedDescription)
                    }
                }
            }
        }

        // Remove all processed events from queue
        syncQueue.removeAll { processedEventIDs.contains($0.id) }
        saveQueue()

        // Add failed events back to queue
        for event in failedEvents {
            syncQueue.append(event)
        }
        if !failedEvents.isEmpty {
            saveQueue()
        }

        // Release the lock before checking for more work
        isSyncing = false

        // Check if there are more events to process
        // (events added during processing or failed events for retry)
        if !syncQueue.isEmpty {
            logger.debug("Queue still has \(self.syncQueue.count) events, continuing processing")
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
        guard let contentType = determineContentType(from: event.relativePath) else {
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
        guard let contentType = determineContentType(from: event.relativePath) else {
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
    func performDiffScan() async throws {
        logger.info("Starting DiffScan...")

        // Check iCloud availability
        let status = await iCloudManager.checkICloudAvailability()
        lastKnownICloudAvailability = status.isAvailable
        
        // Enumerate local files
        let localFiles = try await enumerateLocalFiles()
        logger.info("Found \(localFiles.count) local files")
        
        // Enumerate iCloud files (if available)
        var iCloudFiles: [SyncFileState] = []
        if status.isAvailable {
            iCloudFiles = try await enumerateICloudFiles()
            logger.info("Found \(iCloudFiles.count) iCloud files")
        } else {
            logger.warning("iCloud unavailable, skipping cloud comparison")
        }
        
        // Build file maps for comparison using composite key (fileID + contentType)
        let localMap = Dictionary(uniqueKeysWithValues: localFiles.map { ($0.compositeKey, $0) })
        let iCloudMap = Dictionary(uniqueKeysWithValues: iCloudFiles.map { ($0.compositeKey, $0) })
        
        // Find differences
        var syncOperations: [SyncEvent] = []

        // Check local files
        for (compositeKey, localFile) in localMap {
            if let iCloudFile = iCloudMap[compositeKey] {
                // File exists in both - compare timestamps with tolerance
                let timeDifference = localFile.modifiedAt.timeIntervalSince(iCloudFile.modifiedAt)
                let tolerance: TimeInterval = 2.0  // 2 seconds tolerance for filesystem precision

                if timeDifference > tolerance {
                    logger.info("Found diff<\(compositeKey)>, local<\(localFile.modifiedAt)> cloud<\(iCloudFile.modifiedAt)>")
                    // Local is newer - upload
                    syncOperations.append(SyncEvent(
                        fileID: localFile.fileID,
                        relativePath: localFile.relativePath,
                        operation: .uploadToCloud,
                        timestamp: Date()
                    ))
                } else if timeDifference < -tolerance {
                    logger.info("Found diff<\(compositeKey)>, local<\(localFile.modifiedAt)> cloud<\(iCloudFile.modifiedAt)>")
                    // iCloud is newer - download
                    syncOperations.append(SyncEvent(
                        fileID: iCloudFile.fileID,
                        relativePath: iCloudFile.relativePath,
                        operation: .downloadFromCloud,
                        timestamp: Date()
                    ))
                }
                // If within tolerance, files are in sync - skip
            } else if status.isAvailable {
                // File only exists locally - upload to iCloud
                syncOperations.append(SyncEvent(
                    fileID: localFile.fileID,
                    relativePath: localFile.relativePath,
                    operation: .uploadToCloud,
                    timestamp: Date()
                ))
            }
        }

        // Check iCloud files for ones not in local
        if status.isAvailable {
            for (compositeKey, iCloudFile) in iCloudMap {
                if localMap[compositeKey] == nil {
                    // File only exists in iCloud - download
                    syncOperations.append(SyncEvent(
                        fileID: iCloudFile.fileID,
                        relativePath: iCloudFile.relativePath,
                        operation: .downloadFromCloud,
                        timestamp: Date()
                    ))
                }
            }
        }
        
        logger.info("DiffScan complete: found \(syncOperations.count) sync operations")

        // Queue all sync operations without auto-processing
        for operation in syncOperations {
            enqueue(operation, autoProcess: false)
        }

        // Process queue once after all operations are queued
        await processQueue()
    }
    
    /// Enumerate all local files
    private func enumerateLocalFiles() async throws -> [SyncFileState] {
        var files: [SyncFileState] = []

        guard let storageURL = await localManager.getStorageURL() else {
            return files
        }

        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: storageURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Check if it's a regular file
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            // Extract fileID from filename
            let filename = fileURL.lastPathComponent
            let components = filename.split(separator: ".")
            guard let fileIDSubstring = components.first else {
                continue
            }
            let fileID = String(fileIDSubstring)

            // Get metadata
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
            let size = attributes[.size] as? Int64 ?? 0

            // Get relative path
            let relativePath = String(fileURL.path.dropFirst(storageURL.path.count + 1))

            // Determine content type from file extension
            guard let contentType = determineContentType(from: relativePath) else {
                // Skip files with unknown extensions
                continue
            }

            files.append(SyncFileState(
                fileID: fileID,
                relativePath: relativePath,
                contentType: contentType,
                modifiedAt: modifiedAt,
                size: size
            ))
        }

        return files
    }
    
    /// Enumerate all iCloud files
    private func enumerateICloudFiles() async throws -> [SyncFileState] {
        var files: [SyncFileState] = []

        guard let containerURL = await iCloudManager.containerURL else {
            return files
        }

        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: containerURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            // Check if it's a regular file
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }

            // Extract fileID from filename
            let filename = fileURL.lastPathComponent
            let components = filename.split(separator: ".")
            guard let fileIDSubstring = components.first else {
                continue
            }
            let fileID = String(fileIDSubstring)

            // Get metadata
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
            let size = attributes[.size] as? Int64 ?? 0

            // Get relative path
            let relativePath = String(fileURL.path.dropFirst(containerURL.path.count + 1))

            // Determine content type from file extension
            guard let contentType = determineContentType(from: relativePath) else {
                // Skip files with unknown extensions
                continue
            }

            files.append(SyncFileState(
                fileID: fileID,
                relativePath: relativePath,
                contentType: contentType,
                modifiedAt: modifiedAt,
                size: size
            ))
        }

        return files
    }
    
    // MARK: - Helper Methods
    
    /// Determine content type from file extension
    private func determineContentType(from relativePath: String) -> FileStorageContentType? {
        let fileExtension = (relativePath as NSString).pathExtension

        switch fileExtension {
        case "excalidrawz":
            return .file
        case "excalidrawz_collab":
            return .collaborationFile
        case "excalidrawz_checkpoint":
            return .checkpoint
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "pdf", "dat":
            // Media items can have various image extensions or .dat
            return .mediaItem(extension: fileExtension)
        default:
            // Unknown file type, skip it
            return nil
        }
    }
    
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
