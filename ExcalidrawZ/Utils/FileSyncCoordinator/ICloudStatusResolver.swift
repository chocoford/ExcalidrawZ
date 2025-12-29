//
//  ICloudStatusResolver.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/23/25.
//

import Foundation
import Logging

/// Resolves iCloud status for files using url.resourceValues
///
/// This actor provides the actual iCloud status checking capability
/// that NSMetadataQuery lacks. While NSMetadataQuery can tell us
/// when files change, we need url.resourceValues to get the actual
/// iCloud download/upload status.
actor ICloudStatusResolver {
    private let logger = Logger(label: "ICloudStatusResolver")
    
    /// Check iCloud status for a single file
    /// - Parameter url: The file URL to check
    /// - Returns: The current FileStatus
    /// - Throws: Error if unable to read resource values
    func checkStatus(for url: URL) async throws -> FileStatus {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                // Check if file is in iCloud Drive
                let ubiquitousValues = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
                guard ubiquitousValues.isUbiquitousItem == true else {
                    continuation.resume(returning: .local)
                    return
                }
                
                // Get iCloud-specific resource values for basic status
                let keys: Set<URLResourceKey> = [
                    .ubiquitousItemDownloadingStatusKey,
                    .ubiquitousItemIsDownloadingKey,
                    .ubiquitousItemIsUploadingKey,
                    .ubiquitousItemHasUnresolvedConflictsKey,
                ]
                
                let values = try url.resourceValues(forKeys: keys)
                
                // Check for conflicts first (fast check using resourceValues)
                if values.ubiquitousItemHasUnresolvedConflicts == true {
                    continuation.resume(returning: .conflict)
                    return
                }
                
                // Check upload status
                if values.ubiquitousItemIsUploading == true {
                    continuation.resume(returning: .uploading)
                    return
                }
                
                // Check downloading status
                if values.ubiquitousItemIsDownloading == true {
                    continuation.resume(returning: .downloading(progress: nil))
                    return
                }
                
                // Check download status using ubiquitousItemDownloadingStatus
                // This is the source of truth for file sync state:
                // - .notDownloaded: File exists in cloud but not downloaded locally
                // - .downloaded: File is downloaded but may not be current (outdated)
                // - .current: File is up to date with iCloud
                if let downloadStatus = values.ubiquitousItemDownloadingStatus {
                    switch downloadStatus {
                        case .notDownloaded:
                            continuation.resume(returning: .notDownloaded)
                            return
                        case .downloaded:
                            // File is downloaded but not current - cloud has newer version
                            continuation.resume(returning: .outdated)
                            return
                        case .current:
                            // File is up to date
                            continuation.resume(returning: .downloaded)
                            return
                        default:
                            break
                    }
                }
                
                // Fallback: assume file is downloaded
                continuation.resume(returning: .downloaded)
                
            } catch {
                logger.error("Failed to check iCloud status for \(url.lastPathComponent): \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Batch check iCloud status for multiple files
    /// - Parameter urls: Array of file URLs to check
    /// - Returns: Dictionary mapping URLs to their FileStatus
    func batchCheckStatus(_ urls: [URL]) async -> [URL: FileStatus] {
        var results: [URL: FileStatus] = [:]
        
        // Check files concurrently with limited concurrency
        await withTaskGroup(of: (URL, FileStatus?).self) { group in
            for url in urls {
                group.addTask {
                    do {
                        let status = try await self.checkStatus(for: url)
                        return (url, status)
                    } catch {
                        self.logger.error("Error checking status for \(url.lastPathComponent): \(error)")
                        return (url, .error(error.localizedDescription))
                    }
                }
            }
            
            for await (url, status) in group {
                if let status = status {
                    results[url] = status
                }
            }
        }
        
        return results
    }
}
