import Foundation

enum AppRuntimeReloadState: Sendable {
    case activeForeground
    case inactiveOrBackground
}

enum BackgroundRefreshForegroundHandoffDecision: Sendable, Equatable {
    case noReload
    case requestReloadImmediately
    case deferUntilNextForeground
}

enum BackgroundRefreshForegroundHandoffPolicy {
    static func decision(
        for outcome: BackgroundRefreshExecutionOutcome,
        runtimeState: AppRuntimeReloadState
    ) -> BackgroundRefreshForegroundHandoffDecision {
        guard outcomeContainsMaterializedContentChanges(outcome) else {
            return .noReload
        }

        switch runtimeState {
        case .activeForeground:
            return .requestReloadImmediately
        case .inactiveOrBackground:
            return .deferUntilNextForeground
        }
    }

    private static func outcomeContainsMaterializedContentChanges(
        _ outcome: BackgroundRefreshExecutionOutcome
    ) -> Bool {
        switch outcome {
        case .success(let result), .partialFailure(let result):
            return result.summary.fetchedCount > 0
        case .totalFailure, .skippedManual, .failedToStart, .cancelled:
            return false
        }
    }
}
