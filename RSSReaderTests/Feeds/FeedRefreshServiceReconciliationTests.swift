import Foundation
import Testing
@testable import RSSReader

@Suite("Feeds / Refresh Service / Reconciliation")
@MainActor
struct FeedRefreshServiceReconciliationTests {
    @Test
    func refreshUpdatesFeedMetadataAndArchivesMissingArticles() async throws {
        let feedURL = "https://example.com/reconcile-feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Reconciled Feed Title",
                            channelLink: "https://example.com/reconciled/",
                            language: "fr",
                            itemTitle: "Current Article",
                            itemLink: "https://example.com/reconciled/articles/current",
                            itemGUID: "current-article",
                            itemDescription: "Current article summary",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )

        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        feed.title = "Stale Feed Title"
        feed.displayTitleOverride = "Custom Display Name"
        feed.siteURL = "https://example.com/old/"
        feed.language = "en"
        feed.kind = .unknown
        try harness.saveModelContext()

        _ = try harness.insertArticle(
            feed: feed,
            externalID: "obsolete-article",
            guid: "obsolete-article",
            url: "https://example.com/reconciled/articles/obsolete",
            title: "Obsolete Article"
        )
        let existingArchivedAt = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "already-archived-article",
            guid: "already-archived-article",
            url: "https://example.com/reconciled/articles/already-archived",
            title: "Already Archived Article",
            archivedAt: existingArchivedAt
        )

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        #expect(result.upsertedEntryCount == 1)

        let refreshedFeed = try #require(try harness.fetchFeed(id: feed.id))
        #expect(refreshedFeed.title == "Reconciled Feed Title")
        #expect(refreshedFeed.displayTitleOverride == "Custom Display Name")
        #expect(refreshedFeed.displayTitle == "Custom Display Name")
        #expect(refreshedFeed.siteURL == "https://example.com/reconciled/")
        #expect(refreshedFeed.language == "fr")
        #expect(refreshedFeed.kind == .rss)

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.count == 3)

        let obsoleteArticle = try #require(articles.first { $0.externalID == "obsolete-article" })
        #expect(obsoleteArticle.archivedAt != nil)
        #expect(obsoleteArticle.feedTitle == "Custom Display Name")

        let alreadyArchivedArticle = try #require(articles.first { $0.externalID == "already-archived-article" })
        #expect(alreadyArchivedArticle.archivedAt == existingArchivedAt)
        #expect(alreadyArchivedArticle.feedTitle == "Custom Display Name")

        let currentArticle = try #require(articles.first { $0.guid == "current-article" })
        #expect(currentArticle.archivedAt == nil)
        #expect(currentArticle.title == "Current Article")
        #expect(currentArticle.feedTitle == "Custom Display Name")
    }

    @Test
    func refreshReactivatesArticleWhenItReappearsInFeedPayload() async throws {
        let feedURL = "https://example.com/reappearing-feed.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Reappearing Feed",
                            channelLink: "https://example.com/reappearing/",
                            language: "en",
                            itemTitle: "Revived Article",
                            itemLink: "https://example.com/reappearing/articles/revived",
                            itemGUID: "revived-article",
                            itemDescription: "Revived article summary",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )

        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        let refreshedEntryExternalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: feedURL,
                guid: "revived-article",
                articleURL: "https://example.com/reappearing/articles/revived",
                title: "Revived Article",
                publishedAt: FeedDateParsingService.parse("Tue, 02 Jan 2024 10:00:00 GMT")
            )
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: refreshedEntryExternalID,
            guid: "revived-article",
            url: "https://example.com/reappearing/articles/revived",
            title: "Stale Revived Article",
            archivedAt: .distantPast
        )

        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .fetched)
        #expect(result.upsertedEntryCount == 1)

        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(articles.count == 1)

        let revivedArticle = try #require(articles.first)
        #expect(revivedArticle.externalID == refreshedEntryExternalID)
        #expect(revivedArticle.archivedAt == nil)
        #expect(revivedArticle.title == "Revived Article")
    }

    @Test
    func refreshRollsBackFeedAndArticleSnapshotWhenReconciliationFailsBeforeCommit() async throws {
        let feedURL = "https://example.com/rollback-feed.xml"
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <rss version="2.0">
                      <channel>
                        <title>Updated Feed</title>
                        <link>https://example.com/updated/</link>
                        <item>
                          <title>Updated Current Article</title>
                          <link>https://example.com/articles/current</link>
                          <guid>current-article</guid>
                          <description>Updated summary</description>
                        </item>
                        <item>
                          <title>New Article</title>
                          <link>https://example.com/articles/new</link>
                          <guid>new-article</guid>
                          <description>New summary</description>
                        </item>
                      </channel>
                    </rss>
                    """
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = Feed(
            url: feedURL,
            siteURL: "https://example.com/original/",
            title: "Original Feed"
        )
        try harness.feedRepository.insert(feed)
        let currentExternalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: feedURL,
                guid: "current-article",
                articleURL: "https://example.com/articles/current",
                title: "Updated Current Article"
            )
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: currentExternalID,
            guid: "current-article",
            url: "https://example.com/articles/current",
            title: "Stale Current Article",
            archivedAt: .distantPast
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "obsolete-article",
            guid: "obsolete-article",
            url: "https://example.com/articles/obsolete",
            title: "Obsolete Article"
        )
        let failingArticleRepository = InterruptingAfterSnapshotArticleRepository(
            backing: harness.articleRepository
        )
        let service = FeedRefreshService(
            logger: TestLogger(),
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedRepository: harness.feedRepository,
            articleRepository: failingArticleRepository,
            feedFetchLogRepository: harness.feedFetchLogRepository
        )

        let result = await service.refresh(feedID: feed.id)

        #expect(result.status == .failed)
        #expect(failingArticleRepository.reconcileFeedSnapshotCallCount == 1)
        #expect(failingArticleRepository.refreshFeedProjectionCallCount == 0)
        #expect(failingArticleRepository.reconcileArticlesCallCount == 0)
        #expect(failingArticleRepository.entryBatchUpsertCallCount == 0)

        let rolledBackFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(rolledBackFeed.title == "Original Feed")
        #expect(rolledBackFeed.siteURL == "https://example.com/original/")
        #expect(rolledBackFeed.lastSuccessfulFetchAt == nil)
        #expect(rolledBackFeed.lastSyncError != nil)

        let rolledBackArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let rolledBackCurrentArticle = try #require(
            rolledBackArticles.first { $0.externalID == currentExternalID }
        )
        let rolledBackObsoleteArticle = try #require(
            rolledBackArticles.first { $0.externalID == "obsolete-article" }
        )
        #expect(rolledBackArticles.count == 2)
        #expect(rolledBackCurrentArticle.title == "Stale Current Article")
        #expect(rolledBackCurrentArticle.archivedAt == .distantPast)
        #expect(rolledBackCurrentArticle.feedTitle == "Original Feed")
        #expect(rolledBackObsoleteArticle.archivedAt == nil)
        #expect(rolledBackObsoleteArticle.feedTitle == "Original Feed")
    }

    @Test
    func cancellationAfterSnapshotUpsertRollsBackFeedAndArticleMutationsBeforeSave() async throws {
        let feedURL = "https://example.com/cancelled-reconciliation-feed.xml"
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .response(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8",
                        "ETag": "\"updated-etag\""
                    ],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Updated Feed",
                        channelLink: "https://example.com/updated/",
                        language: "en",
                        itemTitle: "New Article",
                        itemLink: "https://example.com/articles/new",
                        itemGUID: "new-article",
                        itemDescription: "New summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    )
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = Feed(
            url: feedURL,
            siteURL: "https://example.com/original/",
            title: "Original Feed",
            lastETag: "\"original-etag\"",
            lastSyncError: "Previous error"
        )
        try harness.feedRepository.insert(feed)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "obsolete-article",
            guid: "obsolete-article",
            url: "https://example.com/articles/obsolete",
            title: "Obsolete Article"
        )
        let cancellingArticleRepository = InterruptingAfterSnapshotArticleRepository(
            backing: harness.articleRepository,
            completion: .cancelCurrentTask
        )
        let service = FeedRefreshService(
            logger: TestLogger(),
            feedFetcher: FeedFetcher(
                httpClient: client,
                retryPolicy: FeedRetryPolicy(maxAttempts: 1, baseDelayNanoseconds: 0)
            ),
            feedRepository: harness.feedRepository,
            articleRepository: cancellingArticleRepository,
            feedFetchLogRepository: harness.feedFetchLogRepository
        )

        let result = await service.refresh(feedID: feed.id)

        #expect(result.status == .cancelled)
        #expect(cancellingArticleRepository.reconcileFeedSnapshotCallCount == 1)
        #expect(service.inFlightRefreshTasks[feed.id] == nil)

        let rolledBackFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        #expect(rolledBackFeed.title == "Original Feed")
        #expect(rolledBackFeed.siteURL == "https://example.com/original/")
        #expect(rolledBackFeed.lastETag == "\"original-etag\"")
        #expect(rolledBackFeed.lastSuccessfulFetchAt == nil)
        #expect(rolledBackFeed.lastSyncError == "Previous error")
        #expect(rolledBackFeed.lastFetchedAt != nil)

        let rolledBackArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let rolledBackObsoleteArticle = try #require(rolledBackArticles.first)
        #expect(rolledBackArticles.count == 1)
        #expect(rolledBackObsoleteArticle.externalID == "obsolete-article")
        #expect(rolledBackObsoleteArticle.archivedAt == nil)
        #expect(rolledBackObsoleteArticle.feedTitle == "Original Feed")

        let latestLog = try #require(
            try harness.feedFetchLogRepository.fetchLatestLog(feedID: feed.id)
        )
        #expect(latestLog.status == "cancelled")
    }
}

@MainActor
private final class InterruptingAfterSnapshotArticleRepository: ArticleRepository {
    enum Completion {
        case throwFailure
        case cancelCurrentTask
    }

    private enum InjectedFailure: Error {
        case afterSnapshotMutation
    }

    private let backing: any ArticleRepository
    private let completion: Completion
    private(set) var reconcileFeedSnapshotCallCount = 0
    private(set) var refreshFeedProjectionCallCount = 0
    private(set) var reconcileArticlesCallCount = 0
    private(set) var entryBatchUpsertCallCount = 0

    init(
        backing: any ArticleRepository,
        completion: Completion = .throwFailure
    ) {
        self.backing = backing
        self.completion = completion
    }

    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool) throws -> Int {
        refreshFeedProjectionCallCount += 1
        return try backing.refreshFeedProjection(for: feed, saveAfterOperation: saveAfterOperation)
    }

    func reconcileFeedSnapshot(
        _ entries: [ParsedFeedEntryDTO],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        reconcileFeedSnapshotCallCount += 1
        let result = try backing.reconcileFeedSnapshot(
            entries,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: saveAfterOperation
        )

        switch completion {
        case .throwFailure:
            throw InjectedFailure.afterSnapshotMutation
        case .cancelCurrentTask:
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return result
        }
    }

    func fetchArticle(id: UUID) throws -> Article? {
        try backing.fetchArticle(id: id)
    }

    func fetchArticle(feedID: UUID, externalID: String) throws -> Article? {
        try backing.fetchArticle(feedID: feedID, externalID: externalID)
    }

    func containsArticle(feedID: UUID, externalID: String) throws -> Bool {
        try backing.containsArticle(feedID: feedID, externalID: externalID)
    }

    func fetchArticles(feedID: UUID) throws -> [Article] {
        try backing.fetchArticles(feedID: feedID)
    }

    func fetchArticles(feedID: UUID, sortMode: ArticleSortMode) throws -> [Article] {
        try backing.fetchArticles(feedID: feedID, sortMode: sortMode)
    }

    func fetchInbox(sortMode: ArticleSortMode) throws -> [Article] {
        try backing.fetchInbox(sortMode: sortMode)
    }

    func fetchArchivedArticles() throws -> [Article] {
        try backing.fetchArchivedArticles()
    }

    func fetchRetentionBatch(
        feedID: UUID,
        scope: ArticleRetentionBatchScope,
        offset: Int,
        limit: Int
    ) throws -> [Article] {
        try backing.fetchRetentionBatch(
            feedID: feedID,
            scope: scope,
            offset: offset,
            limit: limit
        )
    }

    func reconcileArticles(
        feedID: UUID,
        keepingExternalIDs: Set<String>,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> Int {
        reconcileArticlesCallCount += 1
        return try backing.reconcileArticles(
            feedID: feedID,
            keepingExternalIDs: keepingExternalIDs,
            fetchedAt: fetchedAt,
            saveAfterOperation: saveAfterOperation
        )
    }

    func upsert(_ entry: ParsedFeedEntryDTO, into feed: Feed, fetchedAt: Date) throws -> Article? {
        try backing.upsert(entry, into: feed, fetchedAt: fetchedAt)
    }

    func upsert(
        _ entries: [ParsedFeedEntryDTO],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> [Article] {
        entryBatchUpsertCallCount += 1
        return try backing.upsert(
            entries,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: saveAfterOperation
        )
    }

    func upsert(_ payload: ArticleUpsertPayload, into feed: Feed) throws -> Article {
        try backing.upsert(payload, into: feed)
    }

    func upsert(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        saveAfterOperation: Bool
    ) throws -> [Article] {
        try backing.upsert(payloads, into: feed, saveAfterOperation: saveAfterOperation)
    }

    func save() throws {
        try backing.save()
    }

    func delete(_ article: Article) throws {
        try backing.delete(article)
    }

    func delete(_ articles: [Article], saveAfterOperation: Bool) throws {
        try backing.delete(articles, saveAfterOperation: saveAfterOperation)
    }
}
