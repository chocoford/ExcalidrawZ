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
    @EnvironmentObject private var statusService: FileStatusService
    @EnvironmentObject private var fileState: FileState
    @State private var fileStatus: FileStatus?

    init() {}

    var body: some View {
        if statusService.hasActiveSyncOperations {
            content()
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // File-specific sync status
            if let syncStatus = fileStatus?.syncStatus,
               syncStatus != .synced {
                fileStatusRow(status: syncStatus)
                if hasOtherItems {
                    Divider()
                }
            }

            // MediaItems download progress
            if let progress = statusService.mediaItemsDownloadProgress {
                mediaItemsProgressRow(current: progress.current, total: progress.total)
                if hasOtherItemsAfterMedia {
                    Divider()
                }
            }

            // Overall sync message
            if let message = statusService.syncProgressMessage {
                overallSyncMessageRow(message: message)
                if statusService.syncingFilesCount > 0 {
                    Divider()
                }
            }

            // Active files syncing count
            if statusService.syncingFilesCount > 0 {
                activeSyncCountRow(count: statusService.syncingFilesCount)
            }
        }
        .bindFileStatus(for: fileState.currentActiveFile, status: $fileStatus)
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            if #available(iOS 26.0, macOS 26.0, *) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.background)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            }
        }
        .padding(7)
        .transition(.move(edge: .trailing).combined(with: .opacity))
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
            ZStack {
                if #available(macOS 15.0, iOS 18.0, *) {
                    Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
                        .symbolEffect(.rotate, isActive: true)
                } else {
                    Image(systemSymbol: .arrowTriangle2Circlepath)
                }
            }
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
        statusService.mediaItemsDownloadProgress != nil ||
        statusService.syncProgressMessage != nil ||
        statusService.syncingFilesCount > 0
    }

    private var hasOtherItemsAfterMedia: Bool {
        statusService.syncProgressMessage != nil ||
        statusService.syncingFilesCount > 0
    }

    private var shouldShowFileStatus: Bool {
        guard let syncStatus = fileStatus?.syncStatus else { return false }
        return syncStatus != .synced
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
