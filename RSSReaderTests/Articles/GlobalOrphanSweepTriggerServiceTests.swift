import Foundation
import SwiftUI
import Testing
@testable import RSSReader

@Suite("Articles / Global Orphan Sweep Trigger Service")
@MainActor
struct GlobalOrphanSweepTriggerServiceTests {
    @Test
    func contractRunsAtExactCadenceAndSuppressionBoundaries() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let contract = GlobalOrphanSweepTriggerContract(
            successfulSweepCadence: 100,
            feedScopedCleanupSuppressionWindow: 10
        )

        #expect(
            contract.decision(
                for: GlobalOrphanSweepScheduleSnapshot(
                    lastSuccessfulSweepAt: now,
                    lastFeedScopedRetentionCleanupAt: nil
                ),
                now: now.addingTimeInterval(99)
            ) == .suppressed(.cadence(nextEligibleAt: now.addingTimeInterval(100)))
        )
        #expect(
            contract.decision(
                for: GlobalOrphanSweepScheduleSnapshot(
                    lastSuccessfulSweepAt: now,
                    lastFeedScopedRetentionCleanupAt: nil
                ),
                now: now.addingTimeInterval(100)
            ) == .run
        )
        #expect(
            contract.decision(
                for: GlobalOrphanSweepScheduleSnapshot(
                    lastSuccessfulSweepAt: nil,
                    lastFeedScopedRetentionCleanupAt: now
                ),
                now: now.addingTimeInterval(9)
            ) == .suppressed(
                .recentFeedScopedRetentionCleanup(nextEligibleAt: now.addingTimeInterval(10))
            )
        )
        #expect(
            contract.decision(
                for: GlobalOrphanSweepScheduleSnapshot(
                    lastSuccessfulSweepAt: nil,
                    lastFeedScopedRetentionCleanupAt: now
                ),
                now: now.addingTimeInterval(10)
            ) == .run
        )
    }

    @Test
    func userDefaultsScheduleStorePersistsCadenceAcrossInstances() throws {
        let suiteName = "GlobalOrphanSweepTriggerServiceTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let successfulSweepAt = Date(timeIntervalSince1970: 1_700_000_000)
        let feedScopedCleanupAt = successfulSweepAt.addingTimeInterval(60)

        let firstStore = UserDefaultsGlobalOrphanSweepScheduleStore(userDefaults: userDefaults)
        firstStore.recordSuccessfulSweep(at: successfulSweepAt)
        firstStore.recordFeedScopedRetentionCleanup(at: feedScopedCleanupAt)
        let restoredSnapshot = UserDefaultsGlobalOrphanSweepScheduleStore(userDefaults: userDefaults)
            .loadSnapshot()

        #expect(
            restoredSnapshot == GlobalOrphanSweepScheduleSnapshot(
                lastSuccessfulSweepAt: successfulSweepAt,
                lastFeedScopedRetentionCleanupAt: feedScopedCleanupAt
            )
        )
    }

    @Test
    func repeatedCleanupAfterSweepBecomesDueDoesNotExtendSuppressionWindow() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let contract = GlobalOrphanSweepTriggerContract(
            successfulSweepCadence: 100,
            feedScopedCleanupSuppressionWindow: 10
        )
        let cleanupService = SuccessfulPersistenceBoundedGrowthCleanupService()
        let scheduleStore = InMemoryGlobalOrphanSweepScheduleStore(
            lastSuccessfulSweepAt: now
        )
        let triggerService = GlobalOrphanSweepTriggerService(
            logger: TestLogger(),
            cleanupService: cleanupService,
            scheduleStore: scheduleStore,
            contract: contract
        )
        let dueAt = now.addingTimeInterval(100)

        triggerService.recordFeedScopedRetentionCleanupCompleted(at: dueAt)
        triggerService.recordFeedScopedRetentionCleanupCompleted(
            at: dueAt.addingTimeInterval(5)
        )
        let result = await triggerService.runIfDue(
            now: dueAt.addingTimeInterval(10)
        )

        guard case .executed = result else {
            Issue.record("Expected suppression window to remain anchored to first due cleanup")
            return
        }
        #expect(cleanupService.cleanupBoundedGrowthCallCount == 1)
    }

    @Test
    func activeLifecycleRunsGlobalRecoveryAndInactiveLifecycleDoesNot() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feedID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try harness.articleStateRepository.upsert(
            feedID: feedID,
            articleExternalID: "legacy-orphan",
            update: ArticleStateUpsert(isRead: true, updatedAt: now)
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: feedID,
            articleExternalID: "starred-orphan",
            update: ArticleStateUpsert(isStarred: true, updatedAt: now)
        )

        let inactiveResult = await AppComposition.runGlobalOrphanSweepLifecycleIfNeeded(
            from: .background,
            using: harness.dependencies,
            now: now
        )

        #expect(inactiveResult == nil)
        #expect(try harness.articleStateRepository.fetchState(
            feedID: feedID,
            articleExternalID: "legacy-orphan"
        ) != nil)

        let activeResult = await AppComposition.runGlobalOrphanSweepLifecycleIfNeeded(
            from: .active,
            using: harness.dependencies,
            now: now
        )

        guard case .executed(let cleanupResult)? = activeResult else {
            Issue.record("Expected active lifecycle to execute global orphan sweep")
            return
        }
        #expect(cleanupResult.deletedArticleStateCount == 1)
        #expect(cleanupResult.retainedStarredArticleStateCount == 1)
        #expect(try harness.articleStateRepository.fetchState(
            feedID: feedID,
            articleExternalID: "legacy-orphan"
        ) == nil)
        #expect(try harness.articleStateRepository.fetchState(
            feedID: feedID,
            articleExternalID: "starred-orphan"
        )?.isStarred == true)
    }

    @Test
    func recentFeedScopedCleanupSuppressesLifecycleSweepUntilWindowBoundary() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/suppression.xml"]).first
        )
        let unrelatedFeedID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try harness.articleStateRepository.upsert(
            feedID: unrelatedFeedID,
            articleExternalID: "partial-sync-orphan",
            update: ArticleStateUpsert(isRead: true, updatedAt: now)
        )

        let retentionResult = harness.dependencies.appActions.cleanupArticles(
            policy: .oneWeek,
            scope: .feedIDs([feed.id]),
            now: now
        )
        let suppressedResult = await AppComposition.runGlobalOrphanSweepLifecycleIfNeeded(
            from: .active,
            using: harness.dependencies,
            now: now.addingTimeInterval(60 * 60 - 1)
        )

        #expect(retentionResult != nil)
        #expect(
            suppressedResult == .suppressed(
                .recentFeedScopedRetentionCleanup(
                    nextEligibleAt: now.addingTimeInterval(60 * 60)
                )
            )
        )
        #expect(try harness.articleStateRepository.fetchState(
            feedID: unrelatedFeedID,
            articleExternalID: "partial-sync-orphan"
        ) != nil)

        let boundaryResult = await AppComposition.runGlobalOrphanSweepLifecycleIfNeeded(
            from: .active,
            using: harness.dependencies,
            now: now.addingTimeInterval(60 * 60)
        )

        guard case .executed(let cleanupResult)? = boundaryResult else {
            Issue.record("Expected global orphan sweep at suppression boundary")
            return
        }
        #expect(cleanupResult.deletedArticleStateCount == 1)
        #expect(try harness.articleStateRepository.fetchState(
            feedID: unrelatedFeedID,
            articleExternalID: "partial-sync-orphan"
        ) == nil)
    }

    @Test
    func repeatedDueSweepIsIdempotentAndSuccessfulRunStartsWeeklyCadence() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feedID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try harness.articleStateRepository.upsert(
            feedID: feedID,
            articleExternalID: "orphan",
            update: ArticleStateUpsert(isRead: true, updatedAt: now)
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: feedID,
            articleExternalID: "starred-orphan",
            update: ArticleStateUpsert(isStarred: true, updatedAt: now)
        )

        let firstResult = await harness.dependencies.appActions.runScheduledGlobalOrphanSweepIfDue(now: now)
        let withinCadenceResult = await harness.dependencies.appActions.runScheduledGlobalOrphanSweepIfDue(
            now: now.addingTimeInterval(1)
        )
        let secondDueResult = await harness.dependencies.appActions.runScheduledGlobalOrphanSweepIfDue(
            now: now.addingTimeInterval(7 * 24 * 60 * 60)
        )

        guard case .executed(let firstCleanup)? = firstResult,
              case .executed(let secondCleanup)? = secondDueResult else {
            Issue.record("Expected both due lifecycle sweeps to execute")
            return
        }
        #expect(firstCleanup.deletedArticleStateCount == 1)
        #expect(secondCleanup.deletedArticleStateCount == 0)
        #expect(secondCleanup.retainedStarredArticleStateCount == 1)
        #expect(
            withinCadenceResult == .suppressed(
                .cadence(nextEligibleAt: now.addingTimeInterval(7 * 24 * 60 * 60))
            )
        )
    }

    @Test
    func partialFailureDoesNotAdvanceCadenceAndNextLifecycleAttemptRecovers() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cleanupService = FailOncePersistenceBoundedGrowthCleanupService()
        let scheduleStore = InMemoryGlobalOrphanSweepScheduleStore()
        let logger = RecordingLogger()
        let triggerService = GlobalOrphanSweepTriggerService(
            logger: logger,
            cleanupService: cleanupService,
            scheduleStore: scheduleStore
        )

        let failedResult = await triggerService.runIfDue(now: now)
        let recoveredResult = await triggerService.runIfDue(now: now)

        #expect(failedResult == .failed)
        guard case .executed = recoveredResult else {
            Issue.record("Expected retry after partial failure to execute")
            return
        }
        #expect(cleanupService.cleanupBoundedGrowthCallCount == 2)
        #expect(cleanupService.committedFeedFetchLogPhaseCount == 2)
        #expect(scheduleStore.loadSnapshot().lastSuccessfulSweepAt == now)
        #expect(logger.contains("Global orphan sweep lifecycle trigger failed", level: .error))
    }

    @Test
    func cancellationDoesNotAdvanceCadenceOrLogFailure() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cleanupService = CancellingPersistenceBoundedGrowthCleanupService()
        let scheduleStore = InMemoryGlobalOrphanSweepScheduleStore()
        let logger = RecordingLogger()
        let triggerService = GlobalOrphanSweepTriggerService(
            logger: logger,
            cleanupService: cleanupService,
            scheduleStore: scheduleStore
        )

        let result = await triggerService.runIfDue(now: now)

        #expect(result == .cancelled)
        #expect(scheduleStore.loadSnapshot().lastSuccessfulSweepAt == nil)
        #expect(logger.contains("Global orphan sweep lifecycle trigger failed", level: .error) == false)
        #expect(logger.contains("Global orphan sweep lifecycle trigger cancelled", level: .debug))
    }
}

