//
//  SyncStatusPopover.swift
//  ExcalidrawZ
//
//  Created by Claude on 2025/11/29.
//

import SwiftUI
import ChocofordUI

/// Sync status popover with MediaItems progress and detailed info
/// Displays as a rectangular card at bottom-trailing of ExcalidrawHomeView
struct SyncStatusPopover: View {
    // Observe syncState for reactive UI updates
    @ObservedObject private var syncState = FileStatusService.shared.syncState
    
    init() {}
    
    @State private var isPresented = false

    var body: some View {
        ZStack {
            if isPresented {
                content()
            }
        }
        .onChange(of: syncState.hasActiveSyncOperations, initial: true, throttle: 0.2, latest: true) { newVal in
            withAnimation(.smooth) {
                isPresented = newVal
            }
        }
    }
    
    @ViewBuilder
    private func content() -> some View {
        SyncStatusContentView()
            .padding(.vertical, 16)
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
    
}


struct SyncStatusContentView: View {
    @ObservedObject private var syncState: SyncState = FileStatusService.shared.syncState
    
    // Debounced syncing files count to avoid flickering when transitioning between files
    @State private var debouncedSyncingFilesCount = 0
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            statusIconView()
                .frame(width: 20)
            
            // Text content (headline + body)
            VStack(alignment: .leading, spacing: 2) {
                headlineText()
                    .font(.callout.weight(.medium))
                
                captionText()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Percentage or other trailing info
            ZStack {
                if let progress = syncState.overallProgress {
                    if #available(iOS 17.0, macOS 14.0, *) {
                        Text("\(Int(Double(progress.current) / Double(progress.total) * 100))%")
                            .contentTransition(.numericText(value: Double(progress.current) / Double(progress.total) * 100))
                            .animation(.smooth, value: Double(progress.current) / Double(progress.total) * 100)
                    } else {
                        Text("\(Int(Double(progress.current) / Double(progress.total) * 100))%")
                    }
                } else if let progress = syncState.mediaItemsDownloadProgress {
                    if #available(iOS 17.0, macOS 14.0, *) {
                        Text("\(Int(Double(progress.current) / Double(progress.total) * 100))%")
                            .contentTransition(.numericText(value: Double(progress.current) / Double(progress.total) * 100))
                            .animation(.smooth, value: Double(progress.current) / Double(progress.total) * 100)
                    } else {
                        Text("\(Int(Double(progress.current) / Double(progress.total) * 100))%")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .onChange(of: syncState.syncingFilesCount, throttle: 0.5, latest: true) { newCount in
            // Only update if count is stable (> 0) or clearly done (stayed 0)
            debouncedSyncingFilesCount = newCount
        }
    }
    
    // MARK: - Computed Properties
    
    /// Headline text (main progress message)
    @ViewBuilder
    private func headlineText() -> some View {
        if let progress = syncState.overallProgress {
            if #available(iOS 17.0, macOS 14.0, *) {
                Text("Syncing \(progress.current) of \(progress.total) files")
                    .contentTransition(.numericText(value: Double(progress.current)))
                    .animation(.smooth, value: progress.current)
            } else {
                Text("Syncing \(progress.current) of \(progress.total) files")
            }
        } else if let progress = syncState.mediaItemsDownloadProgress {
            if #available(iOS 17.0, macOS 14.0, *) {
                Text("Downloading \(progress.current) of \(progress.total) media files")
                    .contentTransition(.numericText(value: Double(progress.current)))
                    .animation(.smooth, value: progress.current)
            } else {
                Text("Downloading \(progress.current) of \(progress.total) media files")
            }
        } else if let message = syncState.syncProgressMessage {
            Text(message)
        } else {
            Text("Preparing...")
        }
    }
    
    /// Caption text (detail/queue info)
    @ViewBuilder
    private func captionText() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            Text(
                "\(debouncedSyncingFilesCount) file\(debouncedSyncingFilesCount > 1 ? "s" : "") in queue"
            )
            .contentTransition(.numericText(value: Double(debouncedSyncingFilesCount)))
        } else {
            Text(
                "\(debouncedSyncingFilesCount) file\(debouncedSyncingFilesCount > 1 ? "s" : "") in queue"
            )
        }
    }
    

    /// Status icon view
    @ViewBuilder
    private func statusIconView() -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            Image(systemSymbol: .arrowTrianglehead2ClockwiseRotate90)
                .symbolEffect(.rotate, isActive: true)
        } else {
            Image(systemSymbol: .arrowTriangle2Circlepath)
        }
    }
}

