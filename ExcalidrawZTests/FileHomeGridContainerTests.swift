#if os(macOS)
import AppKit
import Combine
import SwiftUI
import XCTest
@testable import ExcalidrawZ

final class FileHomeGridContainerTests: XCTestCase {
    @MainActor
    func testCardStyleConfigurationDoesNotMutateOriginalView() {
        let original = FileHomeItemView(file: .temporaryFile(URL(fileURLWithPath: "/tmp/example.excalidraw")))
        let styled = original.fileHomeItemStyle(.file)
        XCTAssertTrue(original.config.style == .card)
        XCTAssertTrue(styled.config.style == .file)
    }

    @MainActor
    func testContainerConfigurationDoesNotMutateOriginalView() {
        let original = FileHomeContainer { EmptyView() }
        let configured = original
            .showPlaceholder(true, itemWidth: 320)
            .contentBottomPadding(60)
            .contentBackground { Color.clear }
        XCTAssertFalse(original.config.isPlaceholderPresented)
        XCTAssertEqual(original.config.itemWidth, 240)
        XCTAssertEqual(original.config.bottomPadding, 30)
        XCTAssertNil(original.config.contentBackground)
        XCTAssertTrue(configured.config.isPlaceholderPresented)
        XCTAssertEqual(configured.config.itemWidth, 320)
        XCTAssertEqual(configured.config.bottomPadding, 60)
        XCTAssertNotNil(configured.config.contentBackground)
    }

    func testAdaptiveColumnsAtResizeBoundary() {
        let wide = FileHomeGridMetrics(viewportWidth: 1080, minimumItemWidth: 240)
        XCTAssertEqual(wide.columns, 4)
        XCTAssertEqual(wide.itemWidth, 240, accuracy: 0.001)

        let narrow = FileHomeGridMetrics(viewportWidth: 1079, minimumItemWidth: 240)
        XCTAssertEqual(narrow.columns, 3)
        XCTAssertEqual(narrow.itemWidth, 326.333333, accuracy: 0.001)
    }

    func testGridPreservesMarginsAndSpacing() {
        for (width, columns, cardWidth) in [(600.0, 2, 260.0), (800.0, 2, 360.0), (1600.0, 6, 240.0)] {
            let metrics = FileHomeGridMetrics(viewportWidth: width, minimumItemWidth: 240)
            XCTAssertEqual(metrics.columns, columns)
            XCTAssertEqual(metrics.itemWidth, cardWidth, accuracy: 0.001)
        }
    }

    func testSmallSizingProposalsStayFinite() {
        for width in [0.0, 1.0, 60.0, 200.0] {
            let metrics = FileHomeGridMetrics(viewportWidth: width, minimumItemWidth: 240)
            XCTAssertEqual(metrics.columns, 1)
            XCTAssertTrue(metrics.itemWidth.isFinite)
            XCTAssertGreaterThan(metrics.itemWidth, 0)
        }
    }

    @MainActor
    func testCellReuseDoesNotPublishTransitionUpdatesDuringOrdinaryScrolling() async {
        let bridge = FileHomeNativeTransitionBridge()
        var notifications = 0
        let subscription = bridge.objectWillChange.sink { notifications += 1 }
        for index in 0..<100 {
            let view = NSView()
            let id = "file-\(index)"
            bridge.registerSource(view, fileID: id)
            bridge.sourceBecameVisible(fileID: id)
            bridge.removeSource(view, fileID: id)
        }
        await nextMainQueueTurn()
        XCTAssertEqual(notifications, 0)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testOnlyActiveTransitionRegistrationsPublishAndTheyAreCoalesced() async {
        let bridge = FileHomeNativeTransitionBridge()
        bridge.activeFileID = "active"
        var notifications = 0
        let subscription = bridge.objectWillChange.sink { notifications += 1 }
        let source = NSView()
        bridge.registerSource(source, fileID: "other")
        await nextMainQueueTurn()
        XCTAssertEqual(notifications, 0)

        bridge.registerSource(source, fileID: "active")
        bridge.sourceBecameVisible(fileID: "active")
        bridge.sourceBecameVisible(fileID: "active")
        await nextMainQueueTurn()
        XCTAssertEqual(notifications, 1)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
#endif
