//
//  FolderSyncOptions.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/23/25.
//

import Foundation

/// Configuration options for folder synchronization and monitoring
struct FolderSyncOptions {
    /// Whether to automatically check iCloud status for files in this folder
    /// - Default: `true`
    var autoCheckICloudStatus: Bool

    /// Time interval for batching iCloud status checks (in seconds)
    ///
    /// Multiple file changes within this interval will be batched into a single
    /// status check operation to improve performance.
    /// - Default: `2.0` seconds
    var batchCheckInterval: TimeInterval

    /// Whether to recursively monitor subfolders
    /// - Default: `true`
    var recursive: Bool

    /// File extensions to monitor (empty array means monitor all files)
    /// - Default: `["excalidraw"]`
    var fileExtensions: [String]

    /// Whether to automatically download files when they're opened
    /// - Default: `true`
    var autoDownloadOnOpen: Bool

    /// Maximum number of concurrent file status checks
    /// - Default: `5`
    var maxConcurrentStatusChecks: Int

    // MARK: - Initializer

    init(
        autoCheckICloudStatus: Bool = true,
        batchCheckInterval: TimeInterval = 2.0,
        recursive: Bool = true,
        fileExtensions: [String] = ["excalidraw"],
        autoDownloadOnOpen: Bool = true,
        maxConcurrentStatusChecks: Int = 5
    ) {
        self.autoCheckICloudStatus = autoCheckICloudStatus
        self.batchCheckInterval = batchCheckInterval
        self.recursive = recursive
        self.fileExtensions = fileExtensions
        self.autoDownloadOnOpen = autoDownloadOnOpen
        self.maxConcurrentStatusChecks = maxConcurrentStatusChecks
    }
}

// MARK: - Presets

extension FolderSyncOptions {
    /// Default options for most use cases
    static let `default` = FolderSyncOptions()

    /// Options optimized for performance (less frequent checks)
    static let performance = FolderSyncOptions(
        batchCheckInterval: 5.0,
        maxConcurrentStatusChecks: 3
    )

    /// Options for local-only folders (no iCloud checks)
    static let localOnly = FolderSyncOptions(
        autoCheckICloudStatus: false
    )
}
