//
//  ExcalidrawFileCover.swift
//  ExcalidrawZ
//
//  Created by Chocoford on 1/1/26.
//

import SwiftUI
import Foundation
import Combine
import ChocofordUI

#if canImport(UIKit)
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
typealias PlatformImage = NSImage
#endif

final class FileItemPreviewCache: NSCache<NSString, PlatformImage> {
    static let shared = FileItemPreviewCache()

#if os(iOS)
    private static let retainedCostLimit = 96 * 1024 * 1024
#else
    private static let retainedCostLimit = 192 * 1024 * 1024
#endif
    private static let retainedCountLimit = 240

    private struct RetainedPreview {
        let image: PlatformImage
        let cost: Int
    }

    private let retainedLock = NSLock()
    private var retainedPreviews: [String: RetainedPreview] = [:]
    private var retainedOrder: [String] = []
    private var retainedTotalCost = 0

    private override init() {
        super.init()
        countLimit = Self.retainedCountLimit
        totalCostLimit = Self.retainedCostLimit
    }
    
    static func cacheKey(forID id: String, colorScheme: ColorScheme) -> NSString {
        (id + (colorScheme == .light ? "_light" : "_dark")) as NSString
    }

    override func object(forKey key: NSString) -> PlatformImage? {
        if let image = super.object(forKey: key) {
            touchRetainedPreview(forKey: key)
            return image
        }

        guard let retainedPreview = retainedPreview(forKey: key) else {
            return nil
        }

        super.setObject(retainedPreview.image, forKey: key, cost: retainedPreview.cost)
        return retainedPreview.image
    }

    override func setObject(_ obj: PlatformImage, forKey key: NSString) {
        setObject(obj, forKey: key, cost: Self.estimatedMemoryCost(for: obj))
    }

    override func setObject(_ obj: PlatformImage, forKey key: NSString, cost g: Int) {
        let cost = max(1, g)
        super.setObject(obj, forKey: key, cost: cost)
        retainPreview(obj, forKey: key, cost: cost)
    }

    override func removeObject(forKey key: NSString) {
        super.removeObject(forKey: key)
        removeRetainedPreview(forKey: key)
    }

    override func removeAllObjects() {
        super.removeAllObjects()
        retainedLock.lock()
        retainedPreviews.removeAll()
        retainedOrder.removeAll()
        retainedTotalCost = 0
        retainedLock.unlock()
    }
    
    func getPreviewCache(forID id: String, colorScheme: ColorScheme) -> PlatformImage? {
        self.object(forKey: Self.cacheKey(forID: id, colorScheme: colorScheme))
    }
    
    func removePreviewCache(forID id: String, colorScheme: ColorScheme) {
        self.removeObject(forKey: Self.cacheKey(forID: id, colorScheme: colorScheme))
    }

    func removePreviewCache(forID id: String) {
        self.removePreviewCache(forID: id, colorScheme: .light)
        self.removePreviewCache(forID: id, colorScheme: .dark)
    }

    private func retainedPreview(forKey key: NSString) -> RetainedPreview? {
        let key = key as String
        retainedLock.lock()
        defer { retainedLock.unlock() }

        guard let preview = retainedPreviews[key] else {
            return nil
        }

        moveRetainedPreviewToEnd(forKey: key)
        return preview
    }

    private func retainPreview(
        _ image: PlatformImage,
        forKey key: NSString,
        cost: Int
    ) {
        let key = key as String
        retainedLock.lock()

        if let existingPreview = retainedPreviews[key] {
            retainedTotalCost -= existingPreview.cost
            retainedOrder.removeAll { $0 == key }
        }

        retainedPreviews[key] = RetainedPreview(image: image, cost: cost)
        retainedOrder.append(key)
        retainedTotalCost += cost

        trimRetainedPreviewsIfNeeded()
        retainedLock.unlock()
    }

    private func touchRetainedPreview(forKey key: NSString) {
        let key = key as String
        retainedLock.lock()
        if retainedPreviews[key] != nil {
            moveRetainedPreviewToEnd(forKey: key)
        }
        retainedLock.unlock()
    }

    private func removeRetainedPreview(forKey key: NSString) {
        let key = key as String
        retainedLock.lock()
        if let existingPreview = retainedPreviews.removeValue(forKey: key) {
            retainedTotalCost -= existingPreview.cost
        }
        retainedOrder.removeAll { $0 == key }
        retainedLock.unlock()
    }

    private func moveRetainedPreviewToEnd(forKey key: String) {
        guard retainedOrder.last != key else { return }
        retainedOrder.removeAll { $0 == key }
        retainedOrder.append(key)
    }

