import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Execution Coordinator / Cancellation")
@MainActor
struct BackgroundRefreshExecutionCoordinatorCancellationTests {
    @Test
    func backgroundRefreshExecutionCoordinatorCancelsRefreshTaskWhenParentTaskIsCancelled() async throws {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .every6Hours),
            policy: BackgroundRefreshPolicy(preference: .every6Hours)
        )
        let backgroundRefreshService = CancellableBackgroundRefreshServiceSpy(configuration: configuration)
        let logger = RecordingLogger()
        let scheduler = ExecutionCoordinatorRecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: logger,
            backgroundRefreshService: backgroundRefreshService,
            backgroundRefreshScheduler: scheduler
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
        #expect(scheduler.replaceCallCount == 1)
        #expect(scheduler.lastReplacedConfiguration?.policy.preference == .every6Hours)
        #expect(
            logger.contains(
                "Background refresh validation stage=executionCancellation outcome=receivedSystemCancellation",
                level: .info
            )
        )
        #expect(logger.contains("Background refresh validation stage=executionCompletion outcome=cancelled", level: .info))
        #expect(logger.contains("partialResultAvailable=false", level: .info))
        #expect(logger.contains("Background refresh validation stage=postRunReschedule outcome=scheduled", level: .info))
        let cancellationMarkerIndex = try #require(
            logger.entries.firstIndex {
                $0.level == .info
                    && $0.message.contains(
                        "Background refresh validation stage=executionCancellation outcome=receivedSystemCancellation"
                    )
            }
        )
        let terminalOutcomeMarkerIndex = try #require(
            logger.entries.firstIndex {
                $0.level == .info
                    && $0.message.contains(
                        "Background refresh validation stage=executionCompletion outcome=cancelled"
                    )
            }
        )
        #expect(cancellationMarkerIndex < terminalOutcomeMarkerIndex)
        switch outcome {
        case .success, .partialFailure, .totalFailure, .skippedManual, .failedToStart:
            Issue.record("Expected cancelled execution outcome")
        case .cancelled(let result):
            #expect(result == nil)
        }
    }
}
