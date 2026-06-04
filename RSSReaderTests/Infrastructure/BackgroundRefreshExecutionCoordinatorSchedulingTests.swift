import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Execution Coordinator / Scheduling")
@MainActor
struct BackgroundRefreshExecutionCoordinatorSchedulingTests {
    @Test
    func backgroundRefreshExecutionCoordinatorReschedulesBeforeForegroundHandoff() async {
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
        let eventRecorder = ExecutionEventRecorder()
        let scheduler = ExecutionCoordinatorRecordingBackgroundRefreshScheduler {
            eventRecorder.record("reschedule")
        }
        let handoffCoordinator = ExecutionCoordinatorRecordingForegroundHandoffCoordinator {
            eventRecorder.record("handoff")
        }
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: AppDependencies(
                logger: TestLogger(),
                backgroundRefreshService: CompletedBackgroundRefreshServiceSpy(
                    result: expectedResult,
                    configuration: configuration
                ),
                backgroundRefreshForegroundHandoffCoordinator: handoffCoordinator,
                backgroundRefreshScheduler: scheduler
            )
        )

        let outcome = await coordinator.executeAppRefresh()

        #expect(eventRecorder.events == ["reschedule", "handoff"])
        #expect(handoffCoordinator.handleCallCount == 1)
        switch handoffCoordinator.lastOutcome {
        case .success(let handedOffResult):
            #expect(handedOffResult.duration == 5)
        case .partialFailure, .totalFailure, .skippedManual, .failedToStart, .cancelled, nil:
            Issue.record("Expected success outcome to be handed off after reschedule")
        }
        switch outcome {
        case .success:
            break
        case .partialFailure, .totalFailure, .skippedManual, .failedToStart, .cancelled:
            Issue.record("Expected success execution outcome")
        }
    }

    @Test
    func backgroundRefreshExecutionCoordinatorLogsRescheduleFailure() async {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )
        let logger = RecordingLogger()
        let scheduler = ExecutionCoordinatorRecordingBackgroundRefreshScheduler(
            replaceError: NSError(
                domain: BGTaskScheduler.Error.errorDomain,
                code: BGTaskScheduler.Error.Code.unavailable.rawValue
            )
        )
        let dependencies = AppDependencies(
            logger: logger,
            backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(
                result: .skippedManual(configuration),
                configuration: configuration
            ),
            backgroundRefreshScheduler: scheduler
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: dependencies
        )

        let outcome = await coordinator.executeAppRefresh()

        #expect(scheduler.replaceCallCount == 1)
        let diagnostics = dependencies.currentBackgroundRefreshValidationDiagnostics().postRunReschedule
        #expect(diagnostics?.outcome == .failed)
        #expect(diagnostics?.failureReason == .backgroundRefreshUnavailable)
        #expect(
            logger.contains(
                "Background refresh validation stage=postRunReschedule outcome=failed",
                level: .error
            )
        )
        #expect(
            logger.contains(
                "failureReason=backgroundRefreshUnavailable",
                level: .error
            )
        )
        switch outcome {
        case .skippedManual(let resolvedConfiguration):
            #expect(resolvedConfiguration.policy.preference == .manual)
        case .success, .partialFailure, .totalFailure, .failedToStart, .cancelled:
            Issue.record("Expected skipped manual execution outcome")
        }
    }
}
