//
//  FileHomeFilesGrid.swift
//  ExcalidrawZ
//

import SwiftUI
import CoreData
import ChocofordUI

enum FileHomeGridDiagnosticStage: Equatable {
    case rectangles
    case metadata
    case cachedCovers
    case cardLayout
    case lockPreview
    case staticLockPreview
    case cardPresentation
    /// Full card interactions while retaining the cached-only cover diagnostic.
    case cardInteraction
    /// Full appearance and interactions, with only the cover pipeline replaced.
    case fullCachedCovers
    /// The cached-cover comparison with app hover tracking and animation removed.
    case fullCachedCoversNoHover
    /// Production covers and full interactions, with app hover tracking removed.
    case fullNoHover
    /// Restore hover tracking and shadows without their transition animation.
    case fullHoverNoAnimation
    case full

    /// Change this source value as card contents are restored one step at a time.
    static let current: Self = .full
}

struct FileHomeFilesGrid: View {
    @Environment(\.colorScheme) private var colorScheme

    let files: [FileState.ActiveFile]
    let itemWidth: CGFloat
    /// Invalidates the grid value when a source changes presentation metadata
    /// without changing any stable file identities.
    let contentRevision: Int
    let animatesChanges: Bool
    let diagnosticStage: FileHomeGridDiagnosticStage

    init(
        files: [FileState.ActiveFile],
        itemWidth: CGFloat,
        contentRevision: Int = 0,
        animatesChanges: Bool = true,
        diagnosticStage: FileHomeGridDiagnosticStage = .current
    ) {
        self.files = files
        self.itemWidth = itemWidth
        self.contentRevision = contentRevision
        self.animatesChanges = animatesChanges
        self.diagnosticStage = diagnosticStage
    }

    @ViewBuilder
    var body: some View {
        switch diagnosticStage {
            case .rectangles, .metadata, .cachedCovers:
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(files) { file in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(height: 180)
                            .overlay {
                                if diagnosticStage == .cachedCovers {
                                    VStack(spacing: 0) {
                                        diagnosticCachedCover(for: file)
                                            .frame(height: 120)
                                        Spacer(minLength: 0)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .overlay(alignment: .bottomLeading) {
                                if diagnosticStage != .rectangles {
                                    diagnosticMetadata(for: file)
                                        .padding(8)
                                }
                            }
                            .allowsHitTesting(false)
                    }
                }
            case .cardLayout, .lockPreview, .staticLockPreview:
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(files) { file in
                        diagnosticCardLayout(for: file)
                    }
                }
            case .cardPresentation:
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(files) { file in
                        FileHomeItemView(
                            file: file,
                            interactionMode: .presentationOnly,
                            coverMode: .cachedOnly
                        )
                        .id(file.fileHomeItemContentID)
                    }
                }
            case .cardInteraction, .fullCachedCovers, .fullCachedCoversNoHover, .fullNoHover, .fullHoverNoAnimation, .full:
                fullGrid
        }
    }

    /// Keep the card geometry and text shared while testing each cover layer.
    private func diagnosticCardLayout(for file: FileState.ActiveFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(1.0 / 0.46, contentMode: .fit)
                .overlay {
                    if diagnosticStage == .lockPreview {
                        Color.clear
                            .modifier(FileHomeItemLockPreviewModifier(
                                file: file,
                                iconSize: 34,
                                coverMode: .cachedOnly
                            ))
                    } else if diagnosticStage == .staticLockPreview {
                        Color.clear
                            .modifier(FileHomeItemStaticLockPreviewModifier(
                                file: file,
                                iconSize: 34
                            ))
                    } else {
                        diagnosticCachedCover(for: file)
                    }
                }
                .clipped()

            diagnosticMetadata(for: file)
                .padding(8)
        }
        .background(Color.secondary.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    private func diagnosticCachedCover(for file: FileState.ActiveFile) -> some View {
        CachedFileCover(file: file, colorScheme: colorScheme)
            .id(FileItemPreviewCache.cacheKey(forID: file.canonicalID, colorScheme: colorScheme))
    }

    private func diagnosticMetadata(for file: FileState.ActiveFile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.name ?? String(localizable: .generalUntitled))
                .font(.headline.weight(.semibold))
            Text(diagnosticModificationDate(for: file)?.formatted()
                 ?? String(localizable: .generalFileNeverModified))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private func diagnosticModificationDate(for file: FileState.ActiveFile) -> Date? {
        switch file {
            case .file(let file):
                file.updatedAt
            case .collaborationFile(let file):
                file.updatedAt
            case .cloudStorageFile(let reference):
                reference.lastKnownModifiedAt
            case .localFile, .temporaryFile:
                // This stage measures text layout without reading filesystem metadata.
                nil
        }
    }

    private var columns: [GridItem] {
        [
            .init(
                .adaptive(
                    minimum: itemWidth,
                    maximum: itemWidth * 2 - 0.1
                ),
                spacing: 20
            )
        ]
    }

    private var fullGrid: some View {
        LazyVGrid(
            columns: columns,
            spacing: 20
        ) {
            ForEach(files) { file in
                FileHomeItemView(
                    file: file,
                    selectionSiblings: files,
                    interactionMode: .gridDiagnosticMode,
                    coverMode: diagnosticStage == .cardInteraction
                        || diagnosticStage == .fullCachedCovers
                        || diagnosticStage == .fullCachedCoversNoHover
                        ? .cachedOnly : .standard
                )
                .id(file.fileHomeItemContentID)
            }
        }
        .animation(animatesChanges ? .smooth(duration: 0.22) : nil, value: files.map(\.id))
    }
}

extension FileState.ActiveFile {
    /// Remote metadata can change without changing a cloud document's stable
    /// identity. Include its presentation snapshot in the row identity so
    /// SwiftUI refreshes that row without treating the editor as a new file.
    var fileHomeItemContentID: String {
        switch self {
            case .cloudStorageFile(let reference):
                let modifiedAt = reference.lastKnownModifiedAt?
                    .timeIntervalSinceReferenceDate ?? 0
                return "\(id):\(reference.lastKnownName):\(modifiedAt)"
            default:
                return id
        }
    }
}
