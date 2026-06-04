import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Retention Cleanup Service")
@MainActor
struct ArticleRetentionCleanupServiceTests {
    @Test
    func cleanupDeletesArchivedArticlesOlderThanPolicyAndKeepsStarredArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/retention.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expiredArchivedAt = now.addingTimeInterval(-(8 * 24 * 60 * 60))
        let retainedArchivedAt = now.addingTimeInterval(-(6 * 24 * 60 * 60))
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "expired-archived",
            url: "https://example.com/articles/expired",
            title: "Expired Archived",
            archivedAt: expiredArchivedAt
        )
        let starredArticle = try harness.insertArticle(
            feed: feed,
            externalID: "starred-expired-archived",
            url: "https://example.com/articles/starred-expired",
            title: "Starred Expired Archived",
            archivedAt: expiredArchivedAt
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "retained-archived",
            url: "https://example.com/articles/retained",
            title: "Retained Archived",
            archivedAt: retainedArchivedAt
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: starredArticle.feedID,
            articleExternalID: starredArticle.externalID,
            update: ArticleStateUpsert(
                isStarred: true,
                starredAt: now,
                updatedAt: now
            )
        )
        let service = ArticleRetentionCleanupService(
            logger: TestLogger(),
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository
        )

        let result = try service.cleanupArchivedArticles(policy: .oneWeek, now: now)
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result.inspectedArchivedCount == 3)
        #expect(result.deletedCount == 1)
        #expect(result.retainedStarredCount == 1)
        #expect(remainingArticles.map(\.externalID).sorted() == ["retained-archived", "starred-expired-archived"])
    }

    @Test
    func cleanupWithNoneDeletesUnstarredArchivedArticlesImmediately() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/retention-none.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "archived-now",
            url: "https://example.com/articles/archived-now",
            title: "Archived Now",
            archivedAt: now
        )
        let service = ArticleRetentionCleanupService(
            logger: TestLogger(),
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository
        )

        let result = try service.cleanupArchivedArticles(policy: .currentFeedOnly, now: now)
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result.deletedCount == 1)
        #expect(remainingArticles.isEmpty)
    }

    @Test
    func purgeDeletesUnstarredArchivedArticlesAndRetainsStarredAndCurrentArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/archive-purge.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let currentArticle = try harness.insertArticle(
            feed: feed,
            externalID: "current",
            url: "https://example.com/articles/current",
            title: "Current"
        )
        let starredArchivedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "starred-archived",
            url: "https://example.com/articles/starred-archived",
            title: "Starred Archived",
            archivedAt: now
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "archived",
            url: "https://example.com/articles/archived",
            title: "Archived",
            archivedAt: now
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: starredArchivedArticle.feedID,
            articleExternalID: starredArchivedArticle.externalID,
            update: ArticleStateUpsert(
                isStarred: true,
                starredAt: now,
                updatedAt: now
            )
        )
        let service = ArticleRetentionCleanupService(
            logger: TestLogger(),
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository
        )

        let result = try service.purgeArchivedArticles()
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result.inspectedArchivedCount == 2)
        #expect(result.deletedCount == 1)
        #expect(result.retainedStarredCount == 1)

        let remainingArticleIDs = remainingArticles.map(\.id)
        let expectedArticleIDs = [currentArticle.id, starredArchivedArticle.id]
        #expect(Set(remainingArticleIDs) == Set(expectedArticleIDs))
    }

    @Test
    func manualRefreshRunsArticleRetentionCleanup() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/manual-retention.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "manual-retention-expired",
            url: "https://example.com/articles/manual-retention-expired",
            title: "Manual Retention Expired",
            archivedAt: .distantPast
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                articleRetentionPolicy: .currentFeedOnly,
                updatedAt: .distantPast
            )
        )

        _ = await harness.dependencies.appActions.refreshAllFeeds()
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(remainingArticles.isEmpty)
    }

    @Test
    func backgroundRefreshRunsArticleRetentionCleanup() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/background-retention.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "background-retention-expired",
            url: "https://example.com/articles/background-retention-expired",
            title: "Background Retention Expired",
            archivedAt: .distantPast
        )
        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                refreshIntervalPreference: .hourly,
                articleRetentionPolicy: .currentFeedOnly,
                updatedAt: .distantPast
            )
        )

        _ = await harness.dependencies.appActions.refreshFeedsForBackground()
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(remainingArticles.isEmpty)
    }
}
