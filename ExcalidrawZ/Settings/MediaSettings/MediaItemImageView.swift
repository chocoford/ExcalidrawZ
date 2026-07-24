//
//  MediaItemImageView.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/13.
//

import SwiftUI
import CoreData

import ChocofordUI

struct MediaItemImageView: View {
    var item: MediaItem

    @State private var thumbnail: PlatformImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(platformImage: thumbnail)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: item.objectID) {
            thumbnail = nil
            let loadedThumbnail = await MediaItemThumbnailCoordinator.shared.thumbnail(for: item)
            guard !Task.isCancelled else { return }
            thumbnail = loadedThumbnail
        }
    }
}

struct MediaItemGridCell: View {
    var item: MediaItem
    var isSelected: Bool

    var body: some View {
        Color.gray.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                MediaItemImageView(item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
