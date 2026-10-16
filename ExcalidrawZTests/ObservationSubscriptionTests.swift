import Observation
import XCTest
@testable import ExcalidrawZ

@MainActor
final class ObservationSubscriptionTests: XCTestCase {
    func testOnlyChangedDerivedValuesAreDelivered() async {
        let state = ObservationSubscriptionFixture()
        var values: [Int] = []
        let changed = expectation(description: "Changed value delivered")
        let subscription = ObservationSubscription { state.primary } onChange: { value in
            values.append(value)
            if value == 2 { changed.fulfill() }
        }

        XCTAssertEqual(values, [0])
        state.secondary = 10
        state.primary = 2
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(values, [0, 2])
        subscription.cancel()
    }

    func testObservationRearmsWhenADependencyChangesWithoutChangingTheResult() async {
        let state = ObservationSubscriptionFixture()
        var values: [Int] = []
        let changed = expectation(description: "New dependency observed")
        let subscription = ObservationSubscription {
            state.useSecondary ? state.secondary : state.primary
        } onChange: { value in
            values.append(value)
            if value == 3 { changed.fulfill() }
        }

        state.useSecondary = true
        await Task.yield()
        await Task.yield()
        state.primary = 7
        state.secondary = 3
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(values, [0, 3])
        subscription.cancel()
    }

    func testCancelPreventsAlreadyQueuedDelivery() async {
        let state = ObservationSubscriptionFixture()
        let unexpected = expectation(description: "Cancelled callback")
        unexpected.isInverted = true
        let subscription = ObservationSubscription(initial: false) {
            state.primary
        } onChange: { _ in
            unexpected.fulfill()
        }

        state.primary = 1
        subscription.cancel()
        await fulfillment(of: [unexpected], timeout: 0.05)
    }

    func testInitialFalseStillObservesSubsequentChanges() async {
        let state = ObservationSubscriptionFixture()
        var values: [Int] = []
        let changed = expectation(description: "Subsequent change delivered")
        let subscription = ObservationSubscription(initial: false) {
            state.primary
        } onChange: { value in
            values.append(value)
            changed.fulfill()
        }

        XCTAssertTrue(values.isEmpty)
        state.primary = 1
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(values, [1])
        subscription.cancel()
    }

    func testQueuedWritesDeliverTheLatestCommittedValue() async {
        let state = ObservationSubscriptionFixture()
        var values: [Int] = []
        let changed = expectation(description: "Latest value delivered")
        let subscription = ObservationSubscription(initial: false) {
            state.primary
        } onChange: { value in
            values.append(value)
            changed.fulfill()
        }

        state.primary = 1
        state.primary = 2
        state.primary = 3
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(values, [3])
        subscription.cancel()
    }

    func testRegistrationDoesNotRetainTheSubscription() {
        let state = ObservationSubscriptionFixture()
        weak var releasedSubscription: ObservationSubscription?
        do {
            let subscription = ObservationSubscription({ state.primary }) { _ in }
            releasedSubscription = subscription
            XCTAssertNotNil(releasedSubscription)
        }
        XCTAssertNil(releasedSubscription)
    }
}

@Observable
private final class ObservationSubscriptionFixture {
    var primary = 0
    var secondary = 0
    var useSecondary = false
}
