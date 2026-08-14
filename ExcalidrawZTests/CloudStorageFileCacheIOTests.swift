//
//  CloudStorageFileCacheIOTests.swift
//  ExcalidrawZTests
//

import Foundation
import XCTest
@testable import ExcalidrawZ

final class CloudStorageFileCacheIOTests: XCTestCase {
    func testRemoteCandidateCannotReplaceNewerLocalWrite() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let documentURL = rootURL.appending(path: "Drawing.excalidraw")
        let cacheIO = CloudStorageFileCacheIO()
        let initialGeneration = await cacheIO.generation(at: documentURL)

        try await cacheIO.write(Data("local".utf8), to: documentURL)
        let installed = try await cacheIO.write(
            Data("remote".utf8),
            to: documentURL,
            ifGenerationIs: initialGeneration
        )

        XCTAssertFalse(installed)
        let storedData = try await cacheIO.read(at: documentURL)
        XCTAssertEqual(String(decoding: storedData, as: UTF8.self), "local")
    }

    func testRemoteCandidateInstallsWhenCacheIsUnchanged() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let documentURL = rootURL.appending(path: "Drawing.excalidraw")
        let cacheIO = CloudStorageFileCacheIO()
        let initialGeneration = await cacheIO.generation(at: documentURL)

        let installed = try await cacheIO.write(
            Data("remote".utf8),
            to: documentURL,
            ifGenerationIs: initialGeneration
        )

        XCTAssertTrue(installed)
        let storedData = try await cacheIO.read(at: documentURL)
        XCTAssertEqual(String(decoding: storedData, as: UTF8.self), "remote")
    }

    func testRemovingCacheDirectoryInvalidatesInFlightCandidate() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let documentURL = rootURL.appending(path: "Drawing.excalidraw")
        let cacheIO = CloudStorageFileCacheIO()
        let initialGeneration = await cacheIO.generation(at: documentURL)

        try await cacheIO.removeDirectoryIfExists(at: rootURL)
        let installed = try await cacheIO.write(
            Data("late remote".utf8),
            to: documentURL,
            ifGenerationIs: initialGeneration
        )

        XCTAssertFalse(installed)
        let storedData = try await cacheIO.readIfExists(at: documentURL)
        XCTAssertNil(storedData)
    }
}
