import Foundation
import XCTest
@testable import ExcalidrawZ

final class LinkedFolderIndexTests: XCTestCase {
    private actor Recorder {
        var updates: [LinkedFolderIndex.Update] = []
        func append(_ value: LinkedFolderIndex.Update) { updates.append(value) }
        func latest() -> LinkedFolderIndex.Update? { updates.last }
        func count() -> Int { updates.count }
        func since(_ count: Int) -> [LinkedFolderIndex.Update] { Array(updates.dropFirst(count)) }
    }

    private func sandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LinkedFolderIndexTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func file(_ path: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
        return url.standardizedFileURL
    }

    private func eventually(_ description: String, timeout: TimeInterval = 6,
                            _ predicate: () async -> Bool) async throws {
        let limit = Date().addingTimeInterval(timeout)
        while Date() < limit {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTFail(description)
    }

    func testShallowBrowsingDoesNotWalkChildrenAndDeepScanKeepsOnlyDrawings() throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let top = try file("top.excalidraw", in: root)
        let nested = try file("target/debug/deep.excalidraw", in: root)
        try file("node_modules/package/index.js", in: root)
        try file(".git/hidden.excalidraw", in: root)
        try file("folder/.hidden.excalidraw", in: root)
        let png = try file("folder/image.excalidraw.png", in: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cycle"), withDestinationURL: root)
        XCTAssertEqual(try LinkedFolderScanner.scan(root, recursively: false).files.map(\.url), [top])
        XCTAssertEqual(Set(try LinkedFolderScanner.scan(root).files.map(\.url)), Set([top, nested, png]))
        let children = try LinkedFolderScanner.immediateDirectories(at: root).map(\.lastPathComponent)
        XCTAssertEqual(Set(children), Set(["target", "node_modules", "folder"]))
        XCTAssertEqual(try LinkedFolderScanner.immediateItemCount(at: root), 4)
    }

    func testOverlappingRootsAreCollapsedButExplicitHiddenRootsRemainAccessible() throws {
        let root = URL(fileURLWithPath: "/projects")
        let child = root.appendingPathComponent("app")
        let similarlyNamed = URL(fileURLWithPath: "/projects-other")
        let hidden = root.appendingPathComponent(".private")
        XCTAssertEqual(Set(LinkedFolderScanner.minimalRoots([child, root, root, similarlyNamed, hidden])),
                       Set([root, similarlyNamed, hidden]))
    }

    func testFileAndDirectoryMovesAndDeletionUpdateOnlyAffectedScopes() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let first = try file("one/a.excalidraw", in: root)
        let untouched = try file("two/b.excalidraw", in: root)
        let recorder = Recorder()
        let index = LinkedFolderIndex(cacheDirectory: base.appendingPathComponent("cache"), monitorsEvents: false) {
            await recorder.append($0)
        }
        await index.configure([.init(id: "root", url: root, bookmark: nil)])
        try await eventually("Initial files indexed") { await recorder.latest()?.recentFiles.count == 2 }
        let old = first.deletingLastPathComponent()
        let moved = root.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: old, to: moved)
        await index.receive(.init(paths: [old, moved], recursivePaths: [old, moved], eventID: 1), rootID: "root")
        let renamedFile = moved.appendingPathComponent("a.excalidraw")
        try await eventually("Moved subtree discovered; old subtree removed") {
            let urls = await recorder.latest()?.recentFiles.map(\.url) ?? []
            return Set(urls) == Set([renamedFile, untouched])
        }
        let renamedAgain = root.appendingPathComponent("new.excalidraw")
        try FileManager.default.moveItem(at: renamedFile, to: renamedAgain)
        await index.invalidate([renamedFile, renamedAgain])
        try await eventually("File rename reconciled") {
            Set(await recorder.latest()?.recentFiles.map(\.url) ?? []) == Set([renamedAgain, untouched])
        }
        try FileManager.default.removeItem(at: renamedAgain)
        await index.invalidate([renamedAgain])
        try await eventually("Deleted drawing removed") {
            await recorder.latest()?.recentFiles.map(\.url) == [untouched]
        }
        await index.stop()
    }

    func testEventLossReconcilesTheWholeTree() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let old = try file("old.excalidraw", in: root)
        let recorder = Recorder()
        let index = LinkedFolderIndex(cacheDirectory: base.appendingPathComponent("cache"), monitorsEvents: false) {
            await recorder.append($0)
        }
        await index.configure([.init(id: "root", url: root, bookmark: nil)])
        try await eventually("Initial index ready") { await recorder.latest()?.recentFiles.count == 1 }
        try FileManager.default.removeItem(at: old)
        let new = try file("new/drawing.excalidraw", in: root)
        await index.receive(.init(requiresFullScan: true), rootID: "root")
        try await eventually("Dropped events trigger background recovery") {
            await recorder.latest()?.recentFiles.map(\.url) == [new]
        }
        await index.stop()
    }

    func testUnlinkCancelsWorkAndLateEventsCannotRestoreEntries() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        try file("drawing.excalidraw", in: root)
        for index in 0..<600 {
            try file("target/\(index)/output.o", in: root)
        }
        let recorder = Recorder()
        let cache = base.appendingPathComponent("cache")
        let index = LinkedFolderIndex(cacheDirectory: cache, monitorsEvents: false) { await recorder.append($0) }
        await index.configure([.init(id: "root", url: root, bookmark: nil)])
        await index.configure([])
        await index.receive(.init(paths: [root], requiresFullScan: true), rootID: "root")
        try await Task.sleep(for: .milliseconds(500))
        let latest = await recorder.latest()
        XCTAssertEqual(latest?.recentFiles.count, 0)
        XCTAssertTrue(((try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []).isEmpty)
        await index.stop()
    }

    func testDeletedDirectoryRemovesAllNestedDrawings() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let drawing = try file("branch/deep/nested/drawing.excalidraw", in: root)
        let kept = try file("kept.excalidraw", in: root)
        let recorder = Recorder()
        let index = LinkedFolderIndex(cacheDirectory: base.appendingPathComponent("cache"), monitorsEvents: false) { await recorder.append($0) }
        await index.configure([.init(id: "root", url: root, bookmark: nil)])
        try await eventually("Initial deep drawing indexed") { await recorder.latest()?.recentFiles.count == 2 }
        let branch = root.appendingPathComponent("branch")
        try FileManager.default.removeItem(at: branch)
        // Even a coalesced invalidation without item-type flags must remove the subtree.
        await index.invalidate([branch])
        try await eventually("All descendants of the deleted directory removed") {
            await recorder.latest()?.recentFiles.map(\.url) == [kept]
        }
        let files = await index.drawingFiles()
        XCTAssertFalse(files.contains { $0.url == drawing })
        await index.stop()
    }

    func testTimestampChangesAreNotReadFromAnOldURLResourceCache() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let drawing = try file("drawing.excalidraw", in: root)
        let recorder = Recorder()
        let index = LinkedFolderIndex(cacheDirectory: base.appendingPathComponent("cache"), monitorsEvents: false) { await recorder.append($0) }
        await index.configure([.init(id: "root", url: root, bookmark: nil)])
        try await eventually("Initial index ready") { await recorder.latest()?.recentFiles.count == 1 }
        let latestURL = await recorder.latest()?.recentFiles.first?.url
        let cachedURL = try XCTUnwrap(latestURL)
        _ = try cachedURL.resourceValues(forKeys: [.contentModificationDateKey])
        let future = Date().addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: drawing.path)
        await index.invalidate([cachedURL])
        try await eventually("Modified date refreshed") {
            (await recorder.latest()?.recentFiles.first?.modifiedAt ?? .distantPast) >= future.addingTimeInterval(-1)
        }
        await index.stop()
    }

    func testOverlappingRootServiceRetainsAnIndependentlyLinkedChildAfterUnlinkingParent() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let drawing = try file("child/deep/drawing.excalidraw", in: root)
        let child = root.appendingPathComponent("child")
        let recorder = Recorder()
        let cache = base.appendingPathComponent("cache")
        let index = LinkedFolderIndex(cacheDirectory: cache, monitorsEvents: false) { await recorder.append($0) }
        let parentDescriptor = LinkedFolderIndex.Root(id: "parent", url: root, bookmark: nil)
        let childDescriptor = LinkedFolderIndex.Root(id: "child", url: child, bookmark: nil)
        await index.configure([childDescriptor, parentDescriptor])
        try await eventually("Overlapping roots indexed once") { await recorder.latest()?.recentFiles.count == 1 }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cache.path).count, 1)
        await index.configure([childDescriptor])
        try await eventually("Independent child remains usable") { await recorder.latest()?.recentFiles.map(\.url) == [drawing] }
        let indexed = await index.drawingFiles(matching: "drawing")
        XCTAssertEqual(indexed.map(\.url), [drawing])
        await index.stop()
    }

    func testInvalidOuterBookmarkDoesNotHideAnAccessibleLinkedChild() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let drawing = try file("child/drawing.excalidraw", in: root)
        let recorder = Recorder()
        let index = LinkedFolderIndex(cacheDirectory: base.appendingPathComponent("cache"), monitorsEvents: false) { await recorder.append($0) }
        await index.configure([
            .init(id: "parent", url: root, bookmark: Data("invalid".utf8)),
            .init(id: "child", url: root.appendingPathComponent("child"), bookmark: nil)
        ])
        try await eventually("Accessible child is not shadowed by failed parent grant") {
            await recorder.latest()?.recentFiles.map(\.url) == [drawing]
        }
        await index.stop()
    }

    func testUnavailableRootPreservesCacheAndRecoversWhenItReturns() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let drawing = try file("drawing.excalidraw", in: root)
        let recorder = Recorder()
        let index = LinkedFolderIndex(cacheDirectory: base.appendingPathComponent("cache"), monitorsEvents: false) { await recorder.append($0) }
        await index.configure([.init(id: "root", url: root, bookmark: nil)])
        try await eventually("Initial index ready") { await recorder.latest()?.recentFiles.count == 1 }
        let unavailable = base.appendingPathComponent("unavailable")
        try FileManager.default.moveItem(at: root, to: unavailable)
        await index.receive(.init(requiresFullScan: true), rootID: "root")
        try await Task.sleep(for: .milliseconds(600))
        let cached = await recorder.latest()?.recentFiles.map(\.url)
        XCTAssertEqual(cached, [drawing])
        try FileManager.default.moveItem(at: unavailable, to: root)
        let new = try file("new.excalidraw", in: root)
        await index.receive(.init(requiresFullScan: true), rootID: "root")
        try await eventually("Returning volume reconciled") {
            Set(await recorder.latest()?.recentFiles.map(\.url) ?? []) == Set([drawing, new])
        }
        await index.stop()
    }

    func testCorruptCacheIsRebuiltAndBuildOutputsAreNotPersisted() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let drawing = try file("drawing.excalidraw", in: root)
        for i in 0..<3000 { try file("target/\(i / 100)/\(i).o", in: root) }
        let cache = base.appendingPathComponent("cache")
        let recorder = Recorder()
        let index = LinkedFolderIndex(cacheDirectory: cache, monitorsEvents: false) { await recorder.append($0) }
        let descriptor = LinkedFolderIndex.Root(id: "root", url: root, bookmark: nil)
        await index.configure([descriptor])
        try await eventually("Build tree indexed") {
            await recorder.latest()?.invalidatedSubtrees.isEmpty == false
        }
        await index.stop()
        let cacheFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).first)
        XCTAssertLessThan(try Data(contentsOf: cacheFile).count, 2048)
        try Data("invalid cache".utf8).write(to: cacheFile)
        let reopened = LinkedFolderIndex(cacheDirectory: cache, monitorsEvents: false) { await recorder.append($0) }
        await reopened.configure([descriptor])
        try await eventually("Corrupt cache rebuilt") { await recorder.latest()?.recentFiles.map(\.url) == [drawing] }
        await reopened.stop()
    }

