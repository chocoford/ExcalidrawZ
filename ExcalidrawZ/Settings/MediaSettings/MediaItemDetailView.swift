//
//  MediaItemDetailView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/13.
//

import SwiftUI
import CoreData

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct MediaItemDetailView: View {
    @ObservedObject var item: MediaItem

    var body: some View {
        MediaItemDetailContent(item: item)
            .navigationTitle(item.file?.name ?? item.collaborationFile?.name ?? String(localizable: .settingsMediasName))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

struct MediaItemDetailContent: View {
    @ObservedObject var item: MediaItem

    @Environment(\.alertToast) private var alertToast

    @State private var data: Data?
    @State private var isLoading = false
    @State private var isDeleteReferencedFileConfirmationPresented = false
    @State private var isDeletingReferencedFile = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                preview
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contextMenu {
                        if let data {
                            Button {
                                copyImage(data)
                            } label: {
                                Text(localizable: .generalButtonCopy)
                            }
                        }
                    }

                referencedFromSection

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    mediaInfoRow(title: "ID", value: item.id ?? String(localizable: .generalUnknown))
                    Divider()
                    mediaInfoRow(
                        title: String(localizable: .mediasInfoLabelCreatedAt),
                        value: item.createdAt?.formatted() ?? String(localizable: .generalUnknown)
                    )
                    Divider()
                    mediaInfoRow(
                        title: String(localizable: .mediasInfoLabelFileSize),
                        value: data?.count.formatted(.byteCount(style: .file)) ?? String(localizable: .generalUnknown)
                    )
                    if let mimeType = item.mimeType, !mimeType.isEmpty {
                        Divider()
                        mediaInfoRow(title: "MIME", value: mimeType)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .task(id: item.objectID) {
            await loadData()
        }
        .confirmationDialog(
            String(localizable: .sidebarFileRowDeletePermanentlyAlertTitle(referencedFileName)),
            isPresented: $isDeleteReferencedFileConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                deleteReferencedFile()
            } label: {
                Text(.localizable(.sidebarFileRowDeletePermanentlyAlertButtonConfirm))
            }
        } message: {
            Text(.localizable(.generalCannotUndoMessage))
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let data {
            DataImage(data: data, thumbnailSize: nil)
                .scaledToFit()
        } else if isLoading {
            ProgressView()
        } else {
            Rectangle()
                .fill(.secondary.opacity(0.25))
        }
    }

    @ViewBuilder
    private func mediaInfoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var referencedFromSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizable: .mediasInfoLabelReferencedFrom)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(referencedFileName)
                        .font(.body)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    referencedFileStatusLabel
                }

                Spacer(minLength: 0)

#if os(macOS)
                if referencedFileObjectID != nil {
                    Button {
                        openReferencedFile()
                    } label: {
                        Image(systemSymbol: .arrowRightCircleFill)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isDeletingReferencedFile)
                    .help(.localizable(.generalButtonOpen))
                }

                if referencedFileDeletionTarget != nil {
                    Button {
                        isDeleteReferencedFileConfirmationPresented = true
                    } label: {
                        if isDeletingReferencedFile {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemSymbol: .trash)
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .disabled(isDeletingReferencedFile)
                    .help(.localizable(.sidebarFileRowContextMenuDeletePermanently))
                }
#endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var referencedFileStatusLabel: some View {
        if let isInTrash = referencedFileIsInTrash {
            Label {
                Text(
                    localizable: isInTrash
                        ? .settingsMediaReferenceStatusInTrash
                        : .settingsMediaReferenceStatusAvailable
                )
            } icon: {
                Image(systemSymbol: isInTrash ? .trash : .checkmarkCircleFill)
            }
            .font(.caption)
            .foregroundStyle(isInTrash ? .orange : .green)
        } else {
            Label {
                Text(localizable: .settingsMediaReferenceStatusSourceUnavailable)
            } icon: {
                Image(systemSymbol: .questionmarkCircle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var referencedFileName: String {
        item.file?.name
            ?? item.collaborationFile?.name
            ?? String(localizable: .generalUnknown)
    }

    private var referencedFileObjectID: NSManagedObjectID? {
        item.file?.objectID ?? item.collaborationFile?.objectID
    }

    private var referencedFileIsInTrash: Bool? {
        if let file = item.file {
            return file.inTrash
        }
        if let file = item.collaborationFile {
            return file.inTrash
        }
        return nil
    }

    private enum ReferencedFileDeletionTarget {
        case file(NSManagedObjectID)
        case collaborationFile(NSManagedObjectID)
    }

    private var referencedFileDeletionTarget: ReferencedFileDeletionTarget? {
        if let file = item.file, file.inTrash {
            return .file(file.objectID)
        }
        if let file = item.collaborationFile, file.inTrash {
            return .collaborationFile(file.objectID)
        }
        return nil
    }

#if os(macOS)
    private func openReferencedFile() {
        guard let referencedFileObjectID,
              let url = try? entityURL(for: referencedFileObjectID) else {
            return
        }

        Task { @MainActor in
            guard ContentWindowActivationCoordinator.shared.activateLastWindow() else {
                NSWorkspace.shared.open(url)
                return
            }
            NotificationCenter.default.post(.shouldOpenExternalURL(url: url))
        }
    }
#endif

    private func deleteReferencedFile() {
        guard let target = referencedFileDeletionTarget else { return }

        isDeletingReferencedFile = true
        Task { @MainActor in
            do {
                switch target {
                case .file(let objectID):
                    try await PersistenceController.shared.fileRepository.delete(
                        fileObjectID: objectID,
                        forcePermanently: true,
                        save: true
                    )
                case .collaborationFile(let objectID):
                    try await PersistenceController.shared.collaborationFileRepository.delete(
                        collaborationFileObjectID: objectID,
                        save: true
                    )
                }
                isDeletingReferencedFile = false
            } catch {
                isDeletingReferencedFile = false
                alertToast(error)
            }
        }
    }

    private func loadData() async {
        isLoading = true
        let imageData = try? await item.loadData()
        await MainActor.run {
            self.data = imageData
            self.isLoading = false
        }
    }

    private func copyImage(_ data: Data) {
#if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
#elseif canImport(UIKit)
        if let image = UIImage(data: data) {
            UIPasteboard.general.setObjects([image])
        }
#endif
    }
}
