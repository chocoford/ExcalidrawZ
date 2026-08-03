//
//  CloudStorageDocumentSyncIndicator.swift
//  ExcalidrawZ
//

import SwiftUI

@MainActor
struct CloudStorageDocumentSyncIndicator: View {
    enum Presentation {
        case iconOnly
        case canvas
    }

    @ObservedObject private var documentStore = CloudStorageDocumentStore.shared

    let reference: CloudStorageDocumentReference
    var presentation: Presentation = .iconOnly

    private var state: CloudStorageDocumentSyncState {
        documentStore.syncState(for: reference)
    }

    @ViewBuilder
    var body: some View {
        if state.isVisiblyPresented {
            visibleContent
                .foregroundStyle(state.tint)
                .help(state.displayText)
                .accessibilityLabel(state.displayText)
                .animation(.smooth(duration: 0.22), value: state)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var visibleContent: some View {
        switch presentation {
            case .iconOnly:
                statusIcon
                    .frame(width: 16, height: 16)

            case .canvas:
                HStack(spacing: state.showsExpandedStatus ? 7 : 0) {
                    statusIcon
                        .frame(width: 20, height: 20)

                    if state.showsExpandedStatus {
                        Text(state.displayText)
                            .font(.callout)
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background {
                    if #available(macOS 26.0, iOS 26.0, *) {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular, in: Capsule())
                    } else {
                        Capsule()
                            .fill(.regularMaterial)
                    }
                }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
            case .checking, .downloading(progress: nil), .uploading(progress: nil), .processing:
                ProgressView()
                    .controlSize(.mini)

            case .downloading(let progress?), .uploading(let progress?):
                ProgressView(value: progress)
                    .controlSize(.mini)

            default:
                if let symbolName = state.symbolName {
                    Image(systemName: symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .apply { content in
                            if #available(macOS 14.0, iOS 17.0, *) {
                                content.contentTransition(.symbolEffect(.replace))
                            } else {
                                content
                            }
                        }
                }
        }
    }
}

private extension CloudStorageDocumentSyncState {
    var isVisiblyPresented: Bool {
        if case .synced = self {
            return false
        }
        return true
    }

    var showsExpandedStatus: Bool {
        switch self {
            case .local, .synced:
                false
            case .queued, .checking, .downloading, .uploading,
                 .processing, .conflict, .failed:
                true
        }
    }

    var symbolName: String? {
        switch self {
            case .local:
                "externaldrive.fill"
            case .queued:
                "icloud.and.arrow.down"
            case .checking:
                "arrow.triangle.2.circlepath"
            case .downloading:
                "arrow.down.circle.fill"
            case .uploading:
                "arrow.up.circle.fill"
            case .synced:
                nil
            case .processing:
                "clock.arrow.circlepath"
            case .conflict:
                "exclamationmark.triangle.fill"
            case .failed:
                "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
            case .synced:
                .green
            case .conflict:
                .orange
            case .failed:
                .red
            case .downloading:
                .blue
            case .uploading:
                .indigo
            case .local, .queued, .checking, .processing:
                .secondary
        }
    }

    var displayText: String {
        switch self {
            case .local:
                String(
                    localized: "cloudStorageStatusLocal",
                    defaultValue: "Saved locally"
                )
            case .queued:
                String(
                    localized: "cloudStorageStatusQueued",
                    defaultValue: "Waiting to sync…"
                )
            case .checking:
                String(
                    localized: "cloudStorageStatusChecking",
                    defaultValue: "Checking cloud status…"
                )
            case .downloading(let progress):
                if let progress {
                    String(
                        localizable: .fileStatusDescriptionDownloading(
                            progress.formatted(.percent.precision(.fractionLength(0)))
                        )
                    )
                } else {
                    String(
                        localized: "cloudStorageStatusDownloading",
                        defaultValue: "Downloading…"
                    )
                }
            case .uploading:
                String(localizable: .fileStatusDescriptionUploading)
            case .synced:
                String(localizable: .fileStatusDescriptionSynced)
            case .processing:
                String(
                    localized: "cloudStorageStatusProcessing",
                    defaultValue: "Processing in cloud…"
                )
            case .conflict:
                String(localizable: .fileStatusDescriptionConflict)
            case .failed(_, let message):
                String(localizable: .fileStatusDescriptionError(message))
        }
    }
}
