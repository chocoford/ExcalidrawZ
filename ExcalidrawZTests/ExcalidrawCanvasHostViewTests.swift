//
//  ExcalidrawCanvasHostViewTests.swift
//  ExcalidrawZTests
//

#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import WebKit
import XCTest
@testable import ExcalidrawZ

final class ExcalidrawCanvasHostViewTests: XCTestCase {
    @MainActor
    func testSizingProbesLeaveTheVisibleCanvasAtItsCurrentSize() async {
        let host = ExcalidrawCanvasHostView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 850)
        )
        let webView = makeWebView()
        host.attach(webView)
        host.layoutSubtreeIfNeeded()
        flushViewportUpdates()
        let visibleFrame = webView.frame

        for proposal in [
            ProposedViewSize(width: 0, height: 0),
            ProposedViewSize(width: nil, height: nil),
            ProposedViewSize(width: .infinity, height: .infinity),
            ProposedViewSize(width: 250, height: 400),
        ] {
            let measuredSize = host.sizeForProposal(proposal)
            XCTAssertTrue(measuredSize.width.isFinite)
            XCTAssertTrue(measuredSize.height.isFinite)
            XCTAssertEqual(host.frame.size, NSSize(width: 1200, height: 850))
            XCTAssertEqual(webView.frame, visibleFrame)
        }
    }

    @MainActor
    func testWebViewportFillsHostAfterItsFrameChangesSettle() async {
        let host = ExcalidrawCanvasHostView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        let webView = makeWebView()
        host.attach(webView)
        host.layoutSubtreeIfNeeded()
        flushViewportUpdates()
        XCTAssertEqual(webView.frame.size, NSSize(width: 800, height: 600))

        for size in [
            NSSize(width: 250, height: 400),
            NSSize(width: 1200, height: 850),
            NSSize(width: 920, height: 680),
        ] {
            // SwiftUI can assign the whole frame instead of calling setFrameSize(_:).
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            flushViewportUpdates()
            XCTAssertEqual(webView.frame, host.bounds)
        }
    }

    @MainActor
    func testMinimumLayoutFramesAreNotSentToWebKitDuringResizeTracking() async {
        let host = ExcalidrawCanvasHostView(
            frame: NSRect(x: 0, y: 0, width: 988, height: 712)
        )
        let webView = RecordingWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration(),
            toolbarActionHandler: { _ in }
        )
        host.attach(webView)
        host.layoutSubtreeIfNeeded()
        flushViewportUpdates()
        webView.viewportSizes.removeAll()

        for size in [NSSize(width: 987, height: 712), NSSize(width: 961, height: 701)] {
            let previousViewport = webView.frame
            // Reproduce the two layouts seen in the user's trace: the split
            // view's minimum-size measurement, followed by its real allocation.
            host.frame.size = NSSize(width: 250.5, height: 386)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(webView.frame, previousViewport)

            host.frame.size = size
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(webView.frame, previousViewport)
            flushViewportUpdates(mode: .eventTracking)
            XCTAssertEqual(webView.frame.size, size)
        }

        XCTAssertEqual(webView.viewportSizes, [
            NSSize(width: 987, height: 712),
            NSSize(width: 961, height: 701),
        ])
    }

    @MainActor
    func testReattachingCanvasIgnoresPendingUpdatesFromPreviousHost() async {
        let firstHost = ExcalidrawCanvasHostView(
            frame: NSRect(x: 0, y: 0, width: 250, height: 400)
        )
        let secondHost = ExcalidrawCanvasHostView(
            frame: NSRect(x: 0, y: 0, width: 1200, height: 850)
        )
        let webView = makeWebView()
        firstHost.attach(webView)
        firstHost.layoutSubtreeIfNeeded()

        secondHost.attach(webView)
        // SwiftUI may dismantle the old host after creating the replacement.
        firstHost.detach()
        secondHost.layoutSubtreeIfNeeded()
        flushViewportUpdates()
        XCTAssertTrue(webView.superview === secondHost)
        XCTAssertEqual(webView.frame, secondHost.bounds)
        XCTAssertTrue(firstHost.constraints.isEmpty)
    }

    @MainActor
    func testDisabledOrDetachedCanvasDoesNotLeaveAnInteractiveHost() async {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let host = ExcalidrawCanvasHostView(frame: root.bounds)
        root.addSubview(host)
        let webView = makeWebView()
        host.attach(webView)
        host.layoutSubtreeIfNeeded()
        flushViewportUpdates()

        let point = NSPoint(x: 400, y: 300)
        XCTAssertNotNil(host.hitTest(point))

        webView.updateNativeInteraction(enabled: false)
        // Input stops immediately, while AppKit visibility waits until the
        // representable's current SwiftUI update has finished.
        XCTAssertFalse(webView.nativeInteractionEnabled)
        XCTAssertFalse(webView.isHidden)
        XCTAssertNil(host.hitTest(point))

        flushViewportUpdates()
        XCTAssertTrue(webView.isHidden)

        host.detach()
        XCTAssertNil(host.hitTest(point))
    }

    @MainActor
    func testPendingVisibilityUpdateUsesTheLatestInteractionState() async {
        let webView = makeWebView()

        webView.updateNativeInteraction(enabled: false)
        webView.updateNativeInteraction(enabled: true)
        flushViewportUpdates()
        XCTAssertFalse(webView.isHidden)

        webView.updateNativeInteraction(enabled: false)
        flushViewportUpdates()
        XCTAssertTrue(webView.isHidden)

        webView.updateNativeInteraction(enabled: true)
        webView.updateNativeInteraction(enabled: false)
        flushViewportUpdates()
        XCTAssertTrue(webView.isHidden)

        webView.updateNativeInteraction(enabled: true)
        flushViewportUpdates()
        XCTAssertFalse(webView.isHidden)
    }

    @MainActor
    private func flushViewportUpdates(mode: RunLoop.Mode = .default) {
        _ = RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: 0.01))
    }

    @MainActor
    private func makeWebView() -> ExcalidrawWebView {
        ExcalidrawWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration(),
            toolbarActionHandler: { _ in }
        )
    }
}

@MainActor
private final class RecordingWebView: ExcalidrawWebView {
    var viewportSizes: [NSSize] = []

    override var frame: NSRect {
        didSet {
            if frame.size != oldValue.size { viewportSizes.append(frame.size) }
        }
    }
}
#endif
