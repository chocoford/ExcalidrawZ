import Foundation

/// Suspends excess callers without allocating a Core Data context or blocking
/// a Dispatch worker. Duplicate keys share work, but retain separate cancellation.
actor LinkedFolderRefreshQueue<Key: Hashable & Sendable, Value: Sendable> {
    private final class Job {
        let id = UUID()
        var operation: @Sendable () async throws -> Value
        var nextOperation: (@Sendable () async throws -> Value)?
        var waiters: [UUID: CheckedContinuation<Value, Error>] = [:]
        var nextWaiters: [UUID: CheckedContinuation<Value, Error>] = [:]
        var task: Task<Void, Never>?

        init(operation: @escaping @Sendable () async throws -> Value) { self.operation = operation }
    }

    private let maximumConcurrent: Int
    private var jobs: [Key: Job] = [:]
    private var pending: [(Key, UUID)] = []
    private var pendingOffset = 0
    private var running: Set<UUID> = []

    init(maximumConcurrent: Int = 1) { self.maximumConcurrent = max(1, maximumConcurrent) }

    func run(key: Key, requiresFreshResult: Bool = false,
             operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let job: Job
                if let existing = jobs[key] {
                    job = existing
                } else {
                    job = Job(operation: operation)
                    jobs[key] = job
                    pending.append((key, job.id))
                }
                if requiresFreshResult, job.task != nil {
                    // An invalidation arriving during a scan needs a later
                    // snapshot; joining the old scan would lose that change.
                    job.nextWaiters[waiter] = continuation
                    job.nextOperation = operation
                } else {
                    job.waiters[waiter] = continuation
                }
                drain()
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiter, key: key) }
        }
    }

    func cancel(keys: [Key]) {
        for key in keys {
            guard let job = jobs.removeValue(forKey: key) else { continue }
            job.task?.cancel()
            for waiter in job.waiters.values { waiter.resume(throwing: CancellationError()) }
            for waiter in job.nextWaiters.values { waiter.resume(throwing: CancellationError()) }
            job.waiters.removeAll()
            job.nextWaiters.removeAll()
        }
        drain()
    }

    private func cancelWaiter(_ waiterID: UUID, key: Key) {
        guard let job = jobs[key],
              let waiter = job.waiters.removeValue(forKey: waiterID) ?? job.nextWaiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(throwing: CancellationError())
        if job.waiters.isEmpty && job.nextWaiters.isEmpty {
            jobs.removeValue(forKey: key)
            job.task?.cancel()
        }
        drain()
    }

    private func drain() {
        while running.count < maximumConcurrent, pendingOffset < pending.count {
            let (key, id) = pending[pendingOffset]
            pendingOffset += 1
            guard let job = jobs[key], job.id == id, job.task == nil else { continue }
            running.insert(id)
            let operation = job.operation
            job.task = Task { [weak self] in
                let result: Result<Value, Error>
                do {
                    try Task.checkCancellation()
                    result = .success(try await operation())
                } catch { result = .failure(error) }
                await self?.finished(key: key, id: id, result: result)
            }
        }
        if pendingOffset == pending.count {
            pending.removeAll(keepingCapacity: true)
            pendingOffset = 0
        } else if pendingOffset > 512, pendingOffset > pending.count / 2 {
            pending.removeFirst(pendingOffset)
            pendingOffset = 0
        }
    }

    private func finished(key: Key, id: UUID, result: Result<Value, Error>) {
        // Cancellation must not free a slot until the underlying operation has
        // really exited. It may still be unwinding a Core Data perform block.
        running.remove(id)
        if let job = jobs[key], job.id == id {
            for waiter in job.waiters.values { waiter.resume(with: result) }
            job.waiters.removeAll()
            if !job.nextWaiters.isEmpty {
                job.waiters = job.nextWaiters
                job.nextWaiters.removeAll()
                if let next = job.nextOperation { job.operation = next }
                job.nextOperation = nil
                job.task = nil
                pending.append((key, id))
            } else {
                jobs.removeValue(forKey: key)
            }
        }
        drain()
    }
}
