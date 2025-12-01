//
//  SyncStatusPopover.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/29.
//

import SwiftUI

/// Sync status popover with MediaItems progress and detailed info
/// Displays as a rectangular card at bottom-trailing of ExcalidrawHomeView
struct SyncStatusPopover: View {
    @ObservedObject private var syncStatus: SyncStatusState
    @EnvironmentObject private var fileState: FileState

    init() {
        self.syncStatus = .shared
    }

    var body: some View {
        if syncStatus.hasActiveSyncOperations || shouldShowFileStatus {
            VStack(alignment: .leading, spacing: 12) {
                // File-specific sync status
                if let fileID = getCurrentFileID(),
                   let status = getFileStatus(fileID),
                   status != .synced {
                    fileStatusRow(status: status)
                    if hasOtherItems {
                        Divider()
                    }
                }

                // MediaItems download progress
                if let progress = syncStatus.mediaItemsDownloadProgress {
                    mediaItemsProgressRow(current: progress.current, total: progress.total)
                    if hasOtherItemsAfterMedia {
                        Divider()
                    }
                }

                // Overall sync message
                if let message = syncStatus.syncProgressMessage {
                    overallSyncMessageRow(message: message)
                    if syncStatus.syncingFilesCount > 0 {
                        Divider()
                    }
                }

                // Active files syncing count
                if syncStatus.syncingFilesCount > 0 {
                    activeSyncCountRow(count: syncStatus.syncingFilesCount)
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
            .frame(minWidth: 240)
            .padding()
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    // MARK: - Sub Views

    @ViewBuilder
    private func fileStatusRow(status: FileSyncStatus) -> some View {
        HStack(spacing: 8) {
            statusIcon(for: status)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Current File")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(status.description)
                    .font(.callout)
                    .fontWeight(.medium)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func mediaItemsProgressRow(current: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Media Files")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Downloading \(current) of \(total)")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            Spacer()
            Text("\(Int(Double(current) / Double(total) * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func overallSyncMessageRow(message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 20)
            Text(message)
                .font(.callout)
                .fontWeight(.medium)
            Spacer()
        }
    }

    @ViewBuilder
    private func activeSyncCountRow(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 16))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync Queue")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(count) file\(count > 1 ? "s" : "") syncing")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            Spacer()
        }
    }

    // MARK: - Helper Properties

    private var hasOtherItems: Bool {
        syncStatus.mediaItemsDownloadProgress != nil ||
        syncStatus.syncProgressMessage != nil ||
        syncStatus.syncingFilesCount > 0
    }

    private var hasOtherItemsAfterMedia: Bool {
        syncStatus.syncProgressMessage != nil ||
        syncStatus.syncingFilesCount > 0
    }

    private var shouldShowFileStatus: Bool {
        guard let fileID = getCurrentFileID() else { return false }
        let status = syncStatus.getStatus(for: fileID)
        return status != .synced
    }

    // MARK: - Helper Methods

    private func getCurrentFileID() -> String? {
        switch fileState.currentActiveFile {
            case .file(let file):
                return file.id?.uuidString
            case .collaborationFile(let collabFile):
                return collabFile.id?.uuidString
            default:
                return nil
        }
    }

    private func getFileStatus(_ fileID: String) -> FileSyncStatus? {
        let status = syncStatus.getStatus(for: fileID)
        return status != .synced ? status : nil
    }

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
