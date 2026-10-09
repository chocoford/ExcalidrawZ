import XCTest
@testable import ExcalidrawZ

final class FileHomeSheetPresentationTests: XCTestCase {
    @MainActor
    func testDifferentFileHomesKeepTheirRequestsSeparate() {
        let first = FileHomeSheetPresentation()
        let second = FileHomeSheetPresentation()
        first.activate()
        second.activate()
        first.presentRename(name: "First") { _ in }
        XCTAssertNotNil(first.request)
        XCTAssertNil(second.request)
    }

    @MainActor
    func testPendingRequestWaitsForDismissalToFinish() {
        let presentation = FileHomeSheetPresentation()
        presentation.activate()
        presentation.presentRename(name: "First") { _ in }
        let firstID = presentation.request?.id
        presentation.presentRename(name: "Second") { _ in }
        XCTAssertEqual(presentation.request?.id, firstID)

        presentation.dismissCurrent()
        // An asynchronous recovery can finish during the sheet's dismissal.
        presentation.presentRename(name: "Third") { _ in }
        XCTAssertNil(presentation.request)
        presentation.didDismiss()
        guard case .rename(let secondName, _) = presentation.request?.content else {
            return XCTFail("Missing queued request")
        }
        XCTAssertEqual(secondName, "Second")
        presentation.dismissCurrent()
        presentation.didDismiss()
        guard case .rename(let thirdName, _) = presentation.request?.content else {
            return XCTFail("Missing request received during dismissal")
        }
        XCTAssertEqual(thirdName, "Third")
    }

    @MainActor
    func testLeavingFileHomeReleasesPendingCallbacksAndRejectsLateRequests() {
        final class LifetimeToken {}
        let presentation = FileHomeSheetPresentation()
        presentation.activate()
        weak var weakToken: LifetimeToken?
        do {
            let token = LifetimeToken()
            weakToken = token
            presentation.presentRename(name: "First") { _ in }
            presentation.presentRename(name: "Second") { [token] _ in
                withExtendedLifetime(token) {}
            }
        }
        XCTAssertNotNil(weakToken)
        presentation.deactivate()
        XCTAssertNil(weakToken)
        XCTAssertNil(presentation.request)
        presentation.presentRename(name: "Late") { _ in }
        presentation.didDismiss()
        XCTAssertNil(presentation.request)

        presentation.activate()
        presentation.presentRename(name: "New") { _ in }
        guard case .rename(let name, _) = presentation.request?.content else {
            return XCTFail("File home did not resume presentations")
        }
        XCTAssertEqual(name, "New")
    }
}
