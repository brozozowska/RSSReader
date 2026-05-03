import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Background Refresh Foreground Handoff Policy")
struct BackgroundRefreshForegroundHandoffPolicyTests {
    @Test
    func foregroundHandoffPolicyRequestsImmediateReloadWhenForegroundRuntimeHasMaterializedRefresh() {
        let decision = BackgroundRefreshForegroundHandoffPolicy.decision(
            for: .success(makeBackgroundResult(results: [
                .fetched(
                    feedID: UUID(),
                    startedAt: .distantPast,
                    finishedAt: .distantPast.addingTimeInterval(1),
                    processedEntryCount: 1,
                    upsertedEntryCount: 1,
                    rejectedEntryCount: 0
                )
            ])),
            runtimeState: .activeForeground
        )

        expectRequestReloadImmediately(decision)
    }

    @Test
    func foregroundHandoffPolicyDefersReloadUntilNextForegroundWhenRuntimeIsBackgrounded() {
        let decision = BackgroundRefreshForegroundHandoffPolicy.decision(
            for: .partialFailure(makeBackgroundResult(results: [
                .fetched(
                    feedID: UUID(),
                    startedAt: .distantPast,
                    finishedAt: .distantPast.addingTimeInterval(1),
                    processedEntryCount: 1,
                    upsertedEntryCount: 1,
                    rejectedEntryCount: 0
                ),
                .failed(
                    feedID: UUID(),
                    startedAt: .distantPast,
                    finishedAt: .distantPast.addingTimeInterval(2),
                    errorDescription: "Network error"
                )
            ])),
            runtimeState: .inactiveOrBackground
        )

        expectDeferUntilNextForeground(decision)
    }

    @Test
    func foregroundHandoffPolicyDoesNotReloadForNotModifiedOnlyBatch() {
        let decision = BackgroundRefreshForegroundHandoffPolicy.decision(
            for: .success(makeBackgroundResult(results: [
                .notModified(
                    feedID: UUID(),
                    startedAt: .distantPast,
                    finishedAt: .distantPast.addingTimeInterval(1)
                )
            ])),
            runtimeState: .activeForeground
        )

        expectNoReload(decision)
    }

    @Test
    func foregroundHandoffPolicyDoesNotReloadForTotalFailure() {
        let decision = BackgroundRefreshForegroundHandoffPolicy.decision(
            for: .totalFailure(makeBackgroundResult(results: [
                .failed(
                    feedID: UUID(),
                    startedAt: .distantPast,
                    finishedAt: .distantPast.addingTimeInterval(1),
                    errorDescription: "Network error"
                )
            ])),
            runtimeState: .activeForeground
        )

        expectNoReload(decision)
    }

    @Test
    func foregroundHandoffPolicyDoesNotReloadForSkippedManualPolicy() {
        let configuration = BackgroundRefreshConfiguration(
            settingsSnapshot: AppSettingsSnapshot(refreshIntervalPreference: .manual),
            policy: BackgroundRefreshPolicy(preference: .manual)
        )

        let decision = BackgroundRefreshForegroundHandoffPolicy.decision(
            for: .skippedManual(configuration),
            runtimeState: .inactiveOrBackground
        )

        expectNoReload(decision)
    }

    @Test
    func foregroundHandoffPolicyDoesNotReloadForCancelledExecution() {
        let decision = BackgroundRefreshForegroundHandoffPolicy.decision(
            for: .cancelled(nil),
            runtimeState: .activeForeground
        )

        expectNoReload(decision)
    }
}

private func makeBackgroundResult(results: [FeedRefreshResult]) -> BackgroundFeedRefreshResult {
    BackgroundFeedRefreshResult(
        batchResult: FeedRefreshBatchResult(
            startedAt: .distantPast,
            finishedAt: .distantPast.addingTimeInterval(5),
            results: results
        )
    )
}

private func expectNoReload(_ decision: BackgroundRefreshForegroundHandoffDecision) {
    switch decision {
    case .noReload:
        break
    case .requestReloadImmediately:
        Issue.record("Expected noReload but got requestReloadImmediately")
    case .deferUntilNextForeground:
        Issue.record("Expected noReload but got deferUntilNextForeground")
    }
}

private func expectRequestReloadImmediately(_ decision: BackgroundRefreshForegroundHandoffDecision) {
    switch decision {
    case .requestReloadImmediately:
        break
    case .noReload:
        Issue.record("Expected requestReloadImmediately but got noReload")
    case .deferUntilNextForeground:
        Issue.record("Expected requestReloadImmediately but got deferUntilNextForeground")
    }
}

private func expectDeferUntilNextForeground(_ decision: BackgroundRefreshForegroundHandoffDecision) {
    switch decision {
    case .deferUntilNextForeground:
        break
    case .noReload:
        Issue.record("Expected deferUntilNextForeground but got noReload")
    case .requestReloadImmediately:
        Issue.record("Expected deferUntilNextForeground but got requestReloadImmediately")
    }
}
