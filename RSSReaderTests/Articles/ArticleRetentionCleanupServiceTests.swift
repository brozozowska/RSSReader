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
        #expect(firstResult.diagnostics.maximumMaterializedFeedBatchCount == 1)
        #expect(firstResult.diagnostics.maximumMaterializedArticleBatchCount == 1)
        #expect(firstResult.diagnostics.maximumMaterializedArticleStateBatchCount == 1)
        #expect(secondResult.diagnostics.maximumMaterializedFeedBatchCount == 1)
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
    func globalCleanupEnumeratesManyFeedsInBoundedBatches() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let batchSize = 3
        let feedCount = 8
        let feeds = try harness.insertFeeds(
            urls: (0..<feedCount).map { "https://example.com/many-feeds-\($0).xml" }
        )

        for (index, feed) in feeds.enumerated() {
            _ = try insertArticle(
                harness: harness,
                feed: feed,
                externalID: "expired-\(index)",
                publishedAt: .distantPast,
                createdAt: .distantPast
            )
        }
        let service = makeService(harness: harness, maximumCount: 10, batchSize: batchSize)

        let result = try service.cleanupArticles(
            policy: .oneWeek,
            scope: .allFeeds,
            now: now
        )

        #expect(result.deletedCount == feedCount)
        #expect(result.diagnostics.processedFeedCount == feedCount)
        #expect(result.diagnostics.processedFeedBatchCount == 3)
        #expect(result.diagnostics.maximumMaterializedFeedBatchCount == batchSize)
        #expect(result.diagnostics.maximumMaterializedArticleBatchCount <= batchSize)
        #expect(result.diagnostics.maximumMaterializedArticleStateBatchCount <= batchSize)
    }

    @Test
    func cleanupKeepsManyStarredArticlesWithoutMaterializingMoreThanBatchSize() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/many-starred.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let batchSize = 3
        let starredCount = 11

        for index in 0..<starredCount {
            let article = try insertArticle(
                harness: harness,
                feed: feed,
                externalID: "starred-\(index)",
                publishedAt: .distantPast,
                archivedAt: index.isMultiple(of: 2) ? now : nil,
                createdAt: .distantPast
            )
            _ = try harness.articleStateRepository.upsert(
                feedID: feed.id,
                articleExternalID: article.externalID,
                update: ArticleStateUpsert(isStarred: true, starredAt: now, updatedAt: now)
            )
        }
        let service = makeService(harness: harness, maximumCount: 2, batchSize: batchSize)

        let result = try service.cleanupArticles(policy: .oneWeek, now: now)
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result.deletedCount == 0)
        #expect(result.retainedStarredCount == starredCount)
        #expect(remainingArticles.count == starredCount)
        #expect(result.diagnostics.processedArticleBatchCount > 1)
        #expect(result.diagnostics.processedArticleStateBatchCount > 1)
        #expect(result.diagnostics.maximumMaterializedArticleBatchCount == batchSize)
        #expect(result.diagnostics.maximumMaterializedArticleStateBatchCount == batchSize)
    }

    @Test
    func manualPurgeKeepsManyStarredArticlesAndBoundsIdentityBatches() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/many-purge.xml"]).first)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let batchSize = 3
        let starredCount = 7
        let unstarredCount = 5

        for index in 0..<starredCount {
            let article = try insertArticle(
                harness: harness,
                feed: feed,
                externalID: "purge-starred-\(index)",
                archivedAt: now
            )
            _ = try harness.articleStateRepository.upsert(
                feedID: feed.id,
                articleExternalID: article.externalID,
                update: ArticleStateUpsert(isStarred: true, starredAt: now, updatedAt: now)
            )
        }
        for index in 0..<unstarredCount {
            let article = try insertArticle(
                harness: harness,
                feed: feed,
                externalID: "purge-unstarred-\(index)",
                archivedAt: now
            )
            _ = try harness.articleStateRepository.upsert(
                feedID: feed.id,
                articleExternalID: article.externalID,
                update: ArticleStateUpsert(isRead: true, readAt: now, updatedAt: now)
            )
        }
        let service = makeService(harness: harness, maximumCount: 2, batchSize: batchSize)

        let result = try service.purgeArchivedArticles()
        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result.deletedCount == unstarredCount)
        #expect(result.retainedStarredCount == starredCount)
        #expect(result.deletedOrphanArticleStateCount == unstarredCount)
        #expect(remainingArticles.count == starredCount)
        #expect(result.diagnostics.maximumMaterializedFeedBatchCount == 1)
        #expect(result.diagnostics.maximumMaterializedArticleBatchCount == batchSize)
        #expect(result.diagnostics.maximumMaterializedArticleStateBatchCount == batchSize)
    }

    @Test
    func singleFeedRefreshRunsRetentionOnlyForRefreshedFeed() async throws {
        let targetURL = "https://example.com/scoped-single-target.xml"
        let otherURL = "https://example.com/scoped-single-other.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    targetURL: .response(statusCode: 304, headers: [:], body: "")
                ]
            )
        )
        let feeds = try harness.insertFeeds(urls: [targetURL, otherURL])
        let targetFeed = feeds[0]
        let otherFeed = feeds[1]
        _ = try insertArticle(
            harness: harness,
            feed: targetFeed,
            externalID: "target-expired",
            publishedAt: .distantPast,
            createdAt: .distantPast
        )
        _ = try insertArticle(
            harness: harness,
            feed: otherFeed,
            externalID: "other-expired",
            publishedAt: .distantPast,
            createdAt: .distantPast
        )
        _ = try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleRetentionPolicy: .oneWeek, updatedAt: .distantPast)
        )

        _ = await harness.dependencies.appActions.refreshFeed(id: targetFeed.id)

        #expect(try harness.articleRepository.fetchArticles(feedID: targetFeed.id).isEmpty)
        #expect(try harness.articleRepository.fetchArticles(feedID: otherFeed.id).map(\.externalID) == ["other-expired"])
    }

    @Test
    func folderRefreshRunsRetentionOnlyForFeedsReturnedByFolderRefresh() async throws {
        let folderURLs = [
            "https://example.com/scoped-folder-first.xml",
            "https://example.com/scoped-folder-second.xml"
        ]
        let outsideURL = "https://example.com/scoped-folder-outside.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: Dictionary(
                    uniqueKeysWithValues: folderURLs.map { url in
                        (url, .response(statusCode: 304, headers: [:], body: ""))
                    }
                )
            )
        )
        let feeds = try harness.insertFeeds(urls: folderURLs + [outsideURL])
        let folder = try harness.folderRepository.insert(Folder(name: "Scoped"))
        feeds[0].folder = folder
        feeds[1].folder = folder
        try harness.saveModelContext()

        for (index, feed) in feeds.enumerated() {
            _ = try insertArticle(
                harness: harness,
                feed: feed,
                externalID: "folder-expired-\(index)",
                publishedAt: .distantPast,
                createdAt: .distantPast
            )
        }
        _ = try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(articleRetentionPolicy: .oneWeek, updatedAt: .distantPast)
        )
        let appState = AppState()
        harness.dependencies.appActions.showFolder(named: "Scoped", using: appState)

        let refreshResult = await harness.dependencies.appActions.refreshCurrentSelection(using: appState)

        #expect(refreshResult?.summary.totalFeedCount == 2)
        #expect(try harness.articleRepository.fetchArticles(feedID: feeds[0].id).isEmpty)
        #expect(try harness.articleRepository.fetchArticles(feedID: feeds[1].id).isEmpty)
        #expect(try harness.articleRepository.fetchArticles(feedID: feeds[2].id).map(\.externalID) == ["folder-expired-2"])
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
