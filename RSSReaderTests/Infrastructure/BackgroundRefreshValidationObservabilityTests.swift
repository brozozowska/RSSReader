import Foundation
import UIKit
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Validation Observability")
@MainActor
struct BackgroundRefreshValidationObservabilityTests {
    @Test
    func registrationMarkerPublishesTypedDiagnosticsSnapshot() {
        let logger = RecordingLogger()
        let dependencies = AppDependencies(logger: logger)

        reportBackgroundRefreshRegistration(using: dependencies)

        #expect(
            dependencies.currentBackgroundRefreshValidationDiagnostics().registration
                == BackgroundRefreshRegistrationDiagnostics(
                    identifier: BackgroundRefreshTaskConfiguration.appRefreshIdentifier,
                    handlerDescription: "SwiftUI.backgroundTask(.appRefresh)"
                )
        )
        #expect(
            logger.contains(
                "Background refresh validation stage=registration outcome=configured",
                level: .info
            )
        )
    }

    @Test
    func runtimePrerequisitesSnapshotIsAvailableAsStandaloneObservabilityContract() {
        let source = DefaultBackgroundRefreshRuntimePrerequisitesSource(
            backgroundRefreshService: ValidationObservabilityBackgroundRefreshServiceSpy(
                configuration: BackgroundRefreshConfiguration(
                    settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .every6Hours),
                    policy: BackgroundRefreshPolicy(preference: .every6Hours)
                )
            ),
            application: ValidationObservabilityBackgroundRefreshStatusProvider(status: .available),
            processInfo: ValidationObservabilityLowPowerModeProvider(isLowPowerModeEnabled: true)
        )

        let snapshot = source.currentSnapshot()

        #expect(snapshot.backgroundRefreshStatus == .available)
        #expect(snapshot.isLowPowerModeEnabled)
        #expect(snapshot.refreshIntervalPreference == .every6Hours)
        #expect(snapshot.schedulingMode == .automatic)
    }

    @Test
    func diagnosticsReporterPublishesSchedulingAndRescheduleStagesWithoutExecutionCoordinator() {
        let logger = RecordingLogger()
        let reporter = DefaultBackgroundRefreshValidationDiagnosticsReporter(logger: logger)
        let scheduledDate = Date(timeIntervalSince1970: 1_700_000_000)

        reporter.reportLaunchScheduling(
            outcome: .scheduled,
            identifier: BackgroundRefreshTaskConfiguration.appRefreshIdentifier,
            earliestBeginDate: scheduledDate,
            failureReason: nil
        )
        reporter.reportPostRunReschedule(
            outcome: .failed,
            identifier: nil,
            earliestBeginDate: nil,
            failureReason: .backgroundRefreshUnavailable
        )

        let snapshot = reporter.currentSnapshot()
        #expect(
            snapshot.scheduling
                == BackgroundRefreshSchedulingDiagnostics(
                    trigger: .launchBootstrap,
                    outcome: .scheduled,
                    identifier: BackgroundRefreshTaskConfiguration.appRefreshIdentifier,
                    earliestBeginDate: scheduledDate,
                    failureReason: nil
                )
        )
        #expect(
            snapshot.postRunReschedule
                == BackgroundRefreshPostRunRescheduleDiagnostics(
                    outcome: .failed,
                    identifier: nil,
                    earliestBeginDate: nil,
                    failureReason: .backgroundRefreshUnavailable
                )
        )
        #expect(
            logger.contains(
                "Background refresh validation stage=scheduling trigger=launchBootstrap outcome=scheduled",
                level: .info
            )
        )
        #expect(
            logger.contains(
                "Background refresh validation stage=postRunReschedule outcome=failed",
                level: .error
            )
        )
    }

    @Test
    func diagnosticsReporterPublishesExecutionStagesAsTypedSnapshot() {
        let logger = RecordingLogger()
        let reporter = DefaultBackgroundRefreshValidationDiagnosticsReporter(logger: logger)

        reporter.reportExecutionStarted()
        reporter.reportExecutionCancellationReceived()
        reporter.reportExecutionCompleted(
            BackgroundRefreshExecutionCompletionDiagnostics(
                kind: .cancelled,
                refreshIntervalPreference: nil,
                partialResultAvailable: false,
                totalFeedCount: nil,
                fetchedCount: nil,
                notModifiedCount: nil,
                failedCount: nil,
                cancelledCount: nil,
                networkFailureCount: nil,
                likelyNoConnectivityHeuristic: nil,
                duration: nil,
                failureReason: nil
            )
        )

        let snapshot = reporter.currentSnapshot()
        #expect(snapshot.executionStart == BackgroundRefreshExecutionStartDiagnostics())
        #expect(snapshot.executionCancellation == BackgroundRefreshExecutionCancellationDiagnostics())
        #expect(snapshot.executionCompletion?.kind == .cancelled)
        #expect(snapshot.executionCompletion?.partialResultAvailable == false)
        #expect(
            logger.contains(
                "Background refresh validation stage=executionStart outcome=started",
                level: .info
            )
        )
        #expect(
            logger.contains(
                "Background refresh validation stage=executionCancellation outcome=receivedSystemCancellation",
                level: .info
            )
        )
        #expect(
            logger.contains(
                "Background refresh validation stage=executionCompletion outcome=cancelled",
                level: .info
            )
        )
    }
}

@MainActor
private final class ValidationObservabilityBackgroundRefreshServiceSpy: BackgroundRefreshService {
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
        configuration
    }

    func performScheduledRefresh() async -> BackgroundRefreshServiceExecutionResult {
        .skippedManual(configuration)
    }
}

@MainActor
private struct ValidationObservabilityBackgroundRefreshStatusProvider: BackgroundRefreshStatusProviding {
    let status: UIBackgroundRefreshStatus

    var backgroundRefreshStatus: UIBackgroundRefreshStatus {
        status
    }
}

private struct ValidationObservabilityLowPowerModeProvider: LowPowerModeStatusProviding {
    let isLowPowerModeEnabled: Bool
}
