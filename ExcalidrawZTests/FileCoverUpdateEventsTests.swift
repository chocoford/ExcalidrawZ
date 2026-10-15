import Combine
import XCTest
@testable import ExcalidrawZ

final class FileCoverUpdateEventsTests: XCTestCase {
    @MainActor
    func testPreviewUpdateReachesOnlyMatchingFileIncludingMultipleCovers() async {
        let center = NotificationCenter()
        let events = FileCoverUpdateEvents(notificationCenter: center)
        let delivered = expectation(description: "Both covers of the matching file")
        delivered.expectedFulfillmentCount = 2
        var otherEvents = 0
        let first = events.publisher(for: "first").sink { event in
            XCTAssertEqual(event, .imageUpdated)
            delivered.fulfill()
        }
        let second = events.publisher(for: "first").sink { event in
            XCTAssertEqual(event, .imageUpdated)
            delivered.fulfill()
        }
        let other = events.publisher(for: "other").sink { _ in otherEvents += 1 }
        center.post(name: .filePreviewDidUpdate, object: String(["f", "irst"].joined()))
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(otherEvents, 0)
        withExtendedLifetime([first, second, other]) {}
    }

    @MainActor
    func testRefreshRequestFromBackgroundThreadIsDeliveredOnMainThread() async {
        let center = NotificationCenter()
        let events = FileCoverUpdateEvents(notificationCenter: center)
        let delivered = expectation(description: "Refresh on main thread")
        let subscription = events.publisher(for: "file").sink { event in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(event, .refreshRequested)
            delivered.fulfill()
        }
        DispatchQueue.global().async {
            center.post(name: .filePreviewShouldRefresh, object: "file")
        }
        await fulfillment(of: [delivered], timeout: 1)
        withExtendedLifetime(subscription) {}
    }
}
