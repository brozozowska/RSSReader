import Foundation

extension AppDependencies {
    @MainActor
    func currentBackgroundRefreshRuntimePrerequisites() -> BackgroundRefreshRuntimePrerequisitesSnapshot {
        backgroundRefreshRuntimePrerequisitesSource.currentSnapshot()
    }

    @MainActor
    func currentBackgroundRefreshValidationDiagnostics() -> BackgroundRefreshValidationDiagnosticsSnapshot {
        backgroundRefreshValidationDiagnosticsReporter.currentSnapshot()
    }

    @MainActor
    func configureBackgroundRefreshLaunchScheduling(now: Date = .now) {
        do {
            reportBackgroundRefreshLaunchScheduling(
                try replaceBackgroundRefreshSchedule(now: now)
            )
        } catch {
            backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
                outcome: .failed,
                identifier: nil,
                earliestBeginDate: nil,
                failureReason: BackgroundRefreshScheduleFailureReason.classify(error)
            )
        }
    }

    @MainActor
    func reportSkippedDuplicateBackgroundRefreshLaunchSchedulingAttempt() {
        backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
            outcome: .skippedDuplicateLaunchAttempt,
            identifier: nil,
            earliestBeginDate: nil,
            failureReason: nil
        )
    }

    @MainActor
    @discardableResult
    func replaceBackgroundRefreshSchedule(
        using configuration: BackgroundRefreshConfiguration,
        now: Date = .now
    ) throws -> BackgroundRefreshScheduleResult {
        try backgroundRefreshScheduler.replace(using: configuration, now: now)
    }

    @MainActor
    @discardableResult
    func replaceBackgroundRefreshSchedule(
        now: Date = .now
    ) throws -> BackgroundRefreshScheduleResult? {
        guard let backgroundRefreshService else {
            logger.debug(
                "Background refresh dependencies trace outcome=serviceUnavailable operation=replaceSchedule"
            )
            return nil
        }

        let configuration = try backgroundRefreshService.loadConfiguration()
        return try replaceBackgroundRefreshSchedule(using: configuration, now: now)
    }
}

private extension AppDependencies {
    @MainActor
    func reportBackgroundRefreshLaunchScheduling(_ result: BackgroundRefreshScheduleResult?) {
        switch result {
        case .scheduled(let plan):
            backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
                outcome: .scheduled,
                identifier: plan.identifier,
                earliestBeginDate: plan.earliestBeginDate,
                failureReason: nil
            )
        case .cancelled:
            backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
                outcome: .cancelled,
                identifier: nil,
                earliestBeginDate: nil,
                failureReason: nil
            )
        case nil:
            backgroundRefreshValidationDiagnosticsReporter.reportLaunchScheduling(
                outcome: .unavailable,
                identifier: nil,
                earliestBeginDate: nil,
                failureReason: nil
            )
        }
    }
}
