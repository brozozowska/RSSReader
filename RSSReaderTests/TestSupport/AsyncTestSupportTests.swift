import Foundation
import Testing
@testable import RSSReader

@Suite("Test Support / Async Synchronization")
@MainActor
struct AsyncTestSupportTests {
    @Test
    func releaseBeforeEntryAndRepeatedReleaseDoNotSuspend() async throws {
        let gate = AsyncTestGate()
        gate.release()
        gate.release()
        try await gate.wait()
        #expect(gate.waiterCount == 0)
    }

    @Test
    func releaseResumesAllSuspendedWaiters() async throws {
        let gate = AsyncTestGate()
        let first = Task { try await gate.wait() }
        let second = Task { try await gate.wait() }
        defer { gate.release(); first.cancel(); second.cancel() }
        try await waitUntil("both gate waiters entered") { gate.waiterCount == 2 }
        gate.release()
        try await first.value
        try await second.value
        #expect(gate.waiterCount == 0)
    }

    @Test
    func cancellationResumesWaiterWithoutAnExternalRelease() async throws {
        let gate = AsyncTestGate()
        let pending = Task { try await gate.wait() }
        defer { pending.cancel(); gate.release() }
        try await waitUntil("cancellable gate entered") { gate.waiterCount == 1 }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(gate.waiterCount == 0)
        gate.release()
    }

    @Test
    func cancellationBeforeEntryDoesNotLeaveAContinuation() async throws {
        let gate = AsyncTestGate()
        let pending = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await gate.wait()
        }
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(gate.waiterCount == 0)
    }

    @Test
    func watchdogFailsWithDescriptionAndRemovesWaiter() async throws {
        let gate = AsyncTestGate()
        do {
            try await gate.wait("controlled missing completion", timeout: .milliseconds(20))
            Issue.record("Expected gate timeout")
        } catch let error as AsyncTestTimeout {
            #expect(error.description.contains("controlled missing completion"))
        }
        #expect(gate.waiterCount == 0)
        gate.release()
    }

    @Test
    func staleResultFixtureWaitsForExplicitCompletionAfterCancellation() async throws {
        let gate = AsyncTestGate()
        let pending = Task { try await gate.wait(honorsCancellation: false) }
        defer { pending.cancel(); gate.release() }
        try await waitUntil("stale fixture entered") { gate.waiterCount == 1 }
        pending.cancel()
        #expect(gate.waiterCount == 1)
        gate.release()
        try await pending.value
        #expect(gate.waiterCount == 0)
    }

    @Test
    func boundedConditionTimeoutThrowsInsteadOfReturningSuccess() async throws {
        await #expect(throws: AsyncTestTimeout.self) {
            try await waitUntil("condition never becomes true", timeout: .milliseconds(20)) { false }
        }
    }

    @Test
    func transportGateCancellationReleasesSuspension() async throws {
        let gate = ScriptedHTTPClientResponseGate()
        let pending = Task { try await gate.enterAndWaitForRelease() }
        defer { pending.cancel() }
        try await waitUntil("transport gate entered") { await gate.suspendedWaiterCount() == 1 }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(await gate.suspendedWaiterCount() == 0)
        await gate.release()
    }

    @Test
    func delayedTransportCancellationKeepsGateUntilExplicitRelease() async throws {
        let gate = ScriptedHTTPClientResponseGate(honorsCancellation: false)
        let pending = Task { try await gate.enterAndWaitForRelease() }
        defer { pending.cancel() }
        try await waitUntil("delayed transport gate entered") { await gate.suspendedWaiterCount() == 1 }
        pending.cancel()
        #expect(await gate.suspendedWaiterCount() == 1)
        await gate.release()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(await gate.suspendedWaiterCount() == 0)
    }

    @Test
    func eventAcknowledgementWaitsForConsumerBodyCompletion() async throws {
        let source = AcknowledgedTestEventSource<Int>()
        let events = source.events()
        let bodyGate = AsyncTestGate()
        var processed: [Int] = []
        var acknowledged = false
        let consumer = Task {
            for await event in events {
                try await bodyGate.wait()
                processed.append(event)
            }
        }
        let delivery = Task {
            try await source.yieldAndWait(7)
            acknowledged = true
        }
        defer { bodyGate.release(); delivery.cancel(); consumer.cancel() }
        try await waitUntil("consumer body suspended") { bodyGate.waiterCount == 1 }
        #expect(acknowledged == false)
        #expect(processed.isEmpty)
        bodyGate.release()
        try await delivery.value
        #expect(processed == [7])
        #expect(acknowledged)
        consumer.cancel()
        try await consumer.value
        #expect(source.subscriberCount == 0)
    }
}
