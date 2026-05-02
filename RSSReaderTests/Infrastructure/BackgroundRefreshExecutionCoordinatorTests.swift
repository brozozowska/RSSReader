import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Execution Coordinator")
@MainActor
struct BackgroundRefreshExecutionCoordinatorTests {
    @Test
    func backgroundRefreshExecutionCoordinatorReturnsFinishedOutcomeForCompletedRefresh() async {
        let expectedResult = BackgroundFeedRefreshResult(
            batchResult: FeedRefreshBatchResult(
                startedAt: .distantPast,
                finishedAt: .distantPast.addingTimeInterval(5),
                results: []
            )
        )
        let backgroundRefreshService = CompletedBackgroundRefreshServiceSpy(result: expectedResult)
        let dependencies = AppDependencies(
            logger: TestLogger(),
            backgroundRefreshService: backgroundRefreshService
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: dependencies)

        let outcome = await coordinator.executeAppRefresh()

        #expect(backgroundRefreshService.performScheduledRefreshCallCount == 1)
        switch outcome {
        case .finished(let result):
            #expect(result?.trigger == .background)
            #expect(result?.duration == 5)
        case .cancelled:
            Issue.record("Expected finished execution outcome")
        }
    }

    @Test
    func backgroundRefreshExecutionCoordinatorCancelsRefreshTaskWhenParentTaskIsCancelled() async {
        let backgroundRefreshService = CancellableBackgroundRefreshServiceSpy()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            backgroundRefreshService: backgroundRefreshService
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: dependencies)

        let task = Task { @MainActor in
            await coordinator.executeAppRefresh()
        }

        await Task.yield()
        task.cancel()
        let outcome = await task.value

        #expect(backgroundRefreshService.performScheduledRefreshCallCount == 1)
        #expect(backgroundRefreshService.observedCancellation)
        switch outcome {
        case .finished:
            Issue.record("Expected cancelled execution outcome")
        case .cancelled(let result):
            #expect(result == nil)
        }
    }
}

@MainActor
private final class CompletedBackgroundRefreshServiceSpy: BackgroundRefreshService {
    private(set) var performScheduledRefreshCallCount = 0
    private let result: BackgroundFeedRefreshResult?

    init(result: BackgroundFeedRefreshResult?) {
        self.result = result
    }

    func loadConfiguration() throws -> BackgroundRefreshConfiguration {
        Issue.record("loadConfiguration() should not be used in this test")
        throw BackgroundRefreshExecutionCoordinatorTestError.unexpectedInvocation
    }

    func updatePreference(
        _ preference: RefreshPreference,
        updatedAt: Date
    ) throws -> BackgroundRefreshConfiguration {
        Issue.record("updatePreference(_:updatedAt:) should not be used in this test")
        throw BackgroundRefreshExecutionCoordinatorTestError.unexpectedInvocation
    }

    func performScheduledRefresh() async -> BackgroundFeedRefreshResult? {
        performScheduledRefreshCallCount += 1
        return result
    }
}

@MainActor
private final class CancellableBackgroundRefreshServiceSpy: BackgroundRefreshService {
    private(set) var performScheduledRefreshCallCount = 0
    private(set) var observedCancellation = false

    func loadConfiguration() throws -> BackgroundRefreshConfiguration {
        Issue.record("loadConfiguration() should not be used in this test")
        throw BackgroundRefreshExecutionCoordinatorTestError.unexpectedInvocation
    }

    func updatePreference(
        _ preference: RefreshPreference,
        updatedAt: Date
    ) throws -> BackgroundRefreshConfiguration {
        Issue.record("updatePreference(_:updatedAt:) should not be used in this test")
        throw BackgroundRefreshExecutionCoordinatorTestError.unexpectedInvocation
    }

    func performScheduledRefresh() async -> BackgroundFeedRefreshResult? {
        performScheduledRefreshCallCount += 1

        do {
            try await Task.sleep(for: .seconds(60))
            return nil
        } catch is CancellationError {
            observedCancellation = true
            return nil
        } catch {
            Issue.record("Unexpected error while waiting for cancellation: \(error)")
            return nil
        }
    }
}

private enum BackgroundRefreshExecutionCoordinatorTestError: Error {
    case unexpectedInvocation
}