    private func trimRetainedPreviewsIfNeeded() {
        while retainedOrder.count > Self.retainedCountLimit
                || (retainedTotalCost > Self.retainedCostLimit && retainedOrder.count > 1) {
            let key = retainedOrder.removeFirst()
            if let preview = retainedPreviews.removeValue(forKey: key) {
                retainedTotalCost -= preview.cost
            }
            super.removeObject(forKey: key as NSString)
        }
    }

    private static func estimatedMemoryCost(for image: PlatformImage) -> Int {
#if canImport(UIKit)
        if let cgImage = image.cgImage {
            return max(1, cgImage.bytesPerRow * cgImage.height)
        }

        let scale = max(1, image.scale)
        return max(1, Int(image.size.width * scale * image.size.height * scale * 4))
#elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return max(1, cgImage.bytesPerRow * cgImage.height)
        }

        return max(1, Int(image.size.width * image.size.height * 4))
#endif
    }
}



struct ExcalidrawFileCover: View {
    @Environment(\.colorScheme) var colorScheme
    
    // Support two initialization modes
    fileprivate enum Source {
        case activeFile(FileState.ActiveFile)
        case excalidrawFile(ExcalidrawFile)
    }
    
    private let source: Source
    private let refreshToken: String?
    private let allowsGeneration: Bool
    private let generationPriority: FileCoverCacheCoordinator.Priority
    
    init(
        file: FileState.ActiveFile,
        refreshToken: String? = nil,
        allowsGeneration: Bool = true,
        generationPriority: FileCoverCacheCoordinator.Priority = .recently
    ) {
        self.source = .activeFile(file)
        self.refreshToken = refreshToken
        self.allowsGeneration = allowsGeneration
        self.generationPriority = generationPriority
    }
    
    init(
        excalidrawFile: ExcalidrawFile,
        refreshToken: String? = nil,
        allowsGeneration: Bool = true,
        generationPriority: FileCoverCacheCoordinator.Priority = .recently
    ) {
        self.source = .excalidrawFile(excalidrawFile)
        self.refreshToken = refreshToken
        self.allowsGeneration = allowsGeneration
        self.generationPriority = generationPriority
    }
    
    var fileID: String {
        switch source {
            case .activeFile(let file):
                return file.canonicalID
            case .excalidrawFile(let file):
                return file.id
        }
    }
    
    var body: some View {
        ExcalidrawFileCoverImage(
            source: source,
            fileID: fileID,
            colorScheme: colorScheme,
            refreshToken: refreshToken,
            allowsGeneration: allowsGeneration,
            generationPriority: generationPriority
        )
        .id(FileItemPreviewCache.cacheKey(forID: fileID, colorScheme: colorScheme))
    }
}

/// Keyed by file and appearance, so a warm cover starts with the cached pixels
/// rather than inserting them with an onAppear state change.
private struct ExcalidrawFileCoverImage: View {
    let source: ExcalidrawFileCover.Source
    let fileID: String
    let colorScheme: ColorScheme
    let refreshToken: String?
    let allowsGeneration: Bool
    let generationPriority: FileCoverCacheCoordinator.Priority

    private let cache = FileItemPreviewCache.shared
    private let updateEvents: AnyPublisher<FileCoverUpdateEvents.Event, Never>
    @State private var coverImage: PlatformImage?

    init(
        source: ExcalidrawFileCover.Source,
        fileID: String,
        colorScheme: ColorScheme,
        refreshToken: String?,
        allowsGeneration: Bool,
        generationPriority: FileCoverCacheCoordinator.Priority
    ) {
        self.source = source
        self.fileID = fileID
        self.colorScheme = colorScheme
        self.refreshToken = refreshToken
        self.allowsGeneration = allowsGeneration
        self.generationPriority = generationPriority
        self.updateEvents = FileCoverUpdateEvents.shared.publisher(for: fileID)
        self._coverImage = State(initialValue: FileItemPreviewCache.shared.getPreviewCache(
            forID: fileID,
            colorScheme: colorScheme
        ))
    }

    var body: some View {
        previewContent
            .apply { view in
                applyListeners(to: view)
            }
            .onAppear {
                updateCoverFromCache()
            }
            .watch(value: refreshToken ?? "default") { _ in
                updateCoverFromCache()
            }
            .onReceive(updateEvents) { event in
                switch event {
                    case .refreshRequested:
                        requestCoverRefresh(forceRefresh: true)
                    case .imageUpdated:
                        updateCoverFromCache(requestIfMissing: false)
                }
            }
    }
    
