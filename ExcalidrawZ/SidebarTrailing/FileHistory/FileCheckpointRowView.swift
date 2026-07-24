//
//  FileCheckpointRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import Logging
import ChocofordUI
import SFSafeSymbols

private let fileCheckpointRowLogger = Logger(label: "FileCheckpointRowView")

struct FileCheckpointRowView<Checkpoint: FileCheckpointRepresentable>: View {
    var checkpoint: Checkpoint
    var presentsDetail = true
    
    @State private var file: ExcalidrawFile?
    @State private var fileSize: Int = 0
    
    var body: some View {
        content()
            .task(id: checkpointMetadataLoadID, priority: .background) {
                do {
                    let content = try await loadContent(for: checkpoint)
                    let file = try? JSONDecoder().decode(ExcalidrawFile.self, from: content)
                    await MainActor.run {
                        self.fileSize = content.count
                        self.file = file
                    }
                } catch {
                    fileCheckpointRowLogger.warning("Failed to load checkpoint metadata: \(error)")
                }
            }
    }

    private var checkpointMetadataLoadID: String {
        "\(checkpoint.objectID.uriRepresentation().absoluteString)-\(checkpoint.updatedAt?.timeIntervalSinceReferenceDate ?? 0)"
    }
    
    @ViewBuilder
    private func content() -> some View {
        if !presentsDetail {
            label()
        } else {
#if os(iOS)
            NavigationLink {
                FileCheckpointDetailView(checkpoint: checkpoint)
            } label: {
                label()
            }
            .buttonStyle(.plain)
#elseif os(macOS)
            Popover(arrowEdge: .trailing) {
                FileCheckpointDetailView(checkpoint: checkpoint)
            } label: {
                label()
            }
            .buttonStyle(.fileCheckpointRow)
#endif
        }
    }
    
    @ViewBuilder
    private func label() -> some View {
        HStack(alignment: .top, spacing: 10) {
            FileCheckpointPreview(checkpoint: checkpoint)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(checkpoint.checkpointDisplayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    // AI-source badge (user-source rows show no badge — they're
                    // the default and a "User" pill on every row would just be
                    // visual noise).
                    sourceBadge
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        if let file {
                            let elementCount = file.elements.filter { !$0.isDeleted }.count
                            if #available(macOS 13.0, iOS 16.0, *) {
                                Text(.localizable(.checkpointsElementsDescription(elementCount)))
                            } else {
                                Text(elementCount.formatted())
                            }
                            Text(" · ")
                        }

                        Text("\(fileSize.formatted(.byteCount(style: .file)))")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    Text(checkpoint.updatedAt?.formatted() ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private func loadContent(for checkpoint: Checkpoint) async throws -> Data {
        if let fileCheckpoint = checkpoint as? FileCheckpoint {
            return try await fileCheckpoint.loadContent()
        }

        guard let content = checkpoint.content else {
            throw EmptyCheckpointContentError()
        }
        return content
    }
    
    /// Capsule badge for AI-authored result checkpoints. `.aiPre` is
    /// visible in history as the revert anchor, but should read like a
    /// normal checkpoint rather than an AI-produced result.
    @ViewBuilder
    private var sourceBadge: some View {
        switch checkpoint.checkpointSource {
        case .aiPost:
            BadgeLabel(
                text: "AI",
                icon: .sparkles,
                tint: .accentColor
            )
        case .mcpPost:
            BadgeLabel(
                text: "MCP",
                icon: .sparkles,
                tint: .accentColor
            )
        case .restorePost:
            BadgeLabel(
                text: "Restore",
                icon: .arrowCounterclockwise,
                tint: .accentColor
            )
        case .user, .aiPre, .mcpPre:
            EmptyView()
        }
    }
}

private struct EmptyCheckpointContentError: Error {}

private enum FileCheckpointPreviewMetrics {
    static let size = CGSize(width: 82, height: 52)
    static let cornerRadius: CGFloat = 7
}

private struct FileCheckpointPreview<Checkpoint: FileCheckpointRepresentable>: View {
    @Environment(\.colorScheme) private var colorScheme

    let checkpoint: Checkpoint

    @State private var coverImage: Image?

    private let cache = FileItemPreviewCache.shared

    private var previewID: String {
        FileCoverCacheCoordinator.checkpointPreviewID(for: checkpoint)
    }

    var body: some View {
        ZStack {
            if let coverImage {
                previewImage(coverImage)
            } else if let cachedImage {
                previewImage(cachedImage)
            } else {
                RoundedRectangle(cornerRadius: FileCheckpointPreviewMetrics.cornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.10 : 0.07))
            }
        }
        .frame(
            width: FileCheckpointPreviewMetrics.size.width,
            height: FileCheckpointPreviewMetrics.size.height
        )
        .fixedSize()
        .clipped()
        .clipShape(RoundedRectangle(
            cornerRadius: FileCheckpointPreviewMetrics.cornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: FileCheckpointPreviewMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .onAppear {
            updateCoverFromCache()
        }
        .watch(value: colorScheme) { _ in
            updateCoverFromCache()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .filePreviewDidUpdate)
        ) { notification in
            guard let updatedPreviewID = notification.object as? String,
                  updatedPreviewID == previewID else { return }

            updateCoverFromCache(requestIfMissing: false)
        }
    }

    private func previewImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(
                width: FileCheckpointPreviewMetrics.size.width,
                height: FileCheckpointPreviewMetrics.size.height
            )
    }

    private var cachedImage: Image? {
        guard let image = cache.getPreviewCache(forID: previewID, colorScheme: colorScheme) else {
            return nil
        }
        return Image(platformImage: image)
    }

    private func updateCoverFromCache(requestIfMissing: Bool = true) {
        if let cachedImage {
            coverImage = cachedImage
        } else {
            coverImage = nil
            if requestIfMissing {
                FileCoverCacheCoordinator.shared.request(
                    checkpoint: checkpoint,
                    colorScheme: colorScheme,
                    priority: .background
                )
            }
        }
    }
}

/// Small capsule used by `FileCheckpointRowView` to surface AI vs user
/// source. Pulled into its own view so the row's body stays flat and so
/// the styling stays consistent if more sources get added later.
private struct BadgeLabel: View {
    let text: String
    let icon: SFSymbol
    let tint: Color
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemSymbol: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(tint)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.3), lineWidth: 0.5)
        )
    }
}

private struct FileCheckpointRowButtonStyle: PrimitiveButtonStyle {
    private var cornerRadius: CGFloat {
        if #available(macOS 26.0, iOS 26.0, *) {
            18
        } else {
            8
        }
    }
    
    func makeBody(configuration: Configuration) -> some View {
        PrimitiveButtonWrapper {
            configuration.trigger()
        } content: { isPressed in
            HStack(spacing: 0) {
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(isPressed ? 0.72 : 1)
        }
    }
}

private extension PrimitiveButtonStyle where Self == FileCheckpointRowButtonStyle {
    static var fileCheckpointRow: FileCheckpointRowButtonStyle {
        FileCheckpointRowButtonStyle()
    }
}


#if DEBUG
#Preview {
    FileCheckpointRowView(checkpoint: FileCheckpoint.preview)
        .environmentObject(FileState())
}
#endif
