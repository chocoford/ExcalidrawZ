//
//  IndicatorOverlay.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/6/30.
//

import SwiftUI
import ChocofordUI

struct IndicatorOverlay: View {
    private static let iconSize: CGFloat = 16
    private static let iconFrame: CGFloat = 24
    private static let expandedContentWidth: CGFloat = 132

    @Bindable private var syncState: SyncState = FileStatusService.shared.syncState

    @State private var currentEvent: SyncIndicatorEvent?
    @State private var queuedEvents: [SyncIndicatorEvent] = []
    @State private var displayTask: Task<Void, Never>?
    @State private var latestSnapshot = SyncIndicatorSnapshot.idle
    @State private var lastSnapshot: SyncIndicatorSnapshot?

    private var buttonStyleSize: ModernButtonStyleModifier.Size {
#if os(iOS)
        .regular
#else
        .large
#endif
    }

    private var contentWidth: CGFloat {
        currentEvent == nil ? Self.iconFrame : Self.expandedContentWidth
    }

    private var buttonShape: ModernButtonStyleModifier.BorderShape {
        currentEvent == nil ? .circle : .capsule
    }

    private var currentSnapshot: SyncIndicatorSnapshot {
        let activeUploadCount = syncState.syncingFiles.filter {
            $0.status.syncStatus?.indicatorDirection == .upload
        }.count
        let activeDownloadCount = syncState.syncingFiles.filter {
            $0.status.syncStatus?.indicatorDirection == .download
        }.count
        let queuedUploadCount = syncState.queuedFiles.filter {
            $0.status.syncStatus?.indicatorDirection == .upload
        }.count
        let queuedDownloadCount = syncState.queuedFiles.filter {
            $0.status.syncStatus?.indicatorDirection == .download
        }.count

        return SyncIndicatorSnapshot(
            activeUploadCount: activeUploadCount,
            activeDownloadCount: activeDownloadCount,
            activeOtherCount: max(syncState.syncingFiles.count - activeUploadCount - activeDownloadCount, 0),
            queuedUploadCount: queuedUploadCount,
            queuedDownloadCount: queuedDownloadCount,
            queuedOtherCount: max(syncState.queuedFiles.count - queuedUploadCount - queuedDownloadCount, 0),
            failedCount: syncState.failedFiles.count,
            overallProgress: syncState.overallProgress.map {
                SyncIndicatorProgress(current: $0.current, total: $0.total)
            },
            mediaProgress: syncState.mediaItemsDownloadProgress.map {
                SyncIndicatorProgress(current: $0.current, total: $0.total)
            },
            message: syncState.syncProgressMessage
        )
    }

