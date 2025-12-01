//
//  iCloudDriveFileManager.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/20.
//

import Foundation
import Logging
import Combine

enum iCloudDriveError: LocalizedError {
    case containerNotAvailable
    case invalidDataURL
    case invalidBase64Data
    case downloadTimeout
    case fileNotFound
    case conflictUnresolved
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
            case .containerNotAvailable:
                return "iCloud Drive container is not available. Please ensure iCloud is enabled."
            case .invalidDataURL:
                return "Invalid data URL format"
            case .invalidBase64Data:
                return "Invalid base64 data"
            case .downloadTimeout:
                return "Timeout waiting for iCloud file download"
            case .fileNotFound:
                return "File not found in iCloud Drive"
            case .conflictUnresolved:
                return "File conflict could not be resolved"
            case .migrationFailed(let reason):
                return "Migration failed: \(reason)"
        }
    }
}

/// iCloud availability status
enum ICloudAvailabilityStatus: Equatable {
    case available
    case unavailable
    case error(String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
}

/// Manages file storage in iCloud Drive
/// Provides a centralized service for storing and retrieving files from iCloud Drive
/// instead of embedding large binary data in CoreData
actor iCloudDriveFileManager {
    static let shared = iCloudDriveFileManager()

    private let logger = Logger(label: "iCloudDriveFileManager")

    // MARK: - iCloud Status Monitoring

    private var iCloudStatusSubject = PassthroughSubject<ICloudAvailabilityStatus, Never>()
    private var currentStatus: ICloudAvailabilityStatus = .unavailable
    private var statusCheckTimer: Task<Void, Never>?

    /// Publisher for iCloud availability status changes
    var iCloudStatusPublisher: AnyPublisher<ICloudAvailabilityStatus, Never> {
        iCloudStatusSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Directory Structure
    
    enum Directory: String {
        case files = "Files"
        case collaborationFiles = "CollaborationFiles"
        case mediaItems = "MediaItems"
        case checkpoints = "Checkpoints"
        
        var path: String {
            return rawValue
        }
    }
    
    // MARK: - Helper Methods

    /// Map FileStorageContentType to Directory
    private func directory(for type: FileStorageContentType) -> Directory {
        switch type {
        case .file: return .files
        case .collaborationFile: return .collaborationFiles
        case .checkpoint: return .checkpoints
        case .mediaItem: return .mediaItems
        }
    }
    
    // MARK: - iCloud Container
    
    private var iCloudContainerURL: URL? {
        if let iCloudContainerURL = FileManager.default
            .url(forUbiquityContainerIdentifier: "iCloud.com.chocoford.excalidraw") {
            return iCloudContainerURL
                .appendingPathComponent("Data", conformingTo: .directory)
                .appendingPathComponent("FileStorage", conformingTo: .directory)
        } else {
            return localCacheURL
        }
    }
    private var localCacheURL: URL? {
        if let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            let dir = base.appendingPathComponent("LocalFileCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        return nil
    }
    
    private func ensureDirectoryExists(for directory: Directory) throws -> URL {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }
        
        let directoryURL = containerURL.appendingPathComponent(directory.path)
        
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        return directoryURL
    }
    
    // MARK: - Generic Content Operations
    
    /// Save content to iCloud Drive
    /// - Parameters:
    ///   - content: The content data
    ///   - id: The UUID identifier
    ///   - type: The content type (file, collaborationFile, or checkpoint)
    /// - Returns: The relative path to the stored file
    func saveContent(_ content: Data, id: UUID, type: FileStorageContentType) async throws -> String {
        let dir = directory(for: type)
        let directory = try ensureDirectoryExists(for: dir)
        let filename = "\(id.uuidString).\(type.fileExtension)"
        let fileURL = directory.appendingPathComponent(filename)

        try content.write(to: fileURL, options: .atomic)

        logger.info("Saved \(type) content to iCloud Drive: \(filename)")

        return "\(dir.path)/\(filename)"
    }
    
    /// Load content from iCloud Drive
    /// - Parameter relativePath: The relative path to the file
    /// - Returns: The content data
    func loadContent(relativePath: String) async throws -> Data {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }
        
        let fileURL = containerURL.appendingPathComponent(relativePath)
        
        // Check if file needs to be downloaded from iCloud
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try await downloadFileIfNeeded(url: fileURL)
        }
        
        return try Data(contentsOf: fileURL)
    }
    
