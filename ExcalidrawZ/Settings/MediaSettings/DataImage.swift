//
//  DataImage.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/06/13.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct DataImage: View {
    var data: Data
    var thumbnailSize: CGSize?

    init(data: Data, thumbnailSize: CGSize? = CGSize(width: 300, height: 300)) {
        self.data = data
        self.thumbnailSize = thumbnailSize
    }

#if canImport(AppKit)
    @State private var platformImage: NSImage?
#elseif canImport(UIKit)
    @State private var platformImage: UIImage?
#endif

    var body: some View {
        ZStack {
            if let svgContent {
                FittedSVGPreviewView(svg: svgContent, padding: 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            } else if let platformImage {
#if canImport(AppKit)
                Image(nsImage: platformImage)
                    .resizable()
                    .scaledToFit()
#elseif canImport(UIKit)
                Image(uiImage: platformImage)
                    .resizable()
                    .scaledToFit()
#endif
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.4))
            }
        }
        .task(id: data) {
            guard svgContent == nil else {
                platformImage = nil
                return
            }
            loadImage(from: data, thumbnailSize: thumbnailSize)
        }
    }

    private var svgContent: String? {
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<svg") || trimmed.contains("<svg ") else {
            return nil
        }
        return string
    }

    private func loadImage(from data: Data, thumbnailSize: CGSize?) {
        Task.detached {
#if canImport(AppKit)
            let sourceImage = NSImage(data: data)
#elseif canImport(UIKit)
            let sourceImage = UIImage(data: data)
#endif
            let platformImage = if let thumbnailSize {
                sourceImage?.preparingThumbnail(of: thumbnailSize) ?? sourceImage
            } else {
                sourceImage
            }
            await MainActor.run {
                self.platformImage = platformImage
            }
        }
    }
}
