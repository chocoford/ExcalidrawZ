//
//  FileStatusBox.swift
//  ExcalidrawZ
//
//  Created by Claude on 12/23/25.
//

import SwiftUI
import Logging

/// A per-file ObservableObject that holds the current status of a file.
///
/// This design ensures that when a file's status changes, only the corresponding
/// UI row is refreshed, rather than the entire file list.
///
/// Usage in SwiftUI:
/// ```swift
/// struct FileItemView: View {
///     @ObservedObject var statusBox: FileStatusBox
///
///     var body: some View {
///         HStack {
///             Text(statusBox.url.lastPathComponent)
///             statusIcon
///         }
///     }
/// }
/// ```
@MainActor
final class FileStatusBox: ObservableObject, @MainActor Identifiable {
    private let logger = Logger(label: "FileStatusBox")
    /// The current status of this file
    @Published var status: FileStatus

    /// The file URL this box represents
    let url: URL
    
    var id: URL { url }
    
    /// Timestamp of last status update
    @Published var lastUpdated: Date

    init(url: URL, status: FileStatus = .loading) {
        self.url = url
        self.status = status
        self.lastUpdated = Date()
    }

    /// Update the status and refresh timestamp
    func updateStatus(_ newStatus: FileStatus) {
        guard status != newStatus else { return }
        // logger.info("status updated: \(newStatus)")
        status = newStatus
        lastUpdated = Date()
    }
}
