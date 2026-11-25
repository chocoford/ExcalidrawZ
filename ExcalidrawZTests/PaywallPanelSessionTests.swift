import XCTest
@testable import ExcalidrawZ

final class PaywallPanelSessionTests: XCTestCase {
    private func losesFocus(_ session: PaywallPanelSession) -> Bool {
        session.shouldDismiss(isApplicationActive: true, keyWindowBelongsToPanel: false, hasAttachedSheet: false)
    }

    func testOrdinaryFocusLossAndAppDeactivationDismiss() {
        var session = PaywallPanelSession()
        _ = session.begin()
        XCTAssertTrue(losesFocus(session))
        XCTAssertTrue(session.shouldDismiss(isApplicationActive: false, keyWindowBelongsToPanel: true, hasAttachedSheet: false))
        XCTAssertFalse(session.shouldDismiss(isApplicationActive: true, keyWindowBelongsToPanel: true, hasAttachedSheet: false))
    }

    func testPurchaseConfirmationSurvivesAppDeactivationUntilTheOperationEnds() {
        var session = PaywallPanelSession()
        let id = session.begin()
        session.updateProtection(true, for: id)
        XCTAssertFalse(session.shouldDismiss(isApplicationActive: false, keyWindowBelongsToPanel: false, hasAttachedSheet: false))
        session.updateProtection(false, for: id)
        XCTAssertTrue(losesFocus(session))
    }

    func testReturningFromPurchaseToThePanelKeepsItOpen() {
        var session = PaywallPanelSession()
        let id = session.begin()
        session.updateProtection(true, for: id)
        session.updateProtection(false, for: id)
        XCTAssertFalse(session.shouldDismiss(isApplicationActive: true, keyWindowBelongsToPanel: true, hasAttachedSheet: false))
    }

    func testOverlappingRestoreAndPurchaseBothHaveToFinish() {
        var session = PaywallPanelSession()
        let id = session.begin()
        session.updateProtection(true, for: id)
        session.updateProtection(true, for: id)
        session.updateProtection(false, for: id)
        XCTAssertFalse(losesFocus(session))
        session.updateProtection(false, for: id)
        XCTAssertTrue(losesFocus(session))
    }

    func testOwnedPopoverAndSystemSheetDoNotDismissThePanel() {
        var session = PaywallPanelSession()
        _ = session.begin()
        XCTAssertFalse(session.shouldDismiss(isApplicationActive: true, keyWindowBelongsToPanel: true, hasAttachedSheet: false))
        XCTAssertFalse(session.shouldDismiss(isApplicationActive: true, keyWindowBelongsToPanel: false, hasAttachedSheet: true))
        XCTAssertFalse(session.shouldDismiss(isApplicationActive: false, keyWindowBelongsToPanel: false, hasAttachedSheet: true))
    }

    func testOldCloseCallbackCannotCloseANewPresentation() {
        var session = PaywallPanelSession()
        let oldID = session.begin()
        XCTAssertTrue(session.end(oldID))
        let newID = session.begin()
        XCTAssertFalse(session.end(oldID))
        XCTAssertEqual(session.id, newID)
    }

    func testOldPurchaseCompletionCannotReleaseProtectionForTheNewPanel() {
        var session = PaywallPanelSession()
        let oldID = session.begin()
        session.updateProtection(true, for: oldID)
        XCTAssertTrue(session.end(oldID))
        let newID = session.begin()
        session.updateProtection(true, for: newID)
        session.updateProtection(false, for: oldID)
        XCTAssertFalse(losesFocus(session))
        session.updateProtection(false, for: newID)
        XCTAssertTrue(losesFocus(session))
    }

    func testClosedPanelIgnoresLateFocusEvents() {
        var session = PaywallPanelSession()
        let id = session.begin()
        XCTAssertTrue(session.end(id))
        XCTAssertFalse(losesFocus(session))
        XCTAssertFalse(session.end(id))
    }
}