    /// Delete content from iCloud Drive
    /// - Parameter relativePath: The relative path to the file
    func deleteContent(relativePath: String) async throws {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }
        
        let fileURL = containerURL.appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted content from iCloud Drive: \(relativePath)")
        }
    }
    
    // MARK: - MediaItem Operations
    
    /// Save MediaItem data to iCloud Drive
    /// - Parameters:
    ///   - dataURL: The base64 data URL string (e.g., "data:image/png;base64,...")
    ///   - itemID: The ID of the MediaItem
    /// - Returns: The relative path to the stored file
    func saveMediaItem(dataURL: String, itemID: String) async throws -> String {
        // Parse data URL to extract mime type and base64 data
        guard let (mimeType, base64Data) = parseDataURL(dataURL) else {
            throw iCloudDriveError.invalidDataURL
        }
        
        guard let data = Data(base64Encoded: base64Data) else {
            throw iCloudDriveError.invalidBase64Data
        }
        
        let directory = try ensureDirectoryExists(for: .mediaItems)
        let fileExtension = fileExtension(for: mimeType)
        let filename = "\(itemID).\(fileExtension)"
        let fileURL = directory.appendingPathComponent(filename)
        
        try data.write(to: fileURL, options: .atomic)
        
        logger.info("Saved media item to iCloud Drive: \(filename)")
        
        return "\(Directory.mediaItems.path)/\(filename)"
    }
    
    /// Load MediaItem data from iCloud Drive and convert to data URL
    /// - Parameter relativePath: The relative path to the file
    /// - Returns: The data URL string (e.g., "data:image/png;base64,...")
    func loadMediaItem(relativePath: String) async throws -> String {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }
        
        let fileURL = containerURL.appendingPathComponent(relativePath)
        
        // Check if file needs to be downloaded from iCloud
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try await downloadFileIfNeeded(url: fileURL)
        }
        
        let data = try Data(contentsOf: fileURL)
        let base64 = data.base64EncodedString()
        
        // Determine mime type from file extension
        let pathExtension = fileURL.pathExtension
        let mimeType = mimeType(for: pathExtension)
        
        return "data:\(mimeType);base64,\(base64)"
    }
    
    /// Delete MediaItem from iCloud Drive
    /// - Parameter relativePath: The relative path to the file
    func deleteMediaItem(relativePath: String) async throws {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }
        
        let fileURL = containerURL.appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted media item from iCloud Drive: \(relativePath)")
        }
    }
    
    // MARK: - FileCheckpoint Operations
    
    /// Save FileCheckpoint content to iCloud Drive
    /// - Parameters:
    ///   - content: The checkpoint content data
    ///   - checkpointID: The UUID of the FileCheckpoint entity
    /// - Returns: The relative path to the stored file
    func saveCheckpointContent(_ content: Data, checkpointID: UUID) async throws -> String {
        let directory = try ensureDirectoryExists(for: .checkpoints)
        let filename = "\(checkpointID.uuidString).excalidraw"
        let fileURL = directory.appendingPathComponent(filename)
        
        try content.write(to: fileURL, options: .atomic)
        
        logger.info("Saved checkpoint content to iCloud Drive: \(filename)")
        
        return "\(Directory.checkpoints.path)/\(filename)"
    }
    
    /// Load FileCheckpoint content from iCloud Drive
    /// - Parameter relativePath: The relative path to the file
    /// - Returns: The checkpoint content data
    func loadCheckpointContent(relativePath: String) async throws -> Data {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }
        
        let fileURL = containerURL.appendingPathComponent(relativePath)
        
        // Check if file needs to be downloaded from iCloud
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try await downloadFileIfNeeded(url: fileURL)
        }
        
        return try Data(contentsOf: fileURL)
    }
    
    /// Delete FileCheckpoint from iCloud Drive
    /// - Parameter relativePath: The relative path to the file
    func deleteCheckpointContent(relativePath: String) async throws {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }
        
        let fileURL = containerURL.appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            logger.info("Deleted checkpoint from iCloud Drive: \(relativePath)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func downloadFileIfNeeded(url: URL) async throws {
        // Check if file needs to be downloaded from iCloud
        let resourceValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        
        if let downloadingStatus = resourceValues.ubiquitousItemDownloadingStatus {
            // If file is not downloaded, start downloading
            if downloadingStatus != .current {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
                
                // Wait for download with timeout
                let timeout = Date().addingTimeInterval(30) // 30 seconds timeout
                
                while !FileManager.default.fileExists(atPath: url.path) {
                    if Date() > timeout {
                        throw iCloudDriveError.downloadTimeout
                    }
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                }
            }
        }
    }
    
    private func parseDataURL(_ dataURL: String) -> (mimeType: String, base64Data: String)? {
        // Format: data:image/png;base64,iVBORw0KGgo...
        guard dataURL.hasPrefix("data:") else { return nil }
        
        let components = dataURL.dropFirst(5).split(separator: ",", maxSplits: 1)
        guard components.count == 2 else { return nil }
        
        let header = String(components[0])
        let base64 = String(components[1])
        
        // Extract mime type from header (e.g., "image/png;base64" -> "image/png")
        let mimeType = header.split(separator: ";").first.map(String.init) ?? "application/octet-stream"
        
        return (mimeType, base64)
    }
    
    private func fileExtension(for mimeType: String) -> String {
        switch mimeType {
            case "image/png": return "png"
            case "image/jpeg", "image/jpg": return "jpg"
            case "image/gif": return "gif"
            case "image/svg+xml": return "svg"
            case "application/pdf": return "pdf"
            case "image/webp": return "webp"
            default: return "dat"
        }
    }
    
    private func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
            case "png": return "image/png"
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "svg": return "image/svg+xml"
            case "pdf": return "application/pdf"
            case "webp": return "image/webp"
            default: return "application/octet-stream"
        }
    }

    // MARK: - iCloud Status Detection Module

    /// Check if iCloud Drive is currently available
    func checkICloudAvailability() -> ICloudAvailabilityStatus {
        // Check if container URL is available
        guard let containerURL = FileManager.default
            .url(forUbiquityContainerIdentifier: "iCloud.com.chocoford.excalidraw") else {
            return .unavailable
        }

        // Try to access the container to verify it's actually accessible
        do {
            let resourceValues = try containerURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if resourceValues.volumeAvailableCapacity != nil {
                return .available
            } else {
                return .error("iCloud container exists but is not accessible")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Start monitoring iCloud availability changes
    func startMonitoringICloudAvailability() {
        // Stop existing timer
        statusCheckTimer?.cancel()

        // Check initial status
        let initialStatus = checkICloudAvailability()
        if currentStatus != initialStatus {
            currentStatus = initialStatus
            iCloudStatusSubject.send(initialStatus)
            logger.info("iCloud initial status: \(String(describing: initialStatus))")
        }

        // Start periodic checking (every 30 seconds)
        statusCheckTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds

                let newStatus = checkICloudAvailability()
                if currentStatus != newStatus {
                    let oldStatus = currentStatus
                    currentStatus = newStatus
                    iCloudStatusSubject.send(newStatus)
                    logger.info("iCloud status changed: \(String(describing: oldStatus)) -> \(String(describing: newStatus))")
                }
            }
        }
    }

    /// Stop monitoring iCloud availability changes
    func stopMonitoringICloudAvailability() {
        statusCheckTimer?.cancel()
        statusCheckTimer = nil
    }

    /// Get current iCloud availability status
    func getCurrentStatus() -> ICloudAvailabilityStatus {
        return currentStatus
    }

    // MARK: - Upload/Download Operations

    /// Upload a file from local storage to iCloud Drive
    /// Called by SyncCoordinator after DiffScan determines local is newer
    /// Directly uploads and overwrites iCloud version without conflict checking
    /// - Parameters:
    ///   - fileID: The UUID of the file
    ///   - localData: The local file content
    ///   - localUpdatedAt: The local file's last update time
    ///   - type: The content type
    /// - Returns: The relative path in iCloud Drive
    func uploadToICloud(
        fileID: String,
        localData: Data,
        localUpdatedAt: Date?,
        type: FileStorageContentType
    ) async throws -> String {
        logger.debug("Uploading \(type) to iCloud: \(fileID)")

        // Check iCloud availability
        let status = checkICloudAvailability()
        guard status.isAvailable else {
            throw iCloudDriveError.migrationFailed("iCloud is not available: \(status)")
        }

        // Get URLs and ensure directory exists
        let dir = directory(for: type)
        let directory = try ensureDirectoryExists(for: dir)
        let filename = "\(fileID).\(type.fileExtension)"
        let iCloudURL = directory.appendingPathComponent(filename)
        let relativePath = "\(dir.path)/\(filename)"

        // Upload to iCloud (overwrite if exists)
        try localData.write(to: iCloudURL, options: .atomic)

        // Set iCloud timestamp to match local
        let date = localUpdatedAt ?? Date()
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: iCloudURL.path)

        logger.info("Successfully uploaded to iCloud: \(relativePath)")
        return relativePath
    }

    /// Migrate a media item from local storage to iCloud Drive
    /// - Parameters:
    ///   - mediaID: The ID of the media item
    ///   - dataURL: The base64 data URL
    ///   - localUpdatedAt: The local file's last update time
    /// - Returns: The relative path in iCloud Drive
    func migrateMediaItemToICloud(
        mediaID: String,
        dataURL: String,
        localUpdatedAt: Date?
    ) async throws -> String {
        logger.info("Starting media item migration for ID: \(mediaID)")

        // Parse data URL
        guard let (mimeType, base64Data) = parseDataURL(dataURL),
              let data = Data(base64Encoded: base64Data) else {
            throw iCloudDriveError.invalidDataURL
        }

        // Check iCloud availability
        let status = checkICloudAvailability()
        guard status.isAvailable else {
            throw iCloudDriveError.migrationFailed("iCloud is not available: \(status)")
        }

        let directory = try ensureDirectoryExists(for: .mediaItems)
        let fileExtension = fileExtension(for: mimeType)
        let filename = "\(mediaID).\(fileExtension)"
        let iCloudURL = directory.appendingPathComponent(filename)
        let relativePath = "\(Directory.mediaItems.path)/\(filename)"

        // Check if file exists in iCloud
        if FileManager.default.fileExists(atPath: iCloudURL.path) {
            logger.info("Media item already exists in iCloud, skipping")
            return relativePath
        }

        // Upload to iCloud
        try data.write(to: iCloudURL, options: .atomic)
        // Always set iCloud timestamp (use local date or current time)
        let date = localUpdatedAt ?? Date()
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: iCloudURL.path)

        logger.info("Successfully migrated media item to iCloud: \(relativePath)")
        return relativePath
    }

    // MARK: - Migration Support
    
    /// Check if iCloud Drive is available
    var isICloudAvailable: Bool {
        iCloudContainerURL != nil
    }
    
    /// Get the total size of all files in iCloud Drive
    func getTotalStorageSize() async throws -> Int64 {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }

        var totalSize: Int64 = 0

        let enumerator = FileManager.default.enumerator(
            at: containerURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    // MARK: - Public Helper Methods

    /// Get the iCloud container URL (public accessor)
    var containerURL: URL? {
        return iCloudContainerURL
    }

    /// Get the full URL for a relative path in iCloud
    func getFileURL(relativePath: String) throws -> URL {
        guard let containerURL = iCloudContainerURL else {
            throw iCloudDriveError.containerNotAvailable
        }
        return containerURL.appendingPathComponent(relativePath)
    }
}
