//
//  FileEnumerator.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/12/31.
//

import Foundation
import CoreData
import Logging

/// File enumeration from different sources (local, iCloud, CoreData)
struct FileEnumerator {
    private let logger = Logger(label: "FileEnumerator")
    private let localManager: LocalStorageManager
    private let iCloudManager: iCloudDriveFileManager

    init(localManager: LocalStorageManager, iCloudManager: iCloudDriveFileManager) {
        self.localManager = localManager
        self.iCloudManager = iCloudManager
    }

    // MARK: - File Enumeration

    /// Enumerate all local files
    func enumerateLocalFiles() async throws -> [SyncFileState] {
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
            print("[DEBUG] enumerateLocalFiles", fileURL)

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
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.filePath)
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
            let size = attributes[.size] as? Int64 ?? 0

            // Get relative path
            let relativePath = String(fileURL.filePath.dropFirst(storageURL.filePath.count + 1))

            // Determine content type from file extension
            guard let contentType = FileStorageContentType.from(relativePath: relativePath) else {
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
    /// - macOS: Uses ICloudStatusChecker to get accurate download status
    /// - iOS: Forces metadata refresh via startDownloadingUbiquitousItem
    func enumerateICloudFiles() async throws -> [SyncFileState] {
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

            #if os(iOS)
            // iOS: Force refresh metadata from iCloud
            // On iOS, placeholder files may have cached timestamps that don't reflect
            // the actual iCloud state. startDownloadingUbiquitousItem forces iOS to
            // refresh metadata from iCloud.
            do {
                try fileManager.startDownloadingUbiquitousItem(at: fileURL)
                // Give it a moment to update metadata
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            } catch {
                logger.warning("Failed to refresh iCloud metadata for \(fileURL.lastPathComponent): \(error)")
                // Continue anyway with cached metadata
            }
            #endif

            // Get metadata
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.filePath)
            let modifiedAt = attributes[.modificationDate] as? Date ?? Date()
            let size = attributes[.size] as? Int64 ?? 0

            // Get relative path
            let relativePath = String(fileURL.filePath.dropFirst(containerURL.filePath.count + 1))

            // Determine content type from file extension
            guard let contentType = FileStorageContentType.from(relativePath: relativePath) else {
                // Skip files with unknown extensions
                continue
            }

            // Get download status (macOS only)
            var downloadStatus: SyncFileState.DownloadStatus? = nil
            #if os(macOS)
            do {
                let iCloudStatus = try await ICloudStatusChecker.shared.checkStatus(for: fileURL)
                downloadStatus = mapToDownloadStatus(iCloudStatus)
            } catch {
                logger.warning("Failed to check iCloud status for \(fileURL.lastPathComponent): \(error)")
                // Continue without download status
            }
            #endif

            files.append(SyncFileState(
                fileID: fileID,
                relativePath: relativePath,
                contentType: contentType,
                modifiedAt: modifiedAt,
                size: size,
                downloadStatus: downloadStatus
            ))
        }

        return files
    }

    /// Map ICloudFileStatus to SyncFileState.DownloadStatus
    #if os(macOS)
    private func mapToDownloadStatus(_ status: ICloudFileStatus) -> SyncFileState.DownloadStatus? {
        switch status {
            case .notDownloaded:
                return .notDownloaded
            case .outdated:
                return .downloaded
            case .downloaded:
                return .current
            default:
                // For other statuses (loading, uploading, downloading, conflict, error, local)
                // return nil as they're not relevant for DiffScan's purposes
                return nil
        }
    }
    #endif

    /// Enumerate all files that should exist based on CoreData entities
    func enumerateExpectedFiles() async -> [SyncFileState] {
        let context = PersistenceController.shared.newTaskContext()

        // All CoreData operations must run on the context's queue
        return await context.perform {
            var expectedFiles: [SyncFileState] = []

            // Fetch all File entities
            do {
                let fileRequest: NSFetchRequest<File> = File.fetchRequest()
                fileRequest.propertiesToFetch = ["id", "updatedAt"]
                let files = try context.fetch(fileRequest)
                for file in files {
                    guard let fileID = file.id?.uuidString,
                          let updatedAt = file.updatedAt else { continue }

                    let relativePath = FileStorageContentType.file.generateRelativePath(fileID: fileID)
                    expectedFiles.append(SyncFileState(
                        fileID: fileID,
                        relativePath: relativePath,
                        contentType: .file,
                        modifiedAt: updatedAt,
                        size: 0  // Size will be determined from filesystem
                    ))
                }
            } catch {
                self.logger.error("Failed to fetch File entities: \(error.localizedDescription)")
            }

            // Fetch all CollaborationFile entities
            do {
                let collabRequest: NSFetchRequest<CollaborationFile> = CollaborationFile.fetchRequest()
                collabRequest.propertiesToFetch = ["id", "updatedAt"]
                let collabFiles = try context.fetch(collabRequest)
                for collabFile in collabFiles {
                    guard let fileID = collabFile.id?.uuidString,
                          let updatedAt = collabFile.updatedAt else { continue }

                    let relativePath = FileStorageContentType.collaborationFile.generateRelativePath(fileID: fileID)
                    expectedFiles.append(SyncFileState(
                        fileID: fileID,
                        relativePath: relativePath,
                        contentType: .collaborationFile,
                        modifiedAt: updatedAt,
                        size: 0
                    ))
                }
            } catch {
                self.logger.error("Failed to fetch CollaborationFile entities: \(error.localizedDescription)")
            }

            // Fetch all FileCheckpoint entities
            do {
                let checkpointRequest: NSFetchRequest<FileCheckpoint> = FileCheckpoint.fetchRequest()
                checkpointRequest.propertiesToFetch = ["id", "updatedAt"]
                let checkpoints = try context.fetch(checkpointRequest)
                for checkpoint in checkpoints {
                    guard let fileID = checkpoint.id?.uuidString,
                          let timestamp = checkpoint.updatedAt else { continue }

                    let relativePath = FileStorageContentType.checkpoint.generateRelativePath(fileID: fileID)
                    expectedFiles.append(SyncFileState(
                        fileID: fileID,
                        relativePath: relativePath,
                        contentType: .checkpoint,
                        modifiedAt: timestamp,
                        size: 0
                    ))
                }
            } catch {
                self.logger.error("Failed to fetch FileCheckpoint entities: \(error.localizedDescription)")
            }

            // Fetch all MediaItem entities
            do {
                let mediaRequest: NSFetchRequest<MediaItem> = MediaItem.fetchRequest()
                mediaRequest.propertiesToFetch = ["id", "mimeType", "createdAt"]
                let mediaItems = try context.fetch(mediaRequest)
                for mediaItem in mediaItems {
                    guard let fileID = mediaItem.id,
                          let mimeType = mediaItem.mimeType,
                          let createdAt = mediaItem.createdAt else { continue }
                    let ext = FileStorageContentType.fileExtension(for: mimeType)
                    let contentType = FileStorageContentType.mediaItem(extension: ext)
                    let relativePath = contentType.generateRelativePath(fileID: fileID)
                    expectedFiles.append(SyncFileState(
                        fileID: fileID,
                        relativePath: relativePath,
                        contentType: contentType,
                        modifiedAt: createdAt,
                        size: 0
                    ))
                }
            } catch {
                self.logger.error("Failed to fetch MediaItem entities: \(error.localizedDescription)")
            }

            self.logger.info("Found \(expectedFiles.count) expected files from CoreData")
            return expectedFiles
        }
    }
}