@MainActor
private final class FailOncePersistenceBoundedGrowthCleanupService: PersistenceBoundedGrowthCleanupServicing {
    private(set) var cleanupBoundedGrowthCallCount = 0
    private(set) var committedFeedFetchLogPhaseCount = 0

    func cleanupFeedFetchLogs(now: Date) throws -> FeedFetchLogCleanupResult {
        makeFeedFetchLogCleanupResult(now: now)
    }

    func cleanupBoundedGrowth(now: Date) throws -> PersistenceBoundedGrowthCleanupResult {
        cleanupBoundedGrowthCallCount += 1
        committedFeedFetchLogPhaseCount += 1
        if cleanupBoundedGrowthCallCount == 1 {
            throw PartialSweepFailure.afterFeedFetchLogCleanup
        }
        return makePersistenceBoundedGrowthCleanupResult(now: now)
    }
}

@MainActor
private final class CancellingPersistenceBoundedGrowthCleanupService: PersistenceBoundedGrowthCleanupServicing {
    func cleanupFeedFetchLogs(now: Date) throws -> FeedFetchLogCleanupResult {
        makeFeedFetchLogCleanupResult(now: now)
    }

    func cleanupBoundedGrowth(now: Date) throws -> PersistenceBoundedGrowthCleanupResult {
        throw CancellationError()
    }
}

