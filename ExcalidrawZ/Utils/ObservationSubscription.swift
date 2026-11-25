import Foundation
import Observation

/// Re-arms Observation for service-level listeners. Delivery occurs on the main
/// actor after a mutation, and unchanged derived values do not trigger work.
@MainActor
final class ObservationSubscription {
    private var observe: (() -> Void)?

    init<Value: Equatable>(
        initial: Bool = true,
        _ value: @escaping @MainActor () -> Value,
        onChange: @escaping @MainActor (Value) -> Void
    ) {
        var previousValue: Value?
        var hasPreviousValue = false
        observe = { [weak self] in
            guard let self, self.observe != nil else { return }
            let nextValue = withObservationTracking {
                value()
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.observe?()
                }
            }
            let shouldDeliver = hasPreviousValue ? previousValue != nextValue : initial
            previousValue = nextValue
            hasPreviousValue = true
            if shouldDeliver {
                onChange(nextValue)
            }
        }
        observe?()
    }

    func cancel() {
        observe = nil
    }
}

@MainActor
func observedValues<Value: Equatable>(
    _ value: @escaping @MainActor () -> Value
) -> AsyncStream<Value> {
    AsyncStream { continuation in
        let subscription = ObservationSubscription(value) {
            continuation.yield($0)
        }
        continuation.onTermination = { _ in
            Task { @MainActor in
                subscription.cancel()
            }
        }
    }
}
