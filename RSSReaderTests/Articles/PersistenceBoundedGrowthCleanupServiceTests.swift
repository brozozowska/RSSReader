import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Persistence Bounded Growth Cleanup Service")
@MainActor
struct PersistenceBoundedGrowthCleanupServiceTests {
    @Test
    func cleanupDeletesFeedFetchLogsOlderThanOneWeek() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/log-cleanup.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredLogDate = now.addingTimeInterval(-(8 * 24 * 60 * 60))
        let retainedLogDate = now.addingTimeInterval(-(6 * 24 * 60 * 60))
        _ = try harness.feedFetchLogRepository.insert(
            FeedFetchLogEntry(
                feedID: feed.id,
                status: "fetched",
                createdAt: expiredLogDate
            )
        )
        _ = try harness.feedFetchLogRepository.insert(
            FeedFetchLogEntry(
                feedID: feed.id,
                status: "notModified",
                createdAt: retainedLogDate
            )
        )
        let service = makeService(harness: harness)

        let result = try service.cleanupBoundedGrowth(now: now)
        let remainingLogs = try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil)

        #expect(result.deletedFeedFetchLogCount == 1)
        #expect(result.deletedExpiredFeedFetchLogCount == 1)
        #expect(result.deletedFeedFetchLogCountExceedingCountLimit == 0)
        #expect(result.maximumFeedFetchLogCountPerFeed == 200)
        #expect(remainingLogs.map(\.createdAt) == [retainedLogDate])
    }

    @Test
    func cleanupRetainsLogsAtExactTimeAndCountBoundaries() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/log-boundary.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let contract = FeedFetchLogRetentionContract(
            maximumAge: 7 * 24 * 60 * 60,
            maximumLogCountPerFeed: 3
        )
        let cutoffDate = contract.cutoffDate(now: now)
        try insertLogs(
            harness: harness,
            feedID: feed.id,
            createdAtDates: [cutoffDate, cutoffDate.addingTimeInterval(1), now]
        )

        let result = try makeService(harness: harness, contract: contract)
            .cleanupBoundedGrowth(now: now)
        let remainingLogs = try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil)

        #expect(result.deletedFeedFetchLogCount == 0)
        #expect(result.feedFetchLogCutoffDate == cutoffDate)
        #expect(remainingLogs.count == contract.maximumLogCountPerFeed)
        #expect(remainingLogs.map(\.createdAt) == [now, cutoffDate.addingTimeInterval(1), cutoffDate])
    }

    @Test
    func cleanupAppliesTimeEvictionBeforePerFeedCountEviction() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/log-order.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let contract = FeedFetchLogRetentionContract(
            maximumAge: 7 * 24 * 60 * 60,
            maximumLogCountPerFeed: 3
        )
        let cutoffDate = contract.cutoffDate(now: now)
        let retainedDates = (0...3).map { cutoffDate.addingTimeInterval(TimeInterval($0)) }
        try insertLogs(
            harness: harness,
            feedID: feed.id,
            createdAtDates: [cutoffDate.addingTimeInterval(-1)] + retainedDates
        )

        let result = try makeService(harness: harness, contract: contract)
            .cleanupBoundedGrowth(now: now)
        let remainingLogs = try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil)

        #expect(result.deletedExpiredFeedFetchLogCount == 1)
        #expect(result.deletedFeedFetchLogCountExceedingCountLimit == 1)
        #expect(result.deletedFeedFetchLogCount == 2)
        #expect(remainingLogs.map(\.createdAt) == Array(retainedDates.reversed().prefix(3)))
    }

    @Test
    func cleanupAppliesCountBudgetIndependentlyToEachFeed() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(urls: [
            "https://example.com/log-first.xml",
            "https://example.com/log-second.xml"
        ])
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let contract = FeedFetchLogRetentionContract(
            maximumAge: 7 * 24 * 60 * 60,
            maximumLogCountPerFeed: 2
        )
        try insertLogs(
            harness: harness,
            feedID: firstFeed.id,
            createdAtDates: [now, now.addingTimeInterval(-1), now.addingTimeInterval(-2)]
        )
        try insertLogs(
            harness: harness,
            feedID: secondFeed.id,
            createdAtDates: [now.addingTimeInterval(-10), now.addingTimeInterval(-11)]
        )

        let result = try makeService(harness: harness, contract: contract)
            .cleanupBoundedGrowth(now: now)
        let firstFeedLogs = try harness.feedFetchLogRepository.fetchLogs(feedID: firstFeed.id, limit: nil)
        let secondFeedLogs = try harness.feedFetchLogRepository.fetchLogs(feedID: secondFeed.id, limit: nil)

        #expect(result.deletedExpiredFeedFetchLogCount == 0)
        #expect(result.deletedFeedFetchLogCountExceedingCountLimit == 1)
        #expect(firstFeedLogs.map(\.createdAt) == [now, now.addingTimeInterval(-1)])
        #expect(secondFeedLogs.map(\.createdAt) == [
            now.addingTimeInterval(-10),
            now.addingTimeInterval(-11)
        ])
    }

    @Test
    func repeatedFeedFetchLogCleanupIsIdempotent() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/log-idempotent.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let contract = FeedFetchLogRetentionContract(
            maximumAge: 7 * 24 * 60 * 60,
            maximumLogCountPerFeed: 2
        )
        try insertLogs(
            harness: harness,
            feedID: feed.id,
            createdAtDates: [
                now,
                now.addingTimeInterval(-1),
                now.addingTimeInterval(-2),
                contract.cutoffDate(now: now).addingTimeInterval(-1)
            ]
        )
        let service = makeService(harness: harness, contract: contract)

        let firstResult = try service.cleanupBoundedGrowth(now: now)
        let secondResult = try service.cleanupBoundedGrowth(now: now)

        #expect(firstResult.deletedExpiredFeedFetchLogCount == 1)
        #expect(firstResult.deletedFeedFetchLogCountExceedingCountLimit == 1)
        #expect(secondResult.deletedFeedFetchLogCount == 0)
        #expect(try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil).count == 2)
    }

    @Test
    func cleanupDeletesUnstarredArticleStatesWithoutArticleAndKeepsStarredOrLinkedStates() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-cleanup.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let linkedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "linked",
            url: "https://example.com/articles/linked",
            title: "Linked"
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: linkedArticle.feedID,
            articleExternalID: linkedArticle.externalID,
            update: ArticleStateUpsert(
                isRead: true,
                readAt: now,
                updatedAt: now
            )
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: "orphan-read",
            update: ArticleStateUpsert(
                isRead: true,
                readAt: now,
                updatedAt: now
            )
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: "orphan-starred",
            update: ArticleStateUpsert(
                isStarred: true,
                starredAt: now,
                updatedAt: now
            )
        )
        let service = makeService(harness: harness)

        let result = try service.cleanupBoundedGrowth(now: now)

        let linkedState = try harness.articleStateRepository.fetchState(
            feedID: feed.id,
            articleExternalID: "linked"
        )
        let deletedOrphanState = try harness.articleStateRepository.fetchState(
            feedID: feed.id,
            articleExternalID: "orphan-read"
        )
        let retainedStarredState = try harness.articleStateRepository.fetchState(
            feedID: feed.id,
            articleExternalID: "orphan-starred"
        )

        #expect(result.inspectedArticleStateCount == 3)
        #expect(result.deletedArticleStateCount == 1)
        #expect(result.retainedStarredArticleStateCount == 1)
        #expect(linkedState != nil)
        #expect(deletedOrphanState == nil)
        #expect(retainedStarredState?.isStarred == true)
    }

    @Test
    func appDependenciesPurgeRunsBoundedGrowthCleanupForDeletedArchivedArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/purge-state-cleanup.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let archivedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "archived",
            url: "https://example.com/articles/archived",
            title: "Archived",
            archivedAt: now
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: archivedArticle.feedID,
            articleExternalID: archivedArticle.externalID,
            update: ArticleStateUpsert(
                isRead: true,
                readAt: now,
                updatedAt: now
            )
        )

        _ = harness.dependencies.appActions.purgeArchivedArticles()

        let remainingArticle = try harness.articleRepository.fetchArticle(
            feedID: feed.id,
            externalID: "archived"
        )
        let remainingState = try harness.articleStateRepository.fetchState(
            feedID: feed.id,
            articleExternalID: "archived"
        )

        #expect(remainingArticle == nil)
        #expect(remainingState == nil)
    }

    private func makeService(
        harness: TestHarness,
        contract: FeedFetchLogRetentionContract = .current
    ) -> PersistenceBoundedGrowthCleanupService {
        PersistenceBoundedGrowthCleanupService(
            logger: TestLogger(),
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository,
            feedFetchLogRepository: harness.feedFetchLogRepository,
            feedFetchLogRetentionContract: contract
        )
    }

    private func insertLogs(
        harness: TestHarness,
        feedID: UUID,
        createdAtDates: [Date]
    ) throws {
        _ = try harness.feedFetchLogRepository.insert(
            createdAtDates.map { createdAt in
                FeedFetchLogEntry(
                    feedID: feedID,
                    status: "fetched",
                    createdAt: createdAt
                )
            }
        )
    }
}
