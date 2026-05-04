import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / RSSReaderApp")
@MainActor
struct RSSReaderAppTests {
    @Test
    func rssReaderAppUsesBackgroundRefreshIdentifierFromInfrastructureConfiguration() {
        #expect(
            RSSReaderApp.backgroundAppRefreshIdentifier
                == BackgroundRefreshTaskConfiguration.appRefreshIdentifier
        )
    }

    @Test
    func backgroundRefreshRegistrationLoggingPublishesAppLevelMarkerWithInfrastructureIdentifier() {
        let logger = RecordingLogger()
        let dependencies = AppDependencies(logger: logger)

        dependencies.reportBackgroundRefreshRegistrationConfigured()

        #expect(
            logger.contains(
                "Background refresh validation stage=registration outcome=configured identifier=\(BackgroundRefreshTaskConfiguration.appRefreshIdentifier)",
                level: .info
            )
        )
        #expect(
            logger.contains(
                "handler=SwiftUI.backgroundTask(.appRefresh)",
                level: .info
            )
        )
        #expect(
            dependencies.currentBackgroundRefreshValidationDiagnostics().registration
                == BackgroundRefreshRegistrationDiagnostics(
                    identifier: BackgroundRefreshTaskConfiguration.appRefreshIdentifier,
                    handlerDescription: "SwiftUI.backgroundTask(.appRefresh)"
                )
        )
    }

    @Test
    func performBackgroundAppRefreshDelegatesToBackgroundRefreshServiceThroughAppDependencies() async {
        let expectedResult = BackgroundFeedRefreshResult(
            batchResult: FeedRefreshBatchResult(
                startedAt: .distantPast,
                finishedAt: .distantPast.addingTimeInterval(1),
                results: []
            )
        )
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .hourly),
            policy: BackgroundRefreshPolicy(preference: .hourly)
        )
        let backgroundRefreshService = BackgroundRefreshServiceSpy(
            result: expectedResult,
            configuration: configuration
        )
        let scheduler = RecordingBackgroundRefreshScheduler()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            backgroundRefreshService: backgroundRefreshService,
            backgroundRefreshScheduler: scheduler
        )

        let outcome = await dependencies.executeBackgroundAppRefresh()

        #expect(backgroundRefreshService.performScheduledRefreshCallCount == 1)
        #expect(backgroundRefreshService.loadConfigurationCallCount == 1)
        #expect(scheduler.replaceCallCount == 1)
        #expect(scheduler.lastReplacedConfiguration?.policy.preference == .hourly)
        switch outcome {
        case .success(let result):
            #expect(result.trigger == .background)
            #expect(result.batchResult.results.isEmpty == true)
            #expect(result.duration == 1)
        case .partialFailure, .totalFailure, .skippedManual, .failedToStart, .cancelled:
            Issue.record("Expected success execution outcome")
        }
    }
}

@MainActor
private final class BackgroundRefreshServiceSpy: BackgroundRefreshService {
    private(set) var loadConfigurationCallCount = 0
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
        loadConfigurationCallCount += 1
        return configuration
    }

    func updatePreference(
        _ preference: RefreshPreference,
        updatedAt: Date
    ) throws -> BackgroundRefreshConfiguration {
        Issue.record("updatePreference(_:updatedAt:) should not be used in this test")
        throw BackgroundRefreshServiceSpyTestError.unexpectedInvocation
    }

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult {
        performScheduledRefreshCallCount += 1
        return .executed(result!)
    }
}

@MainActor
private final class RecordingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    private(set) var replaceCallCount = 0
    private(set) var lastReplacedConfiguration: BackgroundRefreshConfiguration?

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

        if let plan = DefaultBackgroundRefreshScheduler.makeSchedulePlan(using: configuration, now: now) {
            return .scheduled(plan)
        }

        return .cancelled
    }
}

private enum BackgroundRefreshServiceSpyTestError: Error {
    case unexpectedInvocation
}
