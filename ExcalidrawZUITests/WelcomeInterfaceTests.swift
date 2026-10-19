import XCTest

#if os(iOS) && targetEnvironment(simulator)
import UIKit

final class WelcomeInterfaceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["EXCALIDRAWZ_ISOLATED_UI_TESTS"] == "1" else {
            throw XCTSkip("Run only in a fresh simulator with inspected test identities and data paths.")
        }
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
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

    private func openWelcome(
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
        app.launch()

        let newDrawing = app.buttons["New draw"].firstMatch
        XCTAssertTrue(newDrawing.waitForExistence(timeout: 15))
        newDrawing.tap()

        let chat = app.buttons["AI Chat"].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 15))
        chat.tap()
        XCTAssertTrue(app.buttons["aiChatWelcomePrimaryAction"].waitForExistence(timeout: 5))
        return app
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
