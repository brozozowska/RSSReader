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
    func sequentialSnapshotsStartRetentionOnlyOnAbsenceAndClearItOnReappearance() async throws {
        let feedURL = "https://example.com/sequential-retention-feed.xml"
        let currentArticleXML = makeValidRSSFeedXML(
            channelTitle: "Sequential Retention Feed",
            channelLink: "https://example.com/sequential/",
            language: "en",
            itemTitle: "Long-Lived Current Article",
            itemLink: "https://example.com/sequential/articles/current",
            itemGUID: "long-lived-current",
            itemDescription: "Still returned despite its old publication date",
            pubDate: "Mon, 01 Jan 2024 10:00:00 GMT"
        )
        let replacementArticleXML = makeValidRSSFeedXML(
            channelTitle: "Sequential Retention Feed",
            channelLink: "https://example.com/sequential/",
            language: "en",
            itemTitle: "Replacement Article",
            itemLink: "https://example.com/sequential/articles/replacement",
            itemGUID: "replacement",
            itemDescription: "Temporarily replaces the long-lived article",
            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
        )
        let client = ScriptedHTTPClient(
            steps: [
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: currentArticleXML
                ),
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: replacementArticleXML
                ),
                .response(statusCode: 304, headers: [:], body: ""),
                .response(
                    statusCode: 200,
                    headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                    body: currentArticleXML
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = Feed(url: feedURL, title: "Sequential Retention Feed")
        try harness.feedRepository.insert(feed)

        let initialResult = await harness.service.refresh(feedID: feed.id)
        let initialArticle = try #require(
            try harness.articleRepository.fetchArticles(feedID: feed.id).first {
                $0.guid == "long-lived-current"
            }
        )
        #expect(initialResult.status == .fetched)
        #expect(initialArticle.archivedAt == nil)

        let disappearanceResult = await harness.service.refresh(feedID: feed.id)
        let archivedArticle = try #require(
            try harness.articleRepository.fetchArticles(feedID: feed.id).first {
                $0.guid == "long-lived-current"
            }
        )
        let firstArchivedAt = try #require(archivedArticle.archivedAt)
        #expect(disappearanceResult.status == .fetched)

        let notModifiedResult = await harness.service.refresh(feedID: feed.id)
        let unchangedArchivedArticle = try #require(
            try harness.articleRepository.fetchArticles(feedID: feed.id).first {
                $0.guid == "long-lived-current"
            }
        )
        #expect(notModifiedResult.status == .notModified)
        #expect(unchangedArchivedArticle.archivedAt == firstArchivedAt)

        let reappearanceResult = await harness.service.refresh(feedID: feed.id)
        let reappearedArticle = try #require(
            try harness.articleRepository.fetchArticles(feedID: feed.id).first {
                $0.guid == "long-lived-current"
            }
        )
        #expect(reappearanceResult.status == .fetched)
        #expect(reappearedArticle.archivedAt == nil)
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
        let reconciliationCheckpoint = ReconciliationCompletionCheckpoint(
            outcome: .failure
        )
        let harness = try TestHarness.make(
            httpClient: client,
            articleReconciliationCancellationCheckpoint: reconciliationCheckpoint.check
        )
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
        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .failed)
        #expect(reconciliationCheckpoint.didInject)

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
        let reconciliationCheckpoint = ReconciliationCompletionCheckpoint(
            outcome: .cancellation
        )
        let harness = try TestHarness.make(
            httpClient: client,
            articleReconciliationCancellationCheckpoint: reconciliationCheckpoint.check
        )
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
        let result = await harness.service.refresh(feedID: feed.id)

        #expect(result.status == .cancelled)
        #expect(reconciliationCheckpoint.didInject)
        #expect(harness.service.inFlightRefreshTasks[feed.id] == nil)

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
private final class ReconciliationCompletionCheckpoint {
    enum Outcome {
        case failure
        case cancellation
    }

    private enum InjectedFailure: Error {
        case afterSnapshotMutation
    }

    private let outcome: Outcome
    private(set) var didInject = false

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func check(_ checkpoint: ArticleFeedSnapshotCancellationCheckpoint) throws {
        try Task.checkCancellation()
        guard checkpoint == .afterUpsert, didInject == false else { return }
        didInject = true

        switch outcome {
        case .failure:
            throw InjectedFailure.afterSnapshotMutation
        case .cancellation:
            throw CancellationError()
        }
    }
}
