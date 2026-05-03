import BackgroundTasks
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
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .hourly),
            policy: BackgroundRefreshPolicy(preference: .hourly)
        )
        let backgroundRefreshService = CompletedBackgroundRefreshServiceSpy(
            result: expectedResult,
            configuration: configuration
        )
        let logger = RecordingLogger()
        let scheduler = RecordingBackgroundRefreshScheduler()
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
        #expect(logger.contains("Starting background refresh execution", level: .info))
        #expect(logger.contains("Completed background refresh execution outcome=success", level: .info))
        #expect(logger.contains("fetchedCount=0", level: .info))
        #expect(logger.contains("Background refresh execution reschedule outcome=scheduled", level: .info))
        switch outcome {
        case .success(let result):
            #expect(result.trigger == .background)
            #expect(result.duration == 5)
        case .partialFailure, .totalFailure, .skippedManual, .failedToStart, .cancelled:
            Issue.record("Expected success execution outcome")
        }
    }

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
        let scheduler = RecordingBackgroundRefreshScheduler {
            eventRecorder.record("reschedule")
        }
        let handoffCoordinator = RecordingBackgroundRefreshForegroundHandoffCoordinator {
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
    func backgroundRefreshExecutionCoordinatorCancelsRefreshTaskWhenParentTaskIsCancelled() async throws {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .every6Hours),
            policy: BackgroundRefreshPolicy(preference: .every6Hours)
        )
        let backgroundRefreshService = CancellableBackgroundRefreshServiceSpy(configuration: configuration)
        let logger = RecordingLogger()
        let scheduler = RecordingBackgroundRefreshScheduler()
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
                "Received background refresh task cancellation; cancelling in-flight refresh task",
                level: .info
            )
        )
        #expect(logger.contains("Completed background refresh execution outcome=cancelled partialResultAvailable=false", level: .info))
        #expect(logger.contains("Background refresh execution reschedule outcome=scheduled", level: .info))
        let cancellationMarkerIndex = try #require(
            logger.entries.firstIndex {
                $0.level == .info
                    && $0.message.contains(
                        "Received background refresh task cancellation; cancelling in-flight refresh task"
                    )
            }
        )
        let terminalOutcomeMarkerIndex = try #require(
            logger.entries.firstIndex {
                $0.level == .info
                    && $0.message.contains(
                        "Completed background refresh execution outcome=cancelled partialResultAvailable=false"
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

    @Test
    func backgroundRefreshExecutionCoordinatorReturnsSkippedManualOutcome() async {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )
        let logger = RecordingLogger()
        let scheduler = RecordingBackgroundRefreshScheduler()
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
                "Completed background refresh execution outcome=skippedManual refreshIntervalPreference=manual",
                level: .info
            )
        )
        #expect(logger.contains("Background refresh execution reschedule outcome=cancelled", level: .info))
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

        #expect(logger.contains("Completed background refresh execution outcome=totalFailure", level: .info))
        #expect(logger.contains("networkFailureCount=1", level: .info))
        #expect(logger.contains("likelyNoConnectivity=true", level: .info))
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
        let scheduler = RecordingBackgroundRefreshScheduler()
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: AppDependencies(
                logger: logger,
                backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(
                    result: .failedToStart(.configurationLoadFailed),
                    configuration: configuration
                ),
                backgroundRefreshScheduler: scheduler
            )
        )

        let outcome = await coordinator.executeAppRefresh()

        #expect(scheduler.replaceCallCount == 1)
        #expect(scheduler.lastReplacedConfiguration?.policy.preference == .hourly)
        #expect(
            logger.contains(
                "Completed background refresh execution outcome=failedToStart reason=configurationLoadFailed",
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

    @Test
    func backgroundRefreshExecutionCoordinatorLogsRescheduleFailure() async {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )
        let logger = RecordingLogger()
        let scheduler = RecordingBackgroundRefreshScheduler(
            replaceError: NSError(
                domain: BGTaskScheduler.Error.errorDomain,
                code: BGTaskScheduler.Error.Code.unavailable.rawValue
            )
        )
        let coordinator = DefaultBackgroundRefreshExecutionCoordinator(
            dependencies: AppDependencies(
                logger: logger,
                backgroundRefreshService: PrecomputedBackgroundRefreshServiceSpy(
                    result: .skippedManual(configuration),
                    configuration: configuration
                ),
                backgroundRefreshScheduler: scheduler
            )
        )

        let outcome = await coordinator.executeAppRefresh()

        #expect(scheduler.replaceCallCount == 1)
        #expect(
            logger.contains(
                "Background refresh execution reschedule outcome=failed reason=backgroundRefreshUnavailable",
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

@MainActor
private final class CompletedBackgroundRefreshServiceSpy: BackgroundRefreshService {
    private(set) var performScheduledRefreshCallCount = 0
    private let result: BackgroundFeedRefreshResult?
    private let configuration: BackgroundRefreshConfiguration

    init(
        result: BackgroundFeedRefreshResult?,
        configuration: BackgroundRefreshConfiguration
    ) {
        self.result = result
        self.configuration = configuration
    }

    func loadConfiguration() throws -> BackgroundRefreshConfiguration {
        configuration
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
    private let configuration: BackgroundRefreshConfiguration

    init(
        result: BackgroundRefreshServiceExecutionResult,
        configuration: BackgroundRefreshConfiguration
    ) {
        self.result = result
        self.configuration = configuration
    }

    func loadConfiguration() throws -> BackgroundRefreshConfiguration {
        configuration
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
    private let configuration: BackgroundRefreshConfiguration

    init(configuration: BackgroundRefreshConfiguration) {
        self.configuration = configuration
    }

    func loadConfiguration() throws -> BackgroundRefreshConfiguration {
        configuration
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

@MainActor
private final class RecordingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    private(set) var replaceCallCount = 0
    private(set) var lastReplacedConfiguration: BackgroundRefreshConfiguration?
    private let replaceError: Error?
    private let onReplace: (() -> Void)?

    init(
        replaceError: Error? = nil,
        onReplace: (() -> Void)? = nil
    ) {
        self.replaceError = replaceError
        self.onReplace = onReplace
    }

    func schedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshSchedulePlan? {
        lastReplacedConfiguration = configuration
        return DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now)
    }

    func cancel() {}

    func replace(
        using configuration: BackgroundRefreshConfiguration,
        now: Date
    ) throws -> BackgroundRefreshScheduleResult {
        replaceCallCount += 1
        lastReplacedConfiguration = configuration

        if let replaceError {
            throw replaceError
        }

        onReplace?()

        if let plan = DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now) {
            return .scheduled(plan)
        }

        return .cancelled
    }
}

@MainActor
private final class RecordingBackgroundRefreshForegroundHandoffCoordinator: BackgroundRefreshForegroundHandoffCoordinating {
    private(set) var handleCallCount = 0
    private(set) var lastOutcome: BackgroundRefreshExecutionOutcome?
    private let onHandle: (() -> Void)?

    init(onHandle: (() -> Void)? = nil) {
        self.onHandle = onHandle
    }

    func bindReloadHandler(_ handler: @escaping @MainActor () -> Void) {}

    func unbindReloadHandler() {}

    func updateRuntimeState(_ runtimeState: AppRuntimeReloadState) {}

    func handleBackgroundRefreshExecutionOutcome(_ outcome: BackgroundRefreshExecutionOutcome) {
        handleCallCount += 1
        lastOutcome = outcome
        onHandle?()
    }
}

@MainActor
private final class ExecutionEventRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}
