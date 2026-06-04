import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

final class CompletedBackgroundRefreshServiceSpy: BackgroundRefreshService {
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
final class PrecomputedBackgroundRefreshServiceSpy: BackgroundRefreshService {
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
final class CancellableBackgroundRefreshServiceSpy: BackgroundRefreshService {
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

enum BackgroundRefreshExecutionCoordinatorTestError: Error {
    case unexpectedInvocation
}

@MainActor
final class ExecutionCoordinatorRecordingBackgroundRefreshScheduler: BackgroundRefreshScheduling {
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
final class ExecutionCoordinatorRecordingForegroundHandoffCoordinator: BackgroundRefreshForegroundHandoffCoordinating {
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
final class ExecutionEventRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}
