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
    var item: MediaItem

    var body: some View {
        MediaItemDetailContent(item: item)
            .navigationTitle(item.file?.name ?? item.collaborationFile?.name ?? String(localizable: .settingsMediasName))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

struct MediaItemDetailContent: View {
    var item: MediaItem

    @State private var data: Data?
    @State private var isLoading = false

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
                    Divider()
                    mediaInfoRow(
                        title: String(localizable: .mediasInfoLabelReferencedFrom),
                        value: item.file?.name
                            ?? item.collaborationFile?.name
                            ?? String(localizable: .generalUnknown)
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
