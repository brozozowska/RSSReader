import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Retention Cleanup Service")
@MainActor
struct ArticleRetentionCleanupServiceTests {
    @Test
    func cleanupAppliesSourceAgeToCurrentAndArchivedArticlesAndProtectsStarredState() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/retention.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredSourceDate = now.addingTimeInterval(-(8 * 24 * 60 * 60))
        let retainedSourceDate = now.addingTimeInterval(-(6 * 24 * 60 * 60))
        let expiredCurrent = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "expired-current",
            publishedAt: expiredSourceDate,
            createdAt: expiredSourceDate
        )
        _ = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "expired-archived",
            publishedAt: expiredSourceDate,
            archivedAt: now,
            createdAt: expiredSourceDate
        )
        _ = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "retained-current",
            publishedAt: retainedSourceDate,
            createdAt: retainedSourceDate
        )
        _ = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "retained-archived",
            publishedAt: retainedSourceDate,
            archivedAt: now,
            createdAt: retainedSourceDate
        )
        let starredCurrent = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "starred-expired-current",
            publishedAt: expiredSourceDate,
            createdAt: expiredSourceDate
        )
        let starredArchived = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "starred-expired-archived",
            publishedAt: expiredSourceDate,
            archivedAt: now,
            createdAt: expiredSourceDate
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: expiredCurrent.feedID,
            articleExternalID: expiredCurrent.externalID,
            update: ArticleStateUpsert(isRead: true, readAt: now, updatedAt: now)
        )
        for article in [starredCurrent, starredArchived] {
            _ = try harness.articleStateRepository.upsert(
                feedID: article.feedID,
                articleExternalID: article.externalID,
                update: ArticleStateUpsert(isStarred: true, starredAt: now, updatedAt: now)
            )
        }
        let service = makeService(harness: harness, maximumCount: 10, batchSize: 2)

        let result = try service.cleanupArticles(policy: .oneWeek, now: now)
        let remainingIDs = try harness.articleRepository.fetchArticles(feedID: feed.id).map(\.externalID)
        let expiredState = try harness.articleStateRepository.fetchState(
            feedID: feed.id,
            articleExternalID: expiredCurrent.externalID
        )

        #expect(result.inspectedArticleCount == 6)
        #expect(result.deletedCount == 2)
        #expect(result.deletedByTimeOrMembershipCount == 2)
        #expect(result.deletedByCountLimitCount == 0)
        #expect(result.retainedStarredCount == 2)
        #expect(result.deletedOrphanArticleStateCount == 1)
        #expect(Set(remainingIDs) == Set([
            "retained-current",
            "retained-archived",
            "starred-expired-current",
            "starred-expired-archived"
        ]))
        #expect(expiredState == nil)
    }

    @Test
    func cleanupBoundsAFeedThatKeepsReturningMultiYearCurrentHistory() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/multi-year.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let year: TimeInterval = 365 * 24 * 60 * 60

        for index in 1...5 {
            let sourceDate = now.addingTimeInterval(-(TimeInterval(index) * year))
            _ = try insertArticle(
                harness: harness,
                feed: feed,
                externalID: "year-\(index)",
                publishedAt: sourceDate,
                createdAt: sourceDate
            )
        }
        _ = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "recent",
            publishedAt: now.addingTimeInterval(-(10 * 24 * 60 * 60)),
            createdAt: now.addingTimeInterval(-(10 * 24 * 60 * 60))
        )
        let service = makeService(harness: harness, maximumCount: 10, batchSize: 2)

        let result = try service.cleanupArticles(policy: .oneMonth, now: now)
        let remainingIDs = try harness.articleRepository.fetchArticles(feedID: feed.id).map(\.externalID)

        #expect(result.deletedByTimeOrMembershipCount == 5)
        #expect(remainingIDs == ["recent"])
    }

    @Test
    func cleanupUsesCountBudgetForMissingDatesAndKeepsNewestMaterializedArticlesPerFeed() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/missing-first.xml"]).first)
        let secondFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/missing-second.xml"]).first)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<5 {
            _ = try insertArticle(
                harness: harness,
                feed: firstFeed,
                externalID: "first-\(index)",
                createdAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
        for index in 0..<3 {
            _ = try insertArticle(
                harness: harness,
                feed: secondFeed,
                externalID: "second-\(index)",
                createdAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
        _ = try harness.articleStateRepository.upsert(
            feedID: firstFeed.id,
            articleExternalID: "first-0",
            update: ArticleStateUpsert(isStarred: true, starredAt: baseDate, updatedAt: baseDate)
        )
        let service = makeService(harness: harness, maximumCount: 3, batchSize: 2)

        let result = try service.cleanupArticles(policy: .oneWeek, now: baseDate.addingTimeInterval(100))
        let firstRemainingIDs = try harness.articleRepository.fetchArticles(feedID: firstFeed.id).map(\.externalID)
        let secondRemainingIDs = try harness.articleRepository.fetchArticles(feedID: secondFeed.id).map(\.externalID)

        #expect(result.deletedByTimeOrMembershipCount == 0)
        #expect(result.deletedByCountLimitCount == 1)
        #expect(Set(firstRemainingIDs) == Set(["first-0", "first-2", "first-3", "first-4"]))
        #expect(Set(secondRemainingIDs) == Set(["second-0", "second-1", "second-2"]))
    }

    @Test
    func currentFeedOnlyDeletesOnlyArchivedUnstarredArticlesBeforeApplyingCountBudget() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/current-only.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "old-current",
            publishedAt: .distantPast,
            createdAt: .distantPast
        )
        _ = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "archived",
            archivedAt: now,
            createdAt: now
        )
        let starredArchived = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "starred-archived",
            archivedAt: now,
            createdAt: now
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: starredArchived.externalID,
            update: ArticleStateUpsert(isStarred: true, starredAt: now, updatedAt: now)
        )
        let service = makeService(harness: harness, maximumCount: 10, batchSize: 1)

        let result = try service.cleanupArticles(policy: .currentFeedOnly, now: now)
        let remainingIDs = try harness.articleRepository.fetchArticles(feedID: feed.id).map(\.externalID)

        #expect(result.deletedByTimeOrMembershipCount == 1)
        #expect(Set(remainingIDs) == Set(["old-current", "starred-archived"]))
    }

    @Test
    func repeatedCleanupIsIdempotentForArticlesAndOrphanStates() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/idempotent.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expired = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "expired",
            publishedAt: now.addingTimeInterval(-(8 * 24 * 60 * 60)),
            createdAt: now.addingTimeInterval(-(8 * 24 * 60 * 60))
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: expired.externalID,
            update: ArticleStateUpsert(isRead: true, readAt: now, updatedAt: now)
        )
        let service = makeService(harness: harness, maximumCount: 10, batchSize: 1)

        let firstResult = try service.cleanupArticles(policy: .oneWeek, now: now)
        let secondResult = try service.cleanupArticles(policy: .oneWeek, now: now)

        #expect(firstResult.deletedCount == 1)
        #expect(firstResult.deletedOrphanArticleStateCount == 1)
        #expect(secondResult.deletedCount == 0)
        #expect(secondResult.deletedOrphanArticleStateCount == 0)
        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)
        #expect(try harness.articleStateRepository.fetchState(
            feedID: feed.id,
            articleExternalID: expired.externalID
        ) == nil)
    }

    @Test
    func purgeDeletesArchivedArticlesInBatchesAndRetainsStarredAndCurrentArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/archive-purge.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try insertArticle(harness: harness, feed: feed, externalID: "current")
        let starredArchived = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "starred-archived",
            archivedAt: now
        )
        let archived = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "archived",
            archivedAt: now
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: starredArchived.externalID,
            update: ArticleStateUpsert(isStarred: true, starredAt: now, updatedAt: now)
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: archived.externalID,
            update: ArticleStateUpsert(isRead: true, readAt: now, updatedAt: now)
        )
        let service = makeService(harness: harness, maximumCount: 10, batchSize: 1)

        let result = try service.purgeArchivedArticles()
        let remainingIDs = try harness.articleRepository.fetchArticles(feedID: feed.id).map(\.externalID)

        #expect(result.inspectedArchivedCount == 2)
        #expect(result.deletedCount == 1)
        #expect(result.retainedStarredCount == 1)
        #expect(result.deletedOrphanArticleStateCount == 1)
        #expect(Set(remainingIDs) == Set(["current", "starred-archived"]))
    }

    @Test
    func manualRefreshRunsRetentionForCurrentSourceAgedArticles() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/manual-retention.xml"]).first)
        _ = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "manual-retention-expired",
            publishedAt: .distantPast,
            createdAt: .distantPast
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(articleRetentionPolicy: .oneWeek, updatedAt: .distantPast)
        )

        _ = await harness.dependencies.appActions.refreshAllFeeds()

        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)
    }

    @Test
    func backgroundRefreshRunsRetentionForCurrentSourceAgedArticles() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/background-retention.xml"]).first)
        _ = try insertArticle(
            harness: harness,
            feed: feed,
            externalID: "background-retention-expired",
            publishedAt: .distantPast,
            createdAt: .distantPast
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .hourly,
                articleRetentionPolicy: .oneWeek,
                updatedAt: .distantPast
            )
        )

        _ = await harness.dependencies.appActions.refreshFeedsForBackground()

        #expect(try harness.articleRepository.fetchArticles(feedID: feed.id).isEmpty)
    }

    private func makeService(
        harness: TestHarness,
        maximumCount: Int,
        batchSize: Int
    ) -> ArticleRetentionCleanupService {
        ArticleRetentionCleanupService(
            logger: TestLogger(),
            feedRepository: harness.feedRepository,
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository,
            contract: ArticleRetentionContract(maximumUnstarredArticleCountPerFeed: maximumCount),
            batchSize: batchSize
        )
    }

    private func insertArticle(
        harness: TestHarness,
        feed: Feed,
        externalID: String,
        publishedAt: Date? = nil,
        updatedAtSource: Date? = nil,
        archivedAt: Date? = nil,
        createdAt: Date = .now
    ) throws -> Article {
        try harness.insertArticle(
            feed: feed,
            externalID: externalID,
            url: "https://example.com/articles/\(externalID)",
            title: externalID,
            publishedAt: publishedAt,
            updatedAtSource: updatedAtSource,
            archivedAt: archivedAt,
            fetchedAt: createdAt,
            createdAt: createdAt
        )
    }
}
