import Foundation
import XCTest
@testable import ExcalidrawZ

final class LinkedFolderRefreshQueueTests: XCTestCase {
    private actor Counter {
        var active = 0
        var peak = 0
        var starts: [String] = []
        func begin(_ key: String) {
            active += 1
            peak = max(peak, active)
            starts.append(key)
        }
        func end() { active -= 1 }
        func snapshot() -> (active: Int, peak: Int, starts: [String]) { (active, peak, starts) }
    }

    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }

    private func eventually(_ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Queued work did not reach the expected state")
    }

    func testThousandDirectoryRequestsNeverExceedTheWorkerLimit() async throws {
        let queue = LinkedFolderRefreshQueue<Int, Int>(maximumConcurrent: 2)
        let counter = Counter()
        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for key in 0..<1000 {
                group.addTask {
                    try await queue.run(key: key) {
                        await counter.begin(String(key))
                        try await Task.sleep(for: .milliseconds(1))
                        await counter.end()
                        return key
                    }
                }
            }
            var values: Set<Int> = []
            for try await value in group { values.insert(value) }
            return values
        }
        let state = await counter.snapshot()
        XCTAssertEqual(results.count, 1000)
        XCTAssertEqual(state.starts.count, 1000)
        XCTAssertLessThanOrEqual(state.peak, 2)
        XCTAssertEqual(state.active, 0)
    }

    func testDuplicateRequestsShareWorkAndItsResult() async throws {
        let queue = LinkedFolderRefreshQueue<String, Int>()
        let gate = Gate()
        let counter = Counter()
        let first = Task {
            try await queue.run(key: "folder") {
                await counter.begin("folder")
                await gate.wait()
                await counter.end()
                return 42
            }
        }
        try await eventually { await counter.snapshot().starts.count == 1 }
        let second = Task { try await queue.run(key: "folder") { XCTFail("Duplicate started"); return -1 } }
        try await Task.sleep(for: .milliseconds(30))
        await gate.open()
        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult, 42)
        XCTAssertEqual(secondResult, 42)
        let state = await counter.snapshot()
        XCTAssertEqual(state.starts.count, 1)
    }

    func testCancellingOneCallerDoesNotCancelAnotherCallerForTheSameFolder() async throws {
        let queue = LinkedFolderRefreshQueue<String, Int>()
        let gate = Gate()
        let counter = Counter()
        let first = Task {
            try await queue.run(key: "folder") {
                await counter.begin("folder")
                await gate.wait()
                try Task.checkCancellation()
                await counter.end()
                return 42
            }
        }
        try await eventually { await counter.snapshot().starts.count == 1 }
        let second = Task { try await queue.run(key: "folder") { return -1 } }
        try await Task.sleep(for: .milliseconds(30))
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled caller succeeded") } catch is CancellationError {}
        await gate.open()
        let result = try await second.value
        XCTAssertEqual(result, 42)
    }

    func testCancellingQueuedWorkDoesNotStartIt() async throws {
        let queue = LinkedFolderRefreshQueue<String, Void>()
        let gate = Gate()
        let counter = Counter()
        let first = Task {
            try await queue.run(key: "active") {
                await counter.begin("active")
                await gate.wait()
                await counter.end()
            }
        }
        try await eventually { await counter.snapshot().starts.count == 1 }
        let queued = Task {
            try await queue.run(key: "unlinked") { await counter.begin("unlinked"); await counter.end() }
        }
        try await Task.sleep(for: .milliseconds(30))
        queued.cancel()
        do { try await queued.value; XCTFail("Cancelled caller succeeded") } catch is CancellationError {}
        await gate.open()
        try await first.value
        let state = await counter.snapshot()
        XCTAssertEqual(state.starts, ["active"])
    }

    func testCancelledWorkerKeepsItsSlotUntilTheUnderlyingWorkHasExited() async throws {
        let queue = LinkedFolderRefreshQueue<String, Void>()
        let gate = Gate()
        let counter = Counter()
        let first = Task {
            try await queue.run(key: "folder") {
                await counter.begin("old")
                // Models a synchronous Core Data block unwinding after cancellation.
                await gate.wait()
                await counter.end()
            }
        }
        try await eventually { await counter.snapshot().starts == ["old"] }
        await queue.cancel(keys: ["folder"])
        do { try await first.value; XCTFail("Unlinked request succeeded") } catch is CancellationError {}
        let next = Task {
            try await queue.run(key: "folder") { await counter.begin("new"); await counter.end() }
        }
        try await Task.sleep(for: .milliseconds(30))
        let waiting = await counter.snapshot()
        XCTAssertEqual(waiting.starts, ["old"])
        await gate.open()
        try await next.value
        let final = await counter.snapshot()
        XCTAssertEqual(final.starts, ["old", "new"])
        XCTAssertEqual(final.peak, 1)
    }

    func testFailureDoesNotStallSubsequentWork() async throws {
        enum Expected: Error { case failure }
        let queue = LinkedFolderRefreshQueue<Int, Int>()
        do {
            _ = try await queue.run(key: 0) { throw Expected.failure }
            XCTFail("Failing work succeeded")
        } catch Expected.failure {}
        let value = try await queue.run(key: 1) { 123 }
        XCTAssertEqual(value, 123)
    }

    func testInvalidationDuringWorkGetsANewSnapshotWithoutStartingConcurrentWork() async throws {
        let queue = LinkedFolderRefreshQueue<String, Int>()
        let gate = Gate()
        let counter = Counter()
        let first = Task {
            try await queue.run(key: "folder", requiresFreshResult: true) {
                await counter.begin("old")
                await gate.wait()
                await counter.end()
                return 1
            }
        }
        try await eventually { await counter.snapshot().starts == ["old"] }
        let updated = Task {
            try await queue.run(key: "folder", requiresFreshResult: true) {
                await counter.begin("new")
                await counter.end()
                return 2
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        let waiting = await counter.snapshot()
        XCTAssertEqual(waiting.starts, ["old"])
        await gate.open()
        let oldValue = try await first.value
        let newValue = try await updated.value
        XCTAssertEqual(oldValue, 1)
        XCTAssertEqual(newValue, 2)
        let state = await counter.snapshot()
        XCTAssertEqual(state.peak, 1)
    }
}
