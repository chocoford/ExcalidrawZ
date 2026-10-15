import CoreGraphics
import Foundation
import XCTest
@testable import ExcalidrawZ

final class FileCoverDiskCacheTests: XCTestCase {
    func testPreviewSurvivesANewCacheInstanceAndKeepsAppearanceSeparate() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCoverDiskCache(directory: directory)
        let image = try thumbnail(width: 32, height: 16)
        let stored = await cache.store(image, key: "file_light", revision: "content:1:viewport:1")
        XCTAssertTrue(stored)

        let reopened = FileCoverDiskCache(directory: directory)
        let hit = await reopened.load(key: "file_light", revision: "content:1:viewport:1", maxPixelSize: 720)
        let dark = await reopened.load(key: "file_dark", revision: "content:1:viewport:1", maxPixelSize: 720)
        XCTAssertEqual(hit?.image.width, 32)
        XCTAssertEqual(hit?.image.height, 16)
        XCTAssertNil(dark)
    }

    func testChangedContentOrViewportDoesNotReturnAnOldPreview() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCoverDiskCache(directory: directory)
        let image = try thumbnail(width: 32, height: 16)
        let stored = await cache.store(image, key: "file_light", revision: "content:1:viewport:1")
        XCTAssertTrue(stored)

        let contentChanged = await cache.load(key: "file_light", revision: "content:2:viewport:1", maxPixelSize: 720)
        let viewportChanged = await cache.load(key: "file_light", revision: "content:1:viewport:2", maxPixelSize: 720)
        XCTAssertNil(contentChanged)
        XCTAssertNil(viewportChanged)
        await cache.remove(key: "file_light")
        let removed = await cache.load(key: "file_light", revision: "content:1:viewport:1", maxPixelSize: 720)
        XCTAssertNil(removed)
    }

    func testCorruptRecordFallsBackToACacheMiss() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCoverDiskCache(directory: directory)
        let image = try thumbnail(width: 32, height: 16)
        let stored = await cache.store(image, key: "file_light", revision: "1")
        XCTAssertTrue(stored)
        let url = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).first)
        try Data("invalid cache".utf8).write(to: url)
        let result = await cache.load(key: "file_light", revision: "1", maxPixelSize: 720)
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDiskReadDownsamplesToTheRequestedPixelSize() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCoverDiskCache(directory: directory)
        let image = try thumbnail(width: 800, height: 400)
        let stored = await cache.store(image, key: "file_light", revision: "1")
        XCTAssertTrue(stored)
        let result = await cache.load(key: "file_light", revision: "1", maxPixelSize: 200)
        XCTAssertEqual(result?.image.width, 200)
        XCTAssertEqual(result?.image.height, 100)
    }

    func testEntryLimitEvictsTheOldestPreview() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileCoverDiskCache(directory: directory, maximumEntries: 1, pruningInterval: 0)
        let image = try thumbnail(width: 32, height: 16)
        let first = await cache.store(image, key: "first", revision: "1")
        let second = await cache.store(image, key: "second", revision: "1")
        XCTAssertTrue(first && second)
        let old = await cache.load(key: "first", revision: "1", maxPixelSize: 720)
        let newest = await cache.load(key: "second", revision: "1", maxPixelSize: 720)
        XCTAssertNil(old)
        XCTAssertNotNil(newest)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func thumbnail(width: Int, height: Int) throws -> FileCoverThumbnail {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return FileCoverThumbnail(image: try XCTUnwrap(context.makeImage()))
    }
}