@MainActor
private final class SuccessfulPersistenceBoundedGrowthCleanupService: PersistenceBoundedGrowthCleanupServicing {
    private(set) var cleanupBoundedGrowthCallCount = 0

    func cleanupFeedFetchLogs(now: Date) throws -> FeedFetchLogCleanupResult {
        makeFeedFetchLogCleanupResult(now: now)
    }

    func cleanupBoundedGrowth(now: Date) throws -> PersistenceBoundedGrowthCleanupResult {
        cleanupBoundedGrowthCallCount += 1
        return makePersistenceBoundedGrowthCleanupResult(now: now)
    }
}

private enum PartialSweepFailure: Error {
    case afterFeedFetchLogCleanup
}

private func makeFeedFetchLogCleanupResult(now: Date) -> FeedFetchLogCleanupResult {
    FeedFetchLogCleanupResult(
        cutoffDate: now,
        maximumCountPerFeed: 200,
        deletedExpiredCount: 0,
        deletedExceedingCountLimit: 0,
        processedBatchCount: 0,
        maximumMaterializedBatchCount: 0
    )
}

private func makePersistenceBoundedGrowthCleanupResult(
    now: Date
) -> PersistenceBoundedGrowthCleanupResult {
    PersistenceBoundedGrowthCleanupResult(
        feedFetchLogCutoffDate: now,
        maximumFeedFetchLogCountPerFeed: 200,
        deletedExpiredFeedFetchLogCount: 0,
        deletedFeedFetchLogCountExceedingCountLimit: 0,
        feedFetchLogProcessedBatchCount: 0,
        maximumMaterializedFeedFetchLogBatchCount: 0,
        inspectedArticleStateCount: 0,
        deletedArticleStateCount: 0,
        retainedStarredArticleStateCount: 0,
        articleStateProcessedBatchCount: 0,
        maximumMaterializedArticleStateBatchCount: 0
    )
}
