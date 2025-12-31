//
//  ICloudConflictResolver.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/30/25.
//

import Foundation
import Logging

/// Handles iCloud file conflict resolution for a specific file
///
/// When iCloud detects conflicts between local and cloud versions,
/// this resolver helps users choose which version to keep.
///
/// Usage:
/// ```swift
/// let resolver = ICloudConflictResolver(fileURL: fileURL)
/// let versions = try await resolver.getConflictVersions()
/// try await resolver.resolveConflict(keepingVersion: selectedVersion)
/// ```
public actor ICloudConflictResolver {
    // MARK: - Properties

    private let fileURL: URL
    private let logger = Logger(label: "ICloudConflictResolver")

    // MARK: - Initialization

    public init(fileURL: URL) {
        self.fileURL = fileURL
        logger.info("ICloudConflictResolver initialized for: \(fileURL.lastPathComponent)")
    }

    // MARK: - Public API

    /// Get all conflicting versions of the file
    /// - Returns: Array of file versions (current + conflicting versions)
    /// - Throws: ConflictError if unable to get versions
    public func getConflictVersions() throws -> [FileVersion] {
        logger.info("Getting conflict versions for: \(fileURL.lastPathComponent)")

        // Get current version
        guard let currentVersion = NSFileVersion.currentVersionOfItem(at: fileURL) else {
            throw ConflictError.noCurrentVersion
        }

        // Get conflicting versions
        let conflictingVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL) ?? []

        guard !conflictingVersions.isEmpty else {
            logger.warning("No conflicting versions found for: \(fileURL.lastPathComponent)")
            throw ConflictError.noConflicts
        }

        // Map to our FileVersion model
        var versions: [FileVersion] = []

        // Add current version
        versions.append(FileVersion(
            url: currentVersion.url,
            modificationDate: currentVersion.modificationDate ?? Date(),
            deviceName: currentVersion.localizedNameOfSavingComputer ?? "Unknown",
            isCurrent: true,
            nsFileVersion: currentVersion
        ))

        // Add conflicting versions
        for (index, version) in conflictingVersions.enumerated() {
            versions.append(FileVersion(
                url: version.url,
                modificationDate: version.modificationDate ?? Date(),
                deviceName: version.localizedNameOfSavingComputer ?? "Device \(index + 1)",
                isCurrent: false,
                nsFileVersion: version
            ))
        }

        logger.info("Found \(versions.count) versions (\(conflictingVersions.count) conflicts)")
        return versions
    }

    /// Resolve conflict by keeping the specified version
    /// - Parameter versionToKeep: The version to keep
    /// - Throws: ConflictError if resolution fails
    public func resolveConflict(keepingVersion versionToKeep: FileVersion) throws {
        logger.info("Resolving conflict for: \(fileURL.lastPathComponent), keeping version from \(versionToKeep.deviceName)")

        // Get all versions
        let versions = try getConflictVersions()

        // If keeping a conflicting version (not current), replace current with it
        if !versionToKeep.isCurrent {
            logger.info("Replacing current version with version from \(versionToKeep.deviceName)")

            // Replace current file with chosen version
            let chosenVersionURL = versionToKeep.nsFileVersion.url
            let chosenData = try Data(contentsOf: chosenVersionURL)

            var coordinationError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(
                writingItemAt: fileURL,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try chosenData.write(to: coordinatedURL, options: .atomic)
                } catch {
                    logger.error("Failed to write chosen version: \(error)")
                }
            }

            if let error = coordinationError {
                throw ConflictError.replaceFailed(error)
            }
        }

        // Mark all conflicting versions as resolved
        for version in versions {
            if !version.isCurrent {
                version.nsFileVersion.isResolved = true
                logger.debug("Marked version as resolved: \(version.deviceName)")
            }
        }

        // Remove other versions
        do {
            try NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
            logger.info("Successfully resolved conflict for: \(fileURL.lastPathComponent)")
        } catch {
            logger.error("Failed to remove other versions: \(error)")
            throw ConflictError.cleanupFailed(error)
        }
    }
}

// MARK: - Models

/// Represents a file version in a conflict
public struct FileVersion: Identifiable {
    public let id = UUID()
    public let url: URL
    public let modificationDate: Date
    public let deviceName: String
    public let isCurrent: Bool

    /// Internal NSFileVersion reference
    fileprivate let nsFileVersion: NSFileVersion

    public var displayName: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if isCurrent {
            return "Current Version - \(deviceName) (\(formatter.string(from: modificationDate)))"
        } else {
            return "\(deviceName) (\(formatter.string(from: modificationDate)))"
        }
    }
}

// MARK: - Errors

public enum ConflictError: LocalizedError {
    case noCurrentVersion
    case noConflicts
    case replaceFailed(Error)
    case cleanupFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .noCurrentVersion:
            return "No current version found"
        case .noConflicts:
            return "No conflicting versions found"
        case .replaceFailed(let error):
            return "Failed to replace file: \(error.localizedDescription)"
        case .cleanupFailed(let error):
            return "Failed to clean up versions: \(error.localizedDescription)"
        }
    }
}