    var body: some View {
        Button {} label: {
            contentView(event: currentEvent)
                .modifier(
                    SyncIndicatorWidthFrame(
                        width: contentWidth,
                        height: Self.iconFrame,
                        alignment: currentEvent == nil ? .center : .leading
                    )
                )
                .clipped()
        }
        .modernButtonStyle(
            style: .glass,
            size: buttonStyleSize,
            shape: buttonShape
        )
        .foregroundStyle(.primary)
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.32), value: contentWidth)
        .animation(.smooth(duration: 0.22), value: currentEvent?.presentationID ?? "idle")
        .watch(value: currentSnapshot, initial: true) { _, newValue in
            handleSnapshotChange(newValue)
        }
        .onDisappear {
            displayTask?.cancel()
            displayTask = nil
            queuedEvents.removeAll()
        }
    }

    private func contentView(event: SyncIndicatorEvent?) -> some View {
        HStack(spacing: event == nil ? 0 : 8) {
            eventIcon(event ?? .idle)
                .font(.system(size: Self.iconSize, weight: .semibold))
                .frame(width: Self.iconFrame, height: Self.iconFrame)

            if let event {
                Text(event.headline)
                    .font(.body)
                    .lineLimit(1)
                    .id(event.presentationID)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: event == nil ? .center : .leading)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func eventIcon(_ event: SyncIndicatorEvent) -> some View {
        let imageName = iconName(for: event)
        return Image(systemName: imageName)
            .foregroundStyle(iconColor(for: event))
            .symbolRenderingMode(.hierarchical)
            .apply { content in
                if #available(iOS 17.0, macOS 14.0, *) {
                    content.contentTransition(.symbolEffect(.replace))
                } else {
                    content
                }
            }
            .apply { content in
                if #available(iOS 18.0, macOS 15.0, *), event.kind == .syncing {
                    content.symbolEffect(.pulse, isActive: true)
                } else {
                    content
                }
            }
    }

    private func iconName(for event: SyncIndicatorEvent) -> String {
        switch event.kind {
            case .idle, .completed:
                return "checkmark.icloud.fill"
            case .queued:
                return "clock.arrow.circlepath"
            case .syncing:
                switch event.direction {
                    case .upload?:
                        return "icloud.and.arrow.up.fill"
                    case .download?:
                        return "icloud.and.arrow.down.fill"
                    case .mixed?, nil:
                        return "arrow.triangle.2.circlepath"
                }
            case .failed:
                return "exclamationmark.triangle.fill"
        }
    }

    private func iconColor(for event: SyncIndicatorEvent) -> Color {
        switch event.kind {
            case .idle, .completed:
                return .green
            case .failed:
                return .orange
            case .queued, .syncing:
                return .secondary
        }
    }

    private func handleSnapshotChange(_ snapshot: SyncIndicatorSnapshot) {
        latestSnapshot = snapshot

        defer {
            lastSnapshot = snapshot
        }

        if snapshot.displayKind == .idle {
            if lastSnapshot?.displayKind.isActive == true {
                enqueue(.completed)
            }
            return
        }

        enqueue(SyncIndicatorEvent(snapshot: snapshot))
    }

    private func enqueue(_ event: SyncIndicatorEvent) {
        if currentEvent?.presentationID == event.presentationID {
            withAnimation(.smooth(duration: 0.2)) {
                currentEvent = event
            }
            return
        }

        if let lastIndex = queuedEvents.indices.last,
           queuedEvents[lastIndex].presentationID == event.presentationID {
            queuedEvents[lastIndex] = event
        } else {
            queuedEvents.append(event)
        }

        processQueueIfNeeded()
    }

    private func processQueueIfNeeded() {
        guard displayTask == nil else { return }

        displayTask = Task { @MainActor in
            while !queuedEvents.isEmpty {
                let event = queuedEvents.removeFirst()

                withAnimation(.smooth(duration: 0.24)) {
                    currentEvent = event
                }

                do {
                    try await Task.sleep(nanoseconds: event.minimumDisplayDuration)
                } catch {
                    displayTask = nil
                    return
                }
            }

            if latestSnapshot.displayKind == .idle {
                withAnimation(.smooth(duration: 0.24)) {
                    currentEvent = nil
                }
            } else {
                withAnimation(.smooth(duration: 0.2)) {
                    currentEvent = SyncIndicatorEvent(snapshot: latestSnapshot)
                }
            }

            displayTask = nil
            if !queuedEvents.isEmpty {
                processQueueIfNeeded()
            }
        }
    }
}

private struct SyncIndicatorWidthFrame: AnimatableModifier {
    var width: CGFloat
    let height: CGFloat
    let alignment: Alignment

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height, alignment: alignment)
    }
}

private struct SyncIndicatorProgress: Equatable {
    let current: Int
    let total: Int
}

private struct SyncIndicatorSnapshot: Equatable {
    static let idle = SyncIndicatorSnapshot(
        activeUploadCount: 0,
        activeDownloadCount: 0,
        activeOtherCount: 0,
        queuedUploadCount: 0,
        queuedDownloadCount: 0,
        queuedOtherCount: 0,
        failedCount: 0,
        overallProgress: nil,
        mediaProgress: nil,
        message: nil
    )

    let activeUploadCount: Int
    let activeDownloadCount: Int
    let activeOtherCount: Int
    let queuedUploadCount: Int
    let queuedDownloadCount: Int
    let queuedOtherCount: Int
    let failedCount: Int
    let overallProgress: SyncIndicatorProgress?
    let mediaProgress: SyncIndicatorProgress?
    let message: String?

    var activeCount: Int {
        activeUploadCount + activeDownloadCount + activeOtherCount
    }

    var queuedCount: Int {
        queuedUploadCount + queuedDownloadCount + queuedOtherCount
    }

    var direction: SyncIndicatorDirection? {
        let uploadCount = activeUploadCount + queuedUploadCount
        let downloadCount = activeDownloadCount + queuedDownloadCount

        if uploadCount > 0, downloadCount == 0 {
            return .upload
        }

        if downloadCount > 0, uploadCount == 0 {
            return .download
        }

        if uploadCount > 0 || downloadCount > 0 || activeOtherCount > 0 || queuedOtherCount > 0 {
            return .mixed
        }

        if mediaProgress != nil {
            return .download
        }

        if overallProgress != nil || message != nil {
            return .mixed
        }

        return nil
    }

