import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Execution Coordinator / Outcomes")
@MainActor
struct BackgroundRefreshExecutionCoordinatorOutcomeTests {
    @Test
    func backgroundRefreshExecutionCoordinatorReturnsFinishedOutcomeForCompletedRefresh() async {
        let expectedResult = BackgroundFeedRefreshResult(
            batchResult: FeedRefreshBatchResult(
                startedAt: .distantPast,
                finishedAt: .distantPast.addingTimeInterval(5),
                results: []
            )
        )
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .hourly),
            policy: BackgroundRefreshPolicy(preference: .hourly)
        )
        let backgroundRefreshService = CompletedBackgroundRefreshServiceSpy(
            result: expectedResult,
            configuration: configuration
        )
        let logger = RecordingLogger()
        let scheduler = ExecutionCoordinatorRecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: logger,
            backgroundRefreshService: backgroundRefreshService,
            backgroundRefreshScheduler: scheduler
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: dependencies)

        let outcome = await coordinator.executeAppRefresh()

        #expect(backgroundRefreshService.performScheduledRefreshCallCount == 1)
        #expect(scheduler.replaceCallCount == 1)
        #expect(scheduler.lastReplacedConfiguration?.policy.preference == .hourly)
        #expect(logger.contains("Background refresh validation stage=executionStart outcome=started", level: .info))
        #expect(logger.contains("Background refresh validation stage=executionCompletion outcome=success", level: .info))
        #expect(logger.contains("fetchedCount=0", level: .info))
        #expect(logger.contains("Background refresh validation stage=postRunReschedule outcome=scheduled", level: .info))
        switch outcome {
        case .success(let result):
            #expect(result.trigger == .background)
            #expect(result.duration == 5)
        case .partialFailure, .totalFailure, .skippedManual, .failedToStart, .cancelled:
            Issue.record("Expected success execution outcome")
        }
    }

    @Test
    func backgroundRefreshExecutionCoordinatorReturnsSkippedManualOutcome() async {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )
        let logger = RecordingLogger()
        let scheduler = ExecutionCoordinatorRecordingBackgroundRefreshScheduler()
        let backgroundRefreshService = PrecomputedBackgroundRefreshServiceSpy(
            result: .skippedManual(configuration),
            configuration: configuration
        )
        let dependencies = AppDependencies(
            logger: logger,
            backgroundRefreshService: backgroundRefreshService,
            backgroundRefreshScheduler: scheduler
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(dependencies: dependencies)

        let outcome = await coordinator.executeAppRefresh()

        #expect(scheduler.replaceCallCount == 1)
        #expect(scheduler.lastReplacedConfiguration?.policy.preference == .manual)
        #expect(
            logger.contains(
                "Background refresh validation stage=executionCompletion outcome=skippedManual refreshIntervalPreference=manual",
                level: .info
            )
        )
        #expect(logger.contains("Background refresh validation stage=postRunReschedule outcome=cancelled", level: .info))
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
                backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(
                    result: .executed(result),
                    configuration: BackgroundRefreshConfiguration(
                        settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .hourly),
                        policy: BackgroundRefreshPolicy(preference: .hourly)
                    )
                )
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
                        errorDescription: "Error Domain=NSURLErrorDomain Code=-1009 \"The Internet connection appears to be offline.\""
                    )
                ]
            )
        )
        let logger = RecordingLogger()
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: AppDependencies(
                logger: logger,
                backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(
                    result: .executed(result),
                    configuration: BackgroundRefreshConfiguration(
                        settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .hourly),
                        policy: BackgroundRefreshPolicy(preference: .hourly)
                    )
                )
            )
        )

        let outcome = await coordinator.executeAppRefresh()

        #expect(logger.contains("Background refresh validation stage=executionCompletion outcome=totalFailure", level: .info))
        #expect(logger.contains("networkFailureCount=1", level: .info))
        #expect(logger.contains("likelyNoConnectivityHeuristic=true", level: .info))
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
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .hourly),
            policy: BackgroundRefreshPolicy(preference: .hourly)
        )
        let logger = RecordingLogger()
        let scheduler = ExecutionCoordinatorRecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: logger,
            backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(
                result: .failedToStart(.configurationLoadFailed),
                configuration: configuration
            ),
            backgroundRefreshScheduler: scheduler
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: dependencies
        )

        let outcome = await coordinator.executeAppRefresh()

        #expect(scheduler.replaceCallCount == 1)
        #expect(scheduler.lastReplacedConfiguration?.policy.preference == .hourly)
        let diagnostics = dependencies.currentBackgroundRefreshValidationDiagnostics().executionCompletion
        #expect(diagnostics?.kind == .failedToStart)
        #expect(diagnostics?.failureReason == "configurationLoadFailed")
        #expect(
            logger.contains(
                "Background refresh validation stage=executionCompletion outcome=failedToStart",
                level: .error
            )
        )
        #expect(
            logger.contains(
                "failureReason=configurationLoadFailed",
                level: .error
            )
        )
        switch outcome {
        case .failedToStart(let failure):
            #expect(failure == .configurationLoadFailed)
        case .success, .partialFailure, .totalFailure, .skippedManual, .cancelled:
            Issue.record("Expected failed-to-start execution outcome")
        }
    }
}
