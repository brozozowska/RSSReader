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
        case .success(let result):
            #expect(result.trigger == .background)
            #expect(result.duration == 5)
        case .partialFailure, .totalFailure, .skippedManual, .failedToStart, .cancelled:
            Issue.record("Expected success execution outcome")
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
        case .success, .partialFailure, .totalFailure, .skippedManual, .failedToStart:
            Issue.record("Expected cancelled execution outcome")
        case .cancelled(let result):
            #expect(result == nil)
        }
    }

    @Test
    func backgroundRefreshExecutionCoordinatorReturnsSkippedManualOutcome() async {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )
        let backgroundRefreshService = PrecomputedBackgroundRefreshServiceSpy(
            result: .skippedManual(configuration)
        )
        let dependencies = AppDependencies(
            logger: TestLogger(),
            backgroundRefreshService: backgroundRefreshService
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: dependencies)

        let outcome = await coordinator.executeAppRefresh()

        switch outcome {
        case .skippedManual(let resolvedConfiguration):
            #expect(resolvedConfiguration.policy.preference == .manual)
        case .success, .partialFailure, .totalFailure, .failedToStart, .cancelled:
            Issue.record("Expected skipped manual execution outcome")
        }
    }

    @Test
    func backgroundRefreshExecutionCoordinatorReturnsPartialFailureOutcomeWhenBatchMixesSuccessAndFailure() async {
        let result = BackgroundFeedRefreshResult(
            batchResult: FeedRefreshBatchResult(
                startedAt: .distantPast,
                finishedAt: .distantPast.addingTimeInterval(5),
                results: [
                    .fetched(
                        feedID: UUID(),
                        startedAt: .distantPast,
                        finishedAt: .distantPast.addingTimeInterval(3),
                        processedEntryCount: 2,
                        upsertedEntryCount: 2,
                        rejectedEntryCount: 0
                    ),
                    .failed(
                        feedID: UUID(),
                        startedAt: .distantPast,
                        finishedAt: .distantPast.addingTimeInterval(4),
                        errorDescription: "Network error"
                    )
                ]
            )
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: AppDependencies(
                logger: TestLogger(),
                backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(result: .executed(result))
            )
        )

        let outcome = await coordinator.executeAppRefresh()

        switch outcome {
        case .partialFailure(let resolvedResult):
            #expect(resolvedResult.summary.fetchedCount == 1)
            #expect(resolvedResult.summary.failedCount == 1)
        case .success, .totalFailure, .skippedManual, .failedToStart, .cancelled:
            Issue.record("Expected partial failure execution outcome")
        }
    }

    @Test
    func backgroundRefreshExecutionCoordinatorReturnsTotalFailureOutcomeWhenBatchHasOnlyFailures() async {
        let result = BackgroundFeedRefreshResult(
            batchResult: FeedRefreshBatchResult(
                startedAt: .distantPast,
                finishedAt: .distantPast.addingTimeInterval(5),
                results: [
                    .failed(
                        feedID: UUID(),
                        startedAt: .distantPast,
                        finishedAt: .distantPast.addingTimeInterval(4),
                        errorDescription: "Network error"
                    )
                ]
            )
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: AppDependencies(
                logger: TestLogger(),
                backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(result: .executed(result))
            )
        )

        let outcome = await coordinator.executeAppRefresh()

        switch outcome {
        case .totalFailure(let resolvedResult):
            #expect(resolvedResult.summary.totalFeedCount == 1)
            #expect(resolvedResult.summary.failedCount == 1)
        case .success, .partialFailure, .skippedManual, .failedToStart, .cancelled:
            Issue.record("Expected total failure execution outcome")
        }
    }

    @Test
    func backgroundRefreshExecutionCoordinatorReturnsFailedToStartOutcomeForPreparationFailure() async {
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: AppDependencies(
                logger: TestLogger(),
                backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(
                    result: .failedToStart(.configurationLoadFailed)
                )
            )
        )

        let outcome = await coordinator.executeAppRefresh()

        switch outcome {
        case .failedToStart(let failure):
            #expect(failure == .configurationLoadFailed)
        case .success, .partialFailure, .totalFailure, .skippedManual, .cancelled:
            Issue.record("Expected failed-to-start execution outcome")
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

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult {
        performScheduledRefreshCallCount += 1
        if let result {
            return .executed(result)
        }

        return .failedToStart(.configurationLoadFailed)
    }
}

@MainActor
private final class PrecomputedBackgroundRefreshServiceSpy: BackgroundRefreshService {
    private let result: BackgroundRefreshServiceExecutionResult

    init(result: BackgroundRefreshServiceExecutionResult) {
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

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult {
        result
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

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult {
        performScheduledRefreshCallCount += 1

        do {
            try await Task.sleep(for: .seconds(60))
            return .failedToStart(.configurationLoadFailed)
        } catch is CancellationError {
            observedCancellation = true
            return .failedToStart(.configurationLoadFailed)
        } catch {
            Issue.record("Unexpected error while waiting for cancellation: \(error)")
            return .failedToStart(.configurationLoadFailed)
        }
    }
}

private enum BackgroundRefreshExecutionCoordinatorTestError: Error {
    case unexpectedInvocation
}
