//
//  FileCoverDiskCache.swift
//  ExcalidrawZ
//

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An immutable, eagerly decoded bitmap that can cross actor boundaries.
struct FileCoverThumbnail: Sendable {
    let image: CGImage

    var memoryCost: Int { image.bytesPerRow * image.height }
}

/// File IO, PNG encoding and image decoding stay on this actor, away from UI work.
actor FileCoverDiskCache {
    static let shared = FileCoverDiskCache()

    private struct Record: Codable {
        let key: String
        let revision: String
        let png: Data
    }

    private let directory: URL
    private let maximumBytes: Int
    private let maximumEntries: Int
    private let pruningInterval: TimeInterval
    private var lastPrunedAt = Date.distantPast

    init(
        directory: URL? = nil,
        maximumBytes: Int = 256 * 1024 * 1024,
        maximumEntries: Int = 4_000,
        pruningInterval: TimeInterval = 60
    ) {
        self.directory = directory ?? FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0].appendingPathComponent("FileCoverPreviews/v1", isDirectory: true)
        self.maximumBytes = maximumBytes
        self.maximumEntries = maximumEntries
        self.pruningInterval = pruningInterval
    }

    func load(key: String, revision: String, maxPixelSize: CGFloat) -> FileCoverThumbnail? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let record = try? PropertyListDecoder().decode(Record.self, from: data),
              record.key == key else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        guard record.revision == revision else { return nil }
        guard let thumbnail = thumbnail(from: record.png, maxPixelSize: maxPixelSize) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        // Modification time tracks access for disk eviction, not document freshness.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return thumbnail
    }

    @discardableResult
    func store(_ thumbnail: FileCoverThumbnail, key: String, revision: String) -> Bool {
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            png, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(destination, thumbnail.image, nil)
        guard CGImageDestinationFinalize(destination) else { return false }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            // One atomic record keeps the revision and image consistent after a crash.
            let data = try encoder.encode(Record(key: key, revision: revision, png: png as Data))
            try data.write(to: fileURL(for: key), options: .atomic)
            pruneIfNeeded()
            return true
        } catch {
            return false
        }
    }

    func remove(key: String) {
        let url = fileURL(for: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func thumbnail(from data: Data, maxPixelSize: CGFloat) -> FileCoverThumbnail? {
        guard maxPixelSize.isFinite, maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return FileCoverThumbnail(image: image)
    }

    func fileRevision(at url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey, .fileSizeKey
        ]), let modifiedAt = values.contentModificationDate else { return nil }
        return "\(modifiedAt.timeIntervalSince1970):\(values.fileSize ?? 0)"
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("preview")
    }

    private func pruneIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastPrunedAt) >= pruningInterval else { return }
        lastPrunedAt = now
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let entries = urls.filter { $0.pathExtension == "preview" }.compactMap { url -> (URL, Date, Int)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 < $1.1 }
        var bytes = entries.reduce(0) { $0 + $1.2 }
        var count = entries.count
        for (url, _, size) in entries {
            guard bytes > maximumBytes || count > maximumEntries else { break }
            try? FileManager.default.removeItem(at: url)
            bytes -= size
            count -= 1
        }
    }
}
