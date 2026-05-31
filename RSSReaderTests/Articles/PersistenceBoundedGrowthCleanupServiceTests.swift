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
        #expect(remainingLogs.map(\.createdAt) == [retainedLogDate])
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

        _ = harness.dependencies.purgeArchivedArticles()

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

    private func makeService(harness: TestHarness) -> PersistenceBoundedGrowthCleanupService {
        PersistenceBoundedGrowthCleanupService(
            logger: TestLogger(),
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository,
            feedFetchLogRepository: harness.feedFetchLogRepository
        )
    }
}
