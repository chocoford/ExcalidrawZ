//
//  FileCheckpointRowView.swift
//  ExcalidrawZ
//
//  Created by Dove Zachary on 2023/8/6.
//

import SwiftUI
import ChocofordUI
import SFSafeSymbols

struct FileCheckpointRowView<Checkpoint: FileCheckpointRepresentable>: View {
    @Environment(\.containerHorizontalSizeClass) private var containerHorizontalSizeClass

    @Environment(\.colorScheme) var colorScheme
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @EnvironmentObject var fileState: FileState
    
    var checkpoint: Checkpoint
    
    @State private var file: ExcalidrawFile?
    @State private var fileSize: Int = 0
    
    var body: some View {
        content()
            .watch(value: checkpoint) { newValue in
                Task {
                    do {
                        let content = try await PersistenceController.shared.checkpointRepository.loadCheckpointContent(
                            checkpointObjectID: newValue.objectID
                        )
                        let file = try? JSONDecoder().decode(ExcalidrawFile.self, from: content)
                        await MainActor.run {
                            self.fileSize = content.count
                            self.file = file
                        }
                    } catch {
                        print(error)
                    }
                }
            }
    }
    
    @MainActor @ViewBuilder
    private func content() -> some View {
#if os(iOS)
            NavigationLink {
                FileCheckpointDetailView(checkpoint: checkpoint)
            } label: {
                label()
            }
#elseif os(macOS)
            Popover(arrowEdge: .trailing) {
                FileCheckpointDetailView(checkpoint: checkpoint)
            } label: {
                label()
            }
            .buttonStyle(
                ExcalidrawZSidebarRowButtonStyle(isSelected: false, isMultiSelected: false)
            )
//            .buttonStyle(ListButtonStyle())
#endif
    }
    
    @MainActor @ViewBuilder
    private func label() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text((checkpoint.filename ?? ""))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                // AI-source badge (user-source rows show no badge — they're
                // the default and a "User" pill on every row would just be
                // visual noise).
                sourceBadge
            }

            // Git-style description, only when present. AI fills this on
            // `.aiPost` rows; user rows are nil unless the user explicitly
            // edits one (TBD UI). Allow up to 2 lines so the AI's summary
            // doesn't get clipped to a single line.
            if let description = checkpoint.historyDescription, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    if let file {
                        if #available(macOS 13.0, iOS 16.0, *) {
                            Text(.localizable(.checkpointsElementsDescription(file.elements.count)))
                        } else {
                            Text(file.elements.count.formatted())
                        }
                    }
                    Text(" · ")

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
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    /// Capsule badge for AI-authored checkpoints. We collapse `.aiPre` /
    /// `.aiPost` into one user-facing "AI" label — the pre/post split is
    /// internal infrastructure for revert (only `.aiPost` actually
    /// reaches this UI; `.aiPre` rows are filtered out by
    /// `FileCheckpointListView`).
    @ViewBuilder
    private var sourceBadge: some View {
        if checkpoint.isAIGenerated {
            BadgeLabel(
                text: "AI",
                icon: .sparkles,
                tint: .accentColor
            )
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


#if DEBUG
#Preview {
    FileCheckpointRowView(checkpoint: FileCheckpoint.preview)
        .environmentObject(FileState())
}
#endif
