import Observation
import SwiftUI
import XCTest
import os
@testable import ExcalidrawZ

final class LayoutStateTests: XCTestCase {
    func testInspectorTogglesPreserveTheSelectedTab() {
        let state = LayoutState()
        state.toggleInspector(.history)
        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertEqual(state.activeInspectorTab, .history)

        state.toggleInspector(.history)
        XCTAssertFalse(state.isInspectorPresented)
        XCTAssertEqual(state.activeInspectorTab, .history)

        state.toggleInspector()
        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertEqual(state.activeInspectorTab, .history)

        state.toggleInspector(.library)
        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertEqual(state.activeInspectorTab, .library)
    }

    func testOpeningAIInspectorClosesAndResetsCompactChat() {
        let state = LayoutState()
        state.enterCompactAIChatToolbar()
        state.isCompactAIChatInputEditing = true
        state.isCompactAIChatAttachmentPickerPresented = true
        state.isCompactAIChatReplyTickerVisible = true
        state.isCompactAIChatReplyStartPending = true

        state.activeInspectorTab = .aiChat
        XCTAssertTrue(state.isCompactAIChatToolbarPresented)
        state.isInspectorPresented = true

        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertFalse(state.isCompactAIChatToolbarPresented)
        XCTAssertFalse(state.isCompactAIChatInputEditing)
        XCTAssertFalse(state.isCompactAIChatAttachmentPickerPresented)
        XCTAssertFalse(state.isCompactAIChatReplyTickerVisible)
        XCTAssertFalse(state.isCompactAIChatReplyStartPending)
    }

    func testSwitchingAnOpenInspectorToAIClosesTheIsland() {
        let state = LayoutState()
        state.toggleInspector(.library)
        state.enterAIChatIsland()
        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertTrue(state.isAIChatIslandMode)

        state.activeInspectorTab = .aiChat

        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertFalse(state.isAIChatIslandMode)

        state.enterAIChatIsland()
        XCTAssertFalse(state.isInspectorPresented)
        XCTAssertTrue(state.isAIChatIslandMode)

        state.exitAIChatIsland()
        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertEqual(state.activeInspectorTab, .aiChat)
        XCTAssertFalse(state.isAIChatIslandMode)
    }

    func testTrackingIgnoresUnrelatedPropertiesAndOtherWindows() {
        let state = LayoutState()
        let otherWindow = LayoutState()
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = state.compactBrowserLayout
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        state.toggleInspector(.library)
        state.aiChatIslandOffset = CGSize(width: 20, height: 40)
        otherWindow.compactBrowserLayout = .list
        XCTAssertEqual(changes.withLock { $0 }, 0)
        XCTAssertEqual(state.compactBrowserLayout, .grid)

        state.compactBrowserLayout = .list
        XCTAssertEqual(changes.withLock { $0 }, 1)
    }

    func testInspectorChangesInvalidateTheObservedProperty() {
        let state = LayoutState()
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = state.isInspectorPresented
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        state.toggleInspector(.aiChat)

        XCTAssertTrue(state.isInspectorPresented)
        XCTAssertEqual(changes.withLock { $0 }, 1)
    }

    func testBindingsWriteThroughToTheTrackedState() {
        let state = LayoutState()
        let bindings = Bindable(state)
        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = state.compactBrowserLayout
        } onChange: {
            changes.withLock { $0 += 1 }
        }

        bindings.compactBrowserLayout.wrappedValue = .list

        XCTAssertEqual(state.compactBrowserLayout, .list)
        XCTAssertEqual(changes.withLock { $0 }, 1)
    }
}
