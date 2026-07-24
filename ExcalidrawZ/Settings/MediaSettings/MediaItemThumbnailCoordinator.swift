//
//  MediaItemThumbnailCoordinator.swift
//  ExcalidrawZ
//
//  Created by Codex on 2026/07/20.
//

import CoreData
import ImageIO
import SwiftUI

private final class MediaItemThumbnailCache: NSCache<NSString, PlatformImage> {
    static let shared = MediaItemThumbnailCache()

    private override init() {
        super.init()
        countLimit = 300
        totalCostLimit = 96 * 1024 * 1024
    }
}

@MainActor
final class MediaItemThumbnailCoordinator {
    static let shared = MediaItemThumbnailCoordinator()

    private struct SendableThumbnail: @unchecked Sendable {
        let image: PlatformImage?
    }

    private let cache = MediaItemThumbnailCache.shared
    private let maxPixelDimension: CGFloat = 440
    private var inFlightTasks: [String: Task<PlatformImage?, Never>] = [:]

    private init() {}

    func thumbnail(for item: MediaItem) async -> PlatformImage? {
        let key = item.objectID.uriRepresentation().absoluteString
        let cacheKey = key as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        if let task = inFlightTasks[key] {
            return await task.value
        }

        let maxPixelDimension = maxPixelDimension
        let task = Task<PlatformImage?, Never> {
            let data: Data
            do {
                data = try await item.loadLocallyCachedData()
            } catch {
                guard let loadedData = try? await item.loadData() else {
                    return nil
                }
                data = loadedData
            }

            let result = await Task.detached(priority: .utility) {
                SendableThumbnail(
                    image: Self.makeThumbnail(
                        from: data,
                        maxPixelDimension: maxPixelDimension
                    )
                )
            }.value

            if let image = result.image {
                let cost = Self.estimatedMemoryCost(of: image)
                cache.setObject(image, forKey: cacheKey, cost: cost)
            }
            return result.image
        }

        inFlightTasks[key] = task
        let image = await task.value
        inFlightTasks[key] = nil
        return image
    }

    nonisolated private static func makeThumbnail(
        from data: Data,
        maxPixelDimension: CGFloat
    ) -> PlatformImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension),
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary

            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
#if os(macOS)
                return NSImage(cgImage: thumbnail, size: .zero)
#else
                return UIImage(cgImage: thumbnail)
#endif
            }
        }

        // ImageIO does not rasterize SVG. Platform image decoding does on the
        // supported OS versions, then an aspect-matched target avoids stretching.
#if os(macOS)
        guard let sourceImage = NSImage(data: data) else { return nil }
#else
        guard let sourceImage = UIImage(data: data) else { return nil }
#endif
        let sourceSize = sourceImage.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return sourceImage
        }

        let scale = min(
            maxPixelDimension / sourceSize.width,
            maxPixelDimension / sourceSize.height
        )
        let targetSize = CGSize(
            width: max(1, sourceSize.width * scale),
            height: max(1, sourceSize.height * scale)
        )
        return sourceImage.preparingThumbnail(of: targetSize) ?? sourceImage
    }

    nonisolated private static func estimatedMemoryCost(of image: PlatformImage) -> Int {
#if os(macOS)
        let pixelSize = image.representations.reduce(CGSize.zero) { result, representation in
            CGSize(
                width: max(result.width, CGFloat(representation.pixelsWide)),
                height: max(result.height, CGFloat(representation.pixelsHigh))
            )
        }
        return max(1, Int(pixelSize.width * pixelSize.height * 4))
#else
        guard let cgImage = image.cgImage else { return 1 }
        return max(1, cgImage.bytesPerRow * cgImage.height)
#endif
    }
}
