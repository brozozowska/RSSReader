import Foundation

nonisolated struct AsyncTestTimeout: Error, CustomStringConvertible {
    let description: String
}

/// Poll only an observable condition; timeout always fails the awaiting test.
@MainActor
func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(5),
    condition: () async throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while true {
        try Task.checkCancellation()
        if try await condition() { return }
        guard ContinuousClock.now < deadline else {
            throw AsyncTestTimeout(description: "Timed out waiting for \(description)")
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// A one-shot gate. Every waiter is removed on release, timeout, or cancellation.
/// Stale-result fixtures may explicitly ignore cancellation, but still have a watchdog.
nonisolated final class AsyncTestGate: @unchecked Sendable {
    private struct Waiter {
        let continuation: CheckedContinuation<Void, Error>
        var watchdog: Task<Void, Never>?
    }

    private let lock = NSLock()
    private var released = false
    private var waiters: [UUID: Waiter] = [:]

    var waiterCount: Int { lock.withLock { waiters.count } }

    func wait(
        _ description: String = "test gate release",
        timeout: Duration = .seconds(5),
        honorsCancellation: Bool = true
    ) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    if honorsCancellation && Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if released {
                        continuation.resume()
                    } else {
                        waiters[id] = Waiter(continuation: continuation)
                    }
                }
                let watchdog = Task.detached { [self] in
                    do {
                        try await Task.sleep(for: timeout)
                        finish(id, result: .failure(AsyncTestTimeout(
                            description: "Timed out waiting for \(description)"
                        )))
                    } catch {}
                }
                lock.withLock {
                    if waiters[id] != nil {
                        waiters[id]?.watchdog = watchdog
                    } else {
                        watchdog.cancel()
                    }
                }
            }
        } onCancel: {
            if honorsCancellation {
                self.finish(id, result: .failure(CancellationError()))
            }
        }
    }

    func release() {
        let pending = lock.withLock {
            released = true
            let pending = Array(waiters.values)
            waiters.removeAll()
            return pending
        }
        for waiter in pending {
            waiter.watchdog?.cancel()
            waiter.continuation.resume()
        }
    }

    private func finish(_ id: UUID, result: Result<Void, Error>) {
        guard let waiter = lock.withLock({ waiters.removeValue(forKey: id) }) else { return }
        waiter.watchdog?.cancel()
        waiter.continuation.resume(with: result)
    }
}

/// One consumer per stream. Requesting the next element acknowledges that the
/// consumer's previous loop body has returned, rather than merely dequeuing it.
actor AcknowledgedTestEventIterator<Event: Sendable> {
    private var iterator: AsyncStream<Event>.Iterator
    private var deliveredCount = 0
    private(set) var processedCount = 0

    init(stream: AsyncStream<Event>) { iterator = stream.makeAsyncIterator() }

    func next() async -> Event? {
        processedCount = deliveredCount
        var current = iterator
        let event = await current.next()
        iterator = current
        if event != nil { deliveredCount += 1 }
        return event
    }
}

nonisolated final class AcknowledgedTestEventSource<Event: Sendable>: @unchecked Sendable {
    private struct Subscription {
        let continuation: AsyncStream<Event>.Continuation
        let iterator: AcknowledgedTestEventIterator<Event>
        var yieldedCount = 0
    }
    private let lock = NSLock()
    private var subscriptions: [UUID: Subscription] = [:]

    var subscriberCount: Int { lock.withLock { subscriptions.count } }

    func events() -> AsyncStream<Event> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        let iterator = AcknowledgedTestEventIterator(stream: stream)
        lock.withLock { subscriptions[id] = Subscription(continuation: continuation, iterator: iterator) }
        continuation.onTermination = { [weak self] _ in
            _ = self?.lock.withLock { self?.subscriptions.removeValue(forKey: id) }
        }
        return AsyncStream(unfolding: { await iterator.next() }, onCancel: { continuation.finish() })
    }

    private func publishSubscriptions() -> [Subscription] {
        lock.withLock {
            for id in subscriptions.keys { subscriptions[id]?.yieldedCount += 1 }
            return Array(subscriptions.values)
        }
    }

    func yield(_ event: Event) {
        let active = publishSubscriptions()
        for subscription in active { subscription.continuation.yield(event) }
    }

    @MainActor
    func yieldAndWait(_ event: Event) async throws {
        let active = publishSubscriptions()
        for subscription in active { subscription.continuation.yield(event) }
        for subscription in active {
            try await waitUntil("event consumer completed loop body") {
                await subscription.iterator.processedCount >= subscription.yieldedCount
            }
        }
    }
}
