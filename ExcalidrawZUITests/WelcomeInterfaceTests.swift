import XCTest

#if os(iOS) && targetEnvironment(simulator)
import UIKit

final class WelcomeInterfaceTests: XCTestCase {
    private var launchedApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["EXCALIDRAWZ_ISOLATED_UI_TESTS"] == "1" else {
            throw XCTSkip("Run only in a fresh simulator with inspected test identities and data paths.")
        }
    }

    override func tearDownWithError() throws {
        if let launchedApp {
            launchedApp.terminate()
            XCUIDevice.shared.orientation = .portrait
            self.launchedApp = nil
        }
    }

    func testCancelConsentKeepsAIWelcomeAndRequiresConsentAgain() {
        let app = openWelcome(orientation: .landscapeLeft)
        let primaryAction = app.buttons["aiChatWelcomePrimaryAction"]
        XCTAssertTrue(primaryAction.isHittable)

        primaryAction.tap()
        assertConsentIsRequired(in: app)
        app.buttons["Cancel"].tap()

        XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Send message"].exists)
        primaryAction.tap()
        assertConsentIsRequired(in: app)
    }

    func testLargeTextCanScrollDetailsAndReturnToActionInBothOrientations() {
        let app = openWelcome(orientation: .landscapeLeft, largeText: true)
        let scrollView = app.scrollViews["aiChatWelcomeScrollView"]
        let primaryAction = app.buttons["aiChatWelcomePrimaryAction"]
        let details = app.buttons["aiChatWelcomeDetails"]

        scrollTo(details, in: scrollView, towardBottom: true)
        details.tap()

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let lastFeature = app.descendants(matching: .any)["aiChatWelcomeRevertFeature"].firstMatch
            scrollTo(lastFeature, in: scrollView, towardBottom: true)
            XCTAssertTrue(lastFeature.isHittable)

            scrollTo(primaryAction, in: scrollView, towardBottom: false)
            XCTAssertTrue(primaryAction.isHittable)
        }

        primaryAction.tap()
        assertConsentIsRequired(in: app)
    }

    func testPresentationWelcomePlanAndActionRemainReachableAtLargeText() {
        let app = openDrawing(orientation: .landscapeLeft, largeText: true)
        let presentation = app.buttons["Presentation"].firstMatch
        XCTAssertTrue(presentation.waitForExistence(timeout: 15))
        presentation.tap()

        let scrollView = app.scrollViews["presentationWelcomeScrollView"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        let planCaption = app.staticTexts["presentationWelcomePlanCaption"]
        let primaryAction = app.buttons["presentationWelcomePrimaryAction"]

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            scrollTo(planCaption, in: scrollView, towardBottom: true)
            scrollTo(primaryAction, in: scrollView, towardBottom: false)
        }
    }

    private func openWelcome(
        orientation: UIDeviceOrientation,
        largeText: Bool = false
    ) -> XCUIApplication {
        let app = openDrawing(orientation: orientation, largeText: largeText)
        let chat = app.buttons["AI Chat"].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 15))
        chat.tap()
        XCTAssertTrue(app.buttons["aiChatWelcomePrimaryAction"].waitForExistence(timeout: 5))
        return app
    }

    private func openDrawing(
        orientation: UIDeviceOrientation,
        largeText: Bool = false
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AIChat.isEnabled", "NO",
            "-DisableCloudSync", "YES",
            "-WhatsNewLastBuild", "999999"
        ]
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
        launchedApp = app
        app.launch()
        dismissStartupSheet(in: app)

        let newDrawing = app.buttons["New draw"].firstMatch
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: newDrawing
        )
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        newDrawing.tap()
        return app
    }

    private func dismissStartupSheet(in app: XCUIApplication) {
        // Debug builds show What's New even when WhatsNewLastBuild is current.
        let whatsNew = app.navigationBars.matching(
            NSPredicate(format: "identifier IN %@", ["What's New", "What’s New in ExcalidrawZ"])
        ).firstMatch
        if whatsNew.waitForExistence(timeout: 5) {
            whatsNew.buttons.firstMatch.tap()
            let dismissed = NSPredicate(format: "exists == false")
            expectation(for: dismissed, evaluatedWith: whatsNew)
            waitForExpectations(timeout: 5)
        }
    }

    private func assertConsentIsRequired(in app: XCUIApplication) {
        let enable = app.buttons["Enable AI"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        XCTAssertFalse(enable.isEnabled)
    }

    private func scrollTo(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        towardBottom: Bool
    ) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if towardBottom {
                scrollView.swipeUp()
            } else {
                scrollView.swipeDown()
            }
        }
        XCTAssertTrue(element.isHittable, "Welcome content must remain reachable by scrolling.")
    }
}
#endif
