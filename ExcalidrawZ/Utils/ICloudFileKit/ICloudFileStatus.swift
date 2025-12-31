//
//  ICloudFileStatus.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/30/25.
//

import Foundation

/// Represents the current state of a file, including iCloud sync status
public enum ICloudFileStatus: Equatable, Sendable {
    /// Initial state, status is being determined
    case loading

    /// Local file (not in iCloud Drive)
    case local

    /// File exists only in iCloud (☁️ placeholder, not downloaded)
    case notDownloaded

    /// File is currently being downloaded from iCloud
    /// - Parameter progress: Download progress (0.0 to 1.0), nil if unknown
    case downloading(progress: Double?)

    /// File has been downloaded from iCloud and is up-to-date
    case downloaded

    /// File has been downloaded but iCloud has a newer version (update available)
    case outdated

    /// File is currently being uploaded to iCloud
    case uploading

    /// File has unresolved version conflicts
    case conflict

    /// Error occurred while checking file status
    /// - Parameter message: Error description
    case error(String)

    #if os(iOS)
    /// Not a real status, only for iOS to represent current file is syncing
    case syncing
    #endif

    // MARK: - Helper Properties

    /// Whether the file is available for immediate reading
    public var isAvailable: Bool {
        switch self {
            case .local, .downloaded, .outdated:
                return true
            default:
                return false
        }
    }

    /// Whether the file is in iCloud Drive
    public var isICloudFile: Bool {
        switch self {
            case .local, .loading, .error:
                return false
            default:
                return true
        }
    }

    /// Whether an action is in progress
    public var isInProgress: Bool {
        switch self {
#if os(iOS)
            case .syncing:
                return true
#endif
            case .downloading, .uploading:
                return true
            default:
                return false
        }
    }

    /// Whether an update is available from iCloud
    public var needsUpdate: Bool {
        switch self {
            case .outdated:
                return true
            default:
                return false
        }
    }
}
