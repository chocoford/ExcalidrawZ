#if os(macOS)
import Foundation
import Logging

@MainActor
final class ScreenAnnotationSaveTaskManager {
    static let shared = ScreenAnnotationSaveTaskManager()

    private let logger = Logger(label: "ScreenAnnotationSaveTaskManager")
    private var pendingTask: Task<Void, Never>?

    private init() {}

    func submit(
        id: String,
        operation: @MainActor @escaping () async throws -> Void
    ) {
        let previousTask = pendingTask
        let queuedAt = Date()
        let taskLogger = logger
        logger.debug("Queued screen annotation save id=\(id)")

        pendingTask = Task { @MainActor in
            await previousTask?.value
            guard !Task.isCancelled else { return }

            let startedAt = Date()
            let queueDuration = Self.milliseconds(from: queuedAt, to: startedAt)
            taskLogger.debug(
                "Started screen annotation save id=\(id) queueMs=\(queueDuration)"
            )

            do {
                try await operation()
                let duration = Self.milliseconds(from: startedAt)
                taskLogger.info(
                    "Finished screen annotation save id=\(id) durationMs=\(duration)"
                )
            } catch is CancellationError {
                taskLogger.debug("Cancelled screen annotation save id=\(id)")
            } catch {
                let duration = Self.milliseconds(from: startedAt)
                taskLogger.error(
                    "Failed screen annotation save id=\(id) durationMs=\(duration) error=\(error)"
                )
            }
        }
    }

    func waitUntilIdle() async {
        await pendingTask?.value
    }

    private static func milliseconds(
        from start: Date,
        to end: Date = Date()
    ) -> Int {
        Int((end.timeIntervalSince(start) * 1_000).rounded())
    }
}
#endif
