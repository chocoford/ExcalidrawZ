//
//  SyncStatusIndicator.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/28.
//

import SwiftUI

/// Sync status indicator view that displays the current file's iCloud sync status
struct SyncStatusIndicator: View {
    @EnvironmentObject private var fileState: FileState
    @State private var fileStatus: FileStatus?

    var body: some View {
        if let activeFile = fileState.currentActiveFile,
           let syncStatus = fileStatus?.syncStatus,
           syncStatus != .synced {
            HStack(spacing: 4) {
                statusIcon(for: syncStatus)
                Text(syncStatus.description)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule().fill(.regularMaterial)
            }
            .padding()
            .bindFileStatus(for: activeFile, status: $fileStatus)
        }
    }

    // MARK: - Helper Methods
    
    @ViewBuilder
    private func statusIcon(for status: FileSyncStatus) -> some View {
        switch status {
            case .synced:
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(.green)
            case .uploading:
                ProgressView()
                    .controlSize(.small)
            case .downloading:
                ProgressView()
                    .controlSize(.small)
            case .needsUpload:
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.orange)
            case .needsDownload:
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.blue)
            case .queued:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            case .conflict:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            case .notAvailable:
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.secondary)
            case .error:
                Image(systemName: "xmark.icloud")
                    .foregroundStyle(.red)
        }
    }
}
