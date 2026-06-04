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
}