    @ViewBuilder
    private var previewContent: some View {
        ZStack {
            if let coverImage {
                Image(platformImage: coverImage)
                    .resizable()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.08 : 0.06))
            }
        }
    }

    @ViewBuilder
    private func applyListeners<V: View>(to view: V) -> some View {
        switch source {
            case .activeFile(let file):
                // Apply all listeners for ActiveFile
                view
                    .observeFileStatus(for: file, onlyICloudStatusChanges: true) { status in
#if os(macOS)
                        if status.iCloudStatus == .outdated {
                            self.requestCoverRefresh(forceRefresh: true)
                        }
#endif
                    }
            case .excalidrawFile:
                view
        }
    }

    @discardableResult
    private func showCachedCoverIfAvailable() -> Bool {
        guard let image = cache.getPreviewCache(forID: fileID, colorScheme: colorScheme) else {
            return false
        }

        // Lazy grids can invoke onAppear again for an already displayed cover.
        if coverImage !== image {
            coverImage = image
        }
        return true
    }

    private func updateCoverFromCache(requestIfMissing: Bool = true) {
        if !showCachedCoverIfAvailable() {
            if coverImage != nil { coverImage = nil }
            if requestIfMissing {
                requestCoverRefresh(
                    forceRefresh: false,
                    priority: generationPriority
                )
            }
        }
    }

    private func requestCoverRefresh(
        forceRefresh: Bool,
        priority: FileCoverCacheCoordinator.Priority = .userInitiated
    ) {
        guard allowsGeneration else { return }

        let coordinatorSource: FileCoverCacheCoordinator.Source = {
            switch source {
                case .activeFile(let file):
                    return .activeFile(file)
                case .excalidrawFile(let file):
                    return .excalidrawFile(file)
            }
        }()

        FileCoverCacheCoordinator.shared.request(
            source: coordinatorSource,
            colorScheme: colorScheme,
            priority: priority,
            forceRefresh: forceRefresh
        )
    }
}

/// Displays cached pixels without the production cover's status listeners,
/// refresh subscriptions, lock animations or JavaScript generation requests.
struct CachedFileCover: View {
    let file: FileState.ActiveFile
    let colorScheme: ColorScheme

    var body: some View {
        FilePreviewLockStateReader(file: file) { lockState in
            if let lockState, lockState != .locked {
                CachedFileCoverImage(file: file, colorScheme: colorScheme)
            } else {
                Color.clear
            }
        }
    }
}

/// Cached pixels for a caller that already gates display on protection state.
/// Keeping this leaf free of store subscriptions avoids observing the same
/// lock state a second time inside the lock preview.
struct CachedFileCoverImage: View {
    let file: FileState.ActiveFile
    let colorScheme: ColorScheme
    private let cacheKey: NSString
    @State private var image: PlatformImage?

    init(file: FileState.ActiveFile, colorScheme: ColorScheme) {
        self.file = file
        self.colorScheme = colorScheme
        let key = FileItemPreviewCache.cacheKey(forID: file.canonicalID, colorScheme: colorScheme)
        self.cacheKey = key
        // The caller keys this subtree by file and appearance so SwiftUI seeds
        // a fresh image state when either changes. This lookup is memory-only.
        self._image = State(initialValue: FileItemPreviewCache.shared.object(forKey: key))
    }

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: cacheKey) {
                guard image == nil else { return }
                let cachedImage = await FileCoverCacheCoordinator.shared.loadCachedPreview(
                    for: file,
                    colorScheme: colorScheme
                )
                guard !Task.isCancelled, image !== cachedImage else { return }
                image = cachedImage
            }
    }
}

#if canImport(AppKit)
extension NSImage {
    func downsampledCGImage(maxPixelSize: CGFloat) -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        guard let cgImage = self.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longestSide = max(width, height)
        guard maxPixelSize > 0, longestSide > 0 else { return nil }
        let scale = min(1, maxPixelSize / longestSide)
        guard scale < 1 else { return cgImage }
        let targetSize = CGSize(width: max(1, width * scale), height: max(1, height * scale))

        guard let ctx = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        return ctx.makeImage()
    }
}
#endif

#if canImport(UIKit)
extension UIImage {
    func downsampledCGImage(maxPixelSize: CGFloat) -> CGImage? {
        let cgImage: CGImage
        if let image = self.cgImage {
            cgImage = image
        } else if let ciImage = self.ciImage {
            let context = CIContext(options: nil)
            guard let image = context.createCGImage(ciImage, from: ciImage.extent) else {
                return nil
            }
            cgImage = image
        } else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longestSide = max(width, height)
        guard maxPixelSize > 0, longestSide > 0 else { return nil }
        let scale = min(1, maxPixelSize / longestSide)
        guard scale < 1 else { return cgImage }
        let targetSize = CGSize(width: max(1, width * scale), height: max(1, height * scale))

        guard let ctx = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        return ctx.makeImage()
    }
}
#endif