    var displayKind: SyncIndicatorDisplayKind {
        if failedCount > 0 {
            return .failed
        }

        if activeCount > 0 ||
            overallProgress != nil ||
            mediaProgress != nil ||
            message != nil {
            return .syncing
        }

        if queuedCount > 0 {
            return .queued
        }

        return .idle
    }

    var detail: String {
        var parts: [String] = []

        if activeUploadCount > 0 {
            parts.append("upload \(activeUploadCount)")
        }

        if activeDownloadCount > 0 {
            parts.append("sync \(activeDownloadCount)")
        }

        if activeOtherCount > 0 {
            parts.append("active \(activeOtherCount)")
        }

        if queuedUploadCount > 0 {
            parts.append("queued upload \(queuedUploadCount)")
        }

        if queuedDownloadCount > 0 {
            parts.append("queued sync \(queuedDownloadCount)")
        }

        if queuedOtherCount > 0 {
            parts.append("queued \(queuedOtherCount)")
        }

        if failedCount > 0 {
            parts.append("failed \(failedCount)")
        }

        if let overallProgress {
            parts.append("overall \(overallProgress.current)/\(overallProgress.total)")
        }

        if let mediaProgress {
            parts.append("media \(mediaProgress.current)/\(mediaProgress.total)")
        }

        return parts.isEmpty ? "idle" : parts.joined(separator: " / ")
    }
}

private enum SyncIndicatorDisplayKind: Equatable {
    case idle
    case queued
    case syncing
    case completed
    case failed

    var isActive: Bool {
        switch self {
            case .queued, .syncing, .failed:
                return true
            case .idle, .completed:
                return false
        }
    }
}

private enum SyncIndicatorDirection: Equatable {
    case upload
    case download
    case mixed
}

private struct SyncIndicatorEvent: Equatable {
    let kind: SyncIndicatorDisplayKind
    let direction: SyncIndicatorDirection?
    let headline: String
    let detail: String
    let message: String?
    let minimumDisplayDuration: UInt64

    static let completed = SyncIndicatorEvent(
        kind: .completed,
        direction: nil,
        headline: "Synced",
        detail: "up to date",
        message: nil,
        minimumDisplayDuration: 1_100_000_000
    )

    static let idle = SyncIndicatorEvent(
        kind: .idle,
        direction: nil,
        headline: "",
        detail: "idle",
        message: nil,
        minimumDisplayDuration: 0
    )

    var presentationID: String {
        "\(kind)-\(direction.map(String.init(describing:)) ?? "none")"
    }

    init(
        kind: SyncIndicatorDisplayKind,
        direction: SyncIndicatorDirection?,
        headline: String,
        detail: String,
        message: String?,
        minimumDisplayDuration: UInt64
    ) {
        self.kind = kind
        self.direction = direction
        self.headline = headline
        self.detail = detail
        self.message = message
        self.minimumDisplayDuration = minimumDisplayDuration
    }

    init(snapshot: SyncIndicatorSnapshot) {
        let snapshotDirection = snapshot.direction

        switch snapshot.displayKind {
            case .queued:
                kind = .queued
                direction = snapshotDirection
                switch snapshotDirection {
                    case .upload?:
                        headline = "Upload queued"
                    case .download?:
                        headline = "Sync queued"
                    case .mixed?, nil:
                        headline = "Sync queued"
                }
                minimumDisplayDuration = 850_000_000

            case .syncing:
                kind = .syncing
                direction = snapshotDirection
                switch snapshotDirection {
                    case .upload?:
                        headline = "Uploading"
                    case .download?:
                        headline = "Syncing"
                    case .mixed?, nil:
                        headline = "Syncing"
                }
                minimumDisplayDuration = 1_000_000_000

            case .failed:
                kind = .failed
                direction = nil
                headline = "Sync error"
                minimumDisplayDuration = 1_800_000_000

            case .idle, .completed:
                kind = .completed
                direction = nil
                headline = "Synced"
                minimumDisplayDuration = 1_100_000_000
        }

        if let message = snapshot.message, !message.isEmpty {
            self.detail = "\(snapshot.detail) / \(message)"
        } else {
            self.detail = snapshot.detail
        }
        self.message = snapshot.message
    }
}

private extension FileSyncStatus {
    var indicatorDirection: SyncIndicatorDirection? {
        switch self {
            case .uploading, .needsUpload:
                return .upload
            case .downloading, .needsDownload:
                return .download
            case .queued(let operation):
                switch operation {
                    case .upload:
                        return .upload
                    case .download:
                        return .download
                    case .delete, .conflictResolution:
                        return .mixed
                }
            case .synced, .conflict, .notAvailable, .error:
                return nil
        }
    }
}
