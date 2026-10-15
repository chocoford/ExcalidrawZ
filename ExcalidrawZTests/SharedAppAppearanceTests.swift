import XCTest
@testable import ExcalidrawZ

final class SharedAppAppearanceTests: XCTestCase {
    func testExplicitCanvasAppearanceOverridesAppAppearance() {
        let appAppearances: [SharedAppAppearance] = [.light, .dark, .auto]
        for canvas in [SharedAppAppearance.light, .dark] {
            for app in appAppearances {
                XCTAssertEqual(
                    SharedAppAppearance.resolve(canvas: canvas, app: app),
                    canvas
                )
            }
        }
    }

    func testAutomaticCanvasAppearanceFallsBackToAppAndThenSystem() {
        let appAppearances: [SharedAppAppearance] = [.light, .dark, .auto]
        for app in appAppearances {
            XCTAssertEqual(
                SharedAppAppearance.resolve(canvas: .auto, app: app),
                app
            )
        }
    }
}