#if os(macOS)
    func testCacheInsideLinkedRootDoesNotCauseAnEventFeedbackLoop() async throws {
        let root = try sandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        try file("drawing.excalidraw", in: root)
        let recorder = Recorder()
        let index = LinkedFolderIndex(cacheDirectory: root.appendingPathComponent("cache")) { await recorder.append($0) }
        await index.configure([.init(id: "root", url: root, bookmark: nil)])
        try await eventually("Initial snapshot ready") { await recorder.latest()?.recentFiles.count == 1 }
        try await Task.sleep(for: .seconds(2))
        let count = await recorder.count()
        try await Task.sleep(for: .seconds(2))
        let laterCount = await recorder.count()
        XCTAssertEqual(count, laterCount, "Checkpoint writes must not recursively checkpoint themselves")
        await index.stop()
    }

    func testCachedRelaunchDoesNotRescanAndReplaysChangesMadeWhileClosed() async throws {
        let base = try sandbox()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("projects")
        let old = try file("old.excalidraw", in: root)
        guard LinkedFolderEventMonitor.historyIdentity(at: root) != nil else {
            throw XCTSkip("This volume has no persistent FSEvents history")
        }
        let cache = base.appendingPathComponent("cache")
        let descriptor = LinkedFolderIndex.Root(id: "root", url: root, bookmark: nil)
        let firstRecorder = Recorder()
        let first = LinkedFolderIndex(cacheDirectory: cache) { await firstRecorder.append($0) }
        await first.configure([descriptor])
        try await eventually("Initial snapshot committed") { await firstRecorder.latest()?.recentFiles.map(\.url) == [old] }
        await first.stop()

        let secondRecorder = Recorder()
        let second = LinkedFolderIndex(cacheDirectory: cache) { await secondRecorder.append($0) }
        await second.configure([descriptor])
        try await Task.sleep(for: .seconds(1))
        let updates = await secondRecorder.since(0)
        XCTAssertEqual(updates.first?.recentFiles.map(\.url), [old])
        XCTAssertFalse(updates.contains { $0.invalidatedSubtrees.contains(root) }, "Warm launch must not walk the root again")
        await second.stop()

        try FileManager.default.removeItem(at: old)
        let new = try file("added-while-closed/deep.excalidraw", in: root)
        let thirdRecorder = Recorder()
        let third = LinkedFolderIndex(cacheDirectory: cache) { await thirdRecorder.append($0) }
        await third.configure([descriptor])
        try await eventually("Historical events find offline additions and deletions", timeout: 10) {
            await thirdRecorder.latest()?.recentFiles.map(\.url) == [new]
        }
        await third.stop()
    }
#endif
}
