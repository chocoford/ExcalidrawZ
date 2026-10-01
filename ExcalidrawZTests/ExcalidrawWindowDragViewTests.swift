//
//  ExcalidrawWindowDragViewTests.swift
//  ExcalidrawZTests
//

#if os(macOS)
import AppKit
import XCTest
@testable import ExcalidrawZ

final class ExcalidrawWindowDragViewTests: XCTestCase {
    @MainActor
    func testHitTestingUsesTheSuperviewCoordinateSystem() async throws {
        let (window, root) = try makeWindow()
        defer { window.close() }

        let dragView = ExcalidrawWindowDragView(
            frame: NSRect(x: 200, y: 0, width: 600, height: 72)
        )
        root.addSubview(dragView)

        XCTAssertTrue(dragView.hitTest(NSPoint(x: 750, y: 10)) === dragView)
        XCTAssertNil(dragView.hitTest(NSPoint(x: 100, y: 10)))

        dragView.isHidden = true
        XCTAssertNil(dragView.hitTest(NSPoint(x: 750, y: 10)))
    }

    @MainActor
    func testOversizedDragRegionDoesNotInterceptCanvasAfterResizing() async throws {
        let (window, root) = try makeWindow()
        defer { window.close() }

        let dragView = ExcalidrawWindowDragView()
        root.addSubview(dragView)

        for size in [
            NSSize(width: 800, height: 600),
            NSSize(width: 1000, height: 800),
            NSSize(width: 650, height: 450),
        ] {
            window.setContentSize(size)
            // Simulate a stale or oversized frame during a SwiftUI layout update.
            dragView.frame = root.bounds

            XCTAssertTrue(dragView.hitTest(NSPoint(x: 400, y: 10)) === dragView)
            XCTAssertNil(dragView.hitTest(NSPoint(x: 400, y: 150)))
        }
    }

    @MainActor
    func testHitTestingHandlesAnUnflippedSuperviewAfterResizing() async throws {
        let (window, root) = try makeWindow()
        defer { window.close() }

        let parent = NSView(frame: root.bounds)
        root.addSubview(parent)
        let dragView = ExcalidrawWindowDragView()
        parent.addSubview(dragView)

        for size in [NSSize(width: 800, height: 600), NSSize(width: 1000, height: 800)] {
            window.setContentSize(size)
            parent.frame = root.bounds
            dragView.frame = NSRect(
                x: 200,
                y: parent.bounds.maxY - 72,
                width: parent.bounds.width - 200,
                height: 72
            )

            let toolbarPoint = parent.convert(NSPoint(x: 750, y: 10), from: root)
            let canvasPoint = parent.convert(NSPoint(x: 750, y: 150), from: root)
            XCTAssertTrue(dragView.hitTest(toolbarPoint) === dragView)
            XCTAssertNil(dragView.hitTest(canvasPoint))
        }
    }

    @MainActor
    private func makeWindow() throws -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let root = FlippedView(frame: try XCTUnwrap(window.contentView).bounds)
        window.contentView = root
        return (window, root)
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
}
#endif
