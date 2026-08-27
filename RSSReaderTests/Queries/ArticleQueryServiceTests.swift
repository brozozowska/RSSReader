import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Queries / Article Query Service")
@MainActor
struct ArticleQueryServiceTests {
    @Test
    func articleQueryServiceAppliesListFiltersAndStateOverlay() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let queryService = makeQueryService(harness)

        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "unread",
            title: "Unread Article",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "read",
            title: "Read Article",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "starred",
            title: "Starred Article",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "hidden",
            title: "Hidden Article",
            publishedAt: Date(timeIntervalSince1970: 50)
        )
        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "archived",
            title: "Archived Article",
            publishedAt: Date(timeIntervalSince1970: 25),
            archivedAt: Date(timeIntervalSince1970: 400)
        )

        try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: "read",
            update: ArticleStateUpsert(isRead: true, updatedAt: Date(timeIntervalSince1970: 10))
        )
        try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: "starred",
            update: ArticleStateUpsert(
                isRead: true,
                isStarred: true,
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )
        try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: "hidden",
            update: ArticleStateUpsert(
                isHidden: true,
                updatedAt: Date(timeIntervalSince1970: 30)
            )
        )

        let allItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .inbox,
            filter: .all
        )
        let unreadItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .inbox,
            filter: .unread
        )
        let starredItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .inbox,
            filter: .starred
        )
        let hiddenItems = try harness.articleRepository.fetchArticleQueryRecordScanBatch(
            matching: ArticleQueryCriteria(
                scope: .inbox,
                hidden: .isTrue,
                sortMode: .publishedAtDescending
            ),
            cursor: nil,
            limit: ArticleQueryPaginationPolicy.defaultPageSize
        ).records.map { ArticleListItemDTO(article: $0.article, state: $0.state) }

        #expect(allItems.map { $0.articleExternalID } == ["unread", "read", "starred", "archived"])
        #expect(unreadItems.map { $0.articleExternalID } == ["unread", "archived"])
        #expect(starredItems.map { $0.articleExternalID } == ["starred"])
        #expect(hiddenItems.map { $0.articleExternalID } == ["hidden"])

        let readItem = try #require(allItems.first { $0.articleExternalID == "read" })
        let starredItem = try #require(allItems.first { $0.articleExternalID == "starred" })
        let hiddenItem = try #require(hiddenItems.first)
        let archivedItem = try #require(allItems.first { $0.articleExternalID == "archived" })

        #expect(readItem.isRead)
        #expect(readItem.isStarred == false)
        #expect(starredItem.isRead)
        #expect(starredItem.isStarred)
        #expect(hiddenItem.isHidden)
        #expect(archivedItem.archivedAt != nil)
    }

    @Test
    func articleQueryServiceFiltersFolderItemsByStoredFeedFolderName() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let newsFeed = try insertFeed(
            into: harness,
            url: "https://example.com/news.xml",
            title: "News",
            folderName: "News Folder"
        )
        let techFeed = try insertFeed(
            into: harness,
            url: "https://example.com/tech.xml",
            title: "Tech",
            folderName: "Tech Folder"
        )
        let queryService = makeQueryService(harness)

        _ = try insertArticle(
            into: harness,
            feed: newsFeed,
            externalID: "news-article",
            title: "News Article",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try insertArticle(
            into: harness,
            feed: techFeed,
            externalID: "tech-article",
            title: "Tech Article",
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        let newsItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .folder("News Folder"),
            filter: .all
        )

        #expect(newsItems.map { $0.articleExternalID } == ["news-article"])
        #expect(newsItems.first?.feedTitle == "News")
    }

    @Test
    func articleQueryServiceReturnsExactBaseScopeMetricsIndependentOfPageAndSearch() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let newsFeed = try insertFeed(
            into: harness,
            url: "https://example.com/metric-news.xml",
            title: "Metric News",
            folderName: "Metric Folder"
        )
        let techFeed = try insertFeed(
            into: harness,
            url: "https://example.com/metric-tech.xml",
            title: "Metric Tech"
        )
        let queryService = makeQueryService(harness)

        _ = try insertArticle(
            into: harness,
            feed: newsFeed,
            externalID: "metric-unread",
            title: "Needle Unread",
            publishedAt: Date(timeIntervalSince1970: 500)
        )
        _ = try insertArticle(
            into: harness,
            feed: newsFeed,
            externalID: "metric-archived",
            title: "Archived Unread",
            publishedAt: Date(timeIntervalSince1970: 400),
            archivedAt: Date(timeIntervalSince1970: 600)
        )
        _ = try insertArticle(
            into: harness,
            feed: newsFeed,
            externalID: "metric-starred",
            title: "Starred Read",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        _ = try insertArticle(
            into: harness,
            feed: newsFeed,
            externalID: "metric-hidden",
            title: "Hidden",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try insertArticle(
            into: harness,
            feed: techFeed,
            externalID: "metric-tech-unread",
            title: "Tech Unread",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        try harness.articleStateRepository.upsert(
            feedID: newsFeed.id,
            articleExternalID: "metric-starred",
            update: ArticleStateUpsert(
                isRead: true,
                isStarred: true,
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        )
        try harness.articleStateRepository.upsert(
            feedID: newsFeed.id,
            articleExternalID: "metric-hidden",
            update: ArticleStateUpsert(
                isStarred: true,
                isHidden: true,
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )
        try harness.articleStateRepository.upsert(
            feedID: newsFeed.id,
            articleExternalID: "metric-orphan",
            update: ArticleStateUpsert(
                isStarred: true,
                updatedAt: Date(timeIntervalSince1970: 30)
            )
        )

        let inboxPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                query: "",
                sortMode: .publishedAtDescending,
                limit: 1,
                scopeMetricLoadingPolicy: .baseScope
            )
        )
        let folderPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .folder("Metric Folder"),
                sidebarArticleFilter: .unread,
                query: "",
                sortMode: .publishedAtDescending,
                limit: 1,
                scopeMetricLoadingPolicy: .baseScope
            )
        )
        let feedPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(newsFeed.id),
                sidebarArticleFilter: .starred,
                query: "",
                sortMode: .publishedAtDescending,
                limit: 1,
                scopeMetricLoadingPolicy: .baseScope
            )
        )
        let smartStarredPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .starred,
                sidebarArticleFilter: .allItems,
                query: "",
                sortMode: .publishedAtDescending,
                limit: 1,
                scopeMetricLoadingPolicy: .baseScope
            )
        )
        let searchPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(newsFeed.id),
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending,
                limit: 1
            )
        )

        #expect(inboxPage.articles.count == 1)
        #expect(inboxPage.nextCursor != nil)
        #expect(inboxPage.scopeMetric == ArticleScopeMetric(kind: .unread, count: 3))
        #expect(folderPage.scopeMetric == ArticleScopeMetric(kind: .unread, count: 2))
        #expect(feedPage.scopeMetric == ArticleScopeMetric(kind: .starred, count: 1))
        #expect(smartStarredPage.scopeMetric == ArticleScopeMetric(kind: .starred, count: 1))
        #expect(searchPage.articles.map(\.articleExternalID) == ["metric-unread"])
        #expect(searchPage.scopeMetric == nil)
    }

    @Test
    func articleQueryServiceReturnsReaderArticleForExistingHiddenArticleAndNilForMissingArticle() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let queryService = makeQueryService(harness)
        let article = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "hidden-reader",
            title: "Hidden Reader Article",
            summary: "Readable summary",
            contentHTML: "<p>Readable body</p>",
            contentText: "Readable body",
            author: "Author",
            publishedAt: Date(timeIntervalSince1970: 100),
            updatedAtSource: Date(timeIntervalSince1970: 200),
            canonicalURL: "https://example.com/canonical",
            imageURL: "https://example.com/image.jpg"
        )
        try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: article.externalID,
            update: ArticleStateUpsert(
                isRead: true,
                isStarred: true,
                isHidden: true,
                updatedAt: Date(timeIntervalSince1970: 300)
            )
        )

        let listItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .inbox,
            filter: .all
        )
        let readerArticle = try #require(try queryService.fetchReaderArticle(id: article.id))
        let missingReaderArticle = try queryService.fetchReaderArticle(id: UUID())

        #expect(listItems.isEmpty)
        #expect(readerArticle.id == article.id)
        #expect(readerArticle.articleExternalID == "hidden-reader")
        #expect(readerArticle.title == "Hidden Reader Article")
        #expect(readerArticle.summary == "Readable summary")
        #expect(readerArticle.contentHTML == "<p>Readable body</p>")
        #expect(readerArticle.contentText == "Readable body")
        #expect(readerArticle.author == "Author")
        #expect(readerArticle.effectiveDate == Date(timeIntervalSince1970: 100))
        #expect(readerArticle.articleURL == "https://example.com/hidden-reader")
        #expect(readerArticle.canonicalURL == "https://example.com/canonical")
        #expect(readerArticle.imageURL == "https://example.com/image.jpg")
        #expect(readerArticle.isRead)
        #expect(readerArticle.isStarred)
        #expect(readerArticle.isHidden)
        #expect(missingReaderArticle == nil)
    }

    @Test
    func articleQueryServiceUsesOneEffectiveDateContractAcrossSourceShapes() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let queryService = makeQueryService(harness)
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let publishedWins = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "atom-published-updated",
            title: "Atom Published And Updated",
            publishedAt: Date(timeIntervalSince1970: 400),
            updatedAtSource: Date(timeIntervalSince1970: 900),
            fetchedAt: fetchedAt
        )
        let updatedOnly = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "atom-updated-only",
            title: "Atom Updated Only",
            updatedAtSource: Date(timeIntervalSince1970: 300),
            fetchedAt: fetchedAt
        )
        let rssPublished = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "rss-pub-date",
            title: "RSS Published",
            publishedAt: Date(timeIntervalSince1970: 200),
            fetchedAt: fetchedAt
        )
        let undated = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "undated",
            title: "Undated",
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        let descending = try await fetchAllArticleItems(
            from: queryService,
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            pageSize: 2
        )
        let ascending = try await fetchAllArticleItems(
            from: queryService,
            feedID: feed.id,
            sortMode: .publishedAtAscending,
            pageSize: 2
        )
        let readerArticle = try #require(try queryService.fetchReaderArticle(id: updatedOnly.id))

        #expect(publishedWins.publishedAt == Date(timeIntervalSince1970: 400))
        #expect(publishedWins.updatedAtSource == Date(timeIntervalSince1970: 900))
        #expect(publishedWins.querySortDate == Date(timeIntervalSince1970: 400))
        #expect(updatedOnly.publishedAt == nil)
        #expect(updatedOnly.updatedAtSource == Date(timeIntervalSince1970: 300))
        #expect(updatedOnly.querySortDate == Date(timeIntervalSince1970: 300))
        #expect(rssPublished.querySortDate == Date(timeIntervalSince1970: 200))
        #expect(undated.querySortDate == Date(timeIntervalSince1970: 100))
        #expect(descending.map(\.articleExternalID) == [
            "atom-published-updated", "atom-updated-only", "rss-pub-date", "undated"
        ])
        #expect(descending.map(\.effectiveDate) == [
            Date(timeIntervalSince1970: 400),
            Date(timeIntervalSince1970: 300),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 100)
        ])
        #expect(ascending.map(\.articleExternalID) == [
            "undated", "rss-pub-date", "atom-updated-only", "atom-published-updated"
        ])
        #expect(readerArticle.effectiveDate == updatedOnly.querySortDate)
    }

    @Test
    func articleQueryServicePaginatesUpdatedOnlyDenseTiesByStableIdentityInBothDirections() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let queryService = makeQueryService(harness)
        let tieDate = Date(timeIntervalSince1970: 500)
        let ids = try (1...7).map { index in
            try #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)))
        }

        for (index, id) in ids.reversed().enumerated() {
            _ = try insertArticle(
                into: harness,
                feed: feed,
                id: id,
                externalID: "updated-tie-\(index)",
                title: "Updated Tie \(index)",
                updatedAtSource: tieDate,
                fetchedAt: Date(timeIntervalSince1970: 1_000 + TimeInterval(index))
            )
        }

        let descending = try await fetchAllArticleItems(
            from: queryService,
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            pageSize: 2
        )
        let ascending = try await fetchAllArticleItems(
            from: queryService,
            feedID: feed.id,
            sortMode: .publishedAtAscending,
            pageSize: 2
        )

        #expect(descending.map(\.id) == Array(ids.reversed()))
        #expect(ascending.map(\.id) == ids)
        #expect(descending.allSatisfy { $0.effectiveDate == tieDate })
        #expect(Set(descending.map(\.id)).count == ids.count)
        #expect(Set(ascending.map(\.id)).count == ids.count)
    }

    @Test
    func articleQueryServiceKeepsReaderAndSearchPayloadOutOfPaginatedListSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let queryService = makeQueryService(harness)
        let contentText = "candidate-only-token " + String(repeating: "body ", count: 8_000)
        let article = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "lightweight-list-payload",
            title: "Lightweight List Payload",
            summary: "Row summary",
            contentHTML: "<article><p>Reader HTML body</p></article>",
            contentText: contentText,
            author: "List Author",
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        let snapshot = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                query: "candidate-only-token",
                sortMode: .publishedAtDescending
            )
        )
        let listItem = try #require(snapshot.articles.first)
        let session = ArticleListSession(
            context: ArticleListSession.Context(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems
            ),
            articles: snapshot.articles
        )
        let readerArticle = try #require(try queryService.fetchReaderArticle(id: article.id))
        let listPayloadFieldNames = Set(
            Mirror(reflecting: listItem).children.compactMap(\.label)
        )

        #expect(snapshot.articles.count == 1)
        #expect(session.articles == [listItem])
        #expect(listItem.title == "Lightweight List Payload")
        #expect(listItem.summary == "Row summary")
        #expect(listItem.feedTitle == feed.displayTitle)
        #expect(listItem.author == "List Author")
        #expect(listPayloadFieldNames.isDisjoint(with: [
            "contentHTML", "contentText", "searchableText"
        ]))
        #expect(readerArticle.contentHTML == "<article><p>Reader HTML body</p></article>")
        #expect(readerArticle.contentText == contentText)
    }

    @Test
    func articleQueryServiceSearchesDocumentedFieldsWithinSelectionScope() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let newsFeed = try insertFeed(
            into: harness,
            url: "https://example.com/news.xml",
            title: "News Feed",
            folderName: "News"
        )
        let techFeed = try insertFeed(
            into: harness,
            url: "https://example.com/tech.xml",
            title: "Tech Feed",
            folderName: "Tech"
        )
        let queryService = makeQueryService(harness)

        _ = try insertArticle(
            into: harness,
            feed: newsFeed,
            externalID: "title-match",
            title: "Needle in title",
            publishedAt: Date(timeIntervalSince1970: 600)
        )
        _ = try insertArticle(
            into: harness,
            feed: newsFeed,
            externalID: "content-text-match",
            title: "Article",
            contentText: "Needle in content text",
            publishedAt: Date(timeIntervalSince1970: 500)
        )
        _ = try insertArticle(
            into: harness,
            feed: newsFeed,
            externalID: "content-html-match",
            title: "Article",
            contentHTML: "<p>Needle in <strong>HTML</strong></p>",
            publishedAt: Date(timeIntervalSince1970: 400)
        )
        _ = try insertArticle(
            into: harness,
            feed: techFeed,
            externalID: "outside-folder-match",
            title: "Needle outside folder",
            publishedAt: Date(timeIntervalSince1970: 300)
        )

        let results = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .folder("News"),
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending
            )
        ).articles

        #expect(results.map(\.articleExternalID) == ["title-match", "content-text-match", "content-html-match"])
    }

    @Test
    func articleQueryServiceReusesCanonicalWhitespaceQueryAcrossCandidateScan() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        var observations: [ArticleSearchScanBatchObservation] = []
        let queryService = makeQueryService(harness) { observation in
            observations.append(observation)
        }

        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "canonical-whitespace",
            title: "Café\treader\npolish",
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        let snapshot = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                query: "  Cafe\u{301}   reader\t\npolish  ",
                sortMode: .publishedAtDescending
            )
        )

        #expect(snapshot.articles.map(\.articleExternalID) == ["canonical-whitespace"])
        #expect(observations.isEmpty == false)
        #expect(observations.allSatisfy { $0.normalizedQuery == "Café reader polish" })
    }

    @Test
    func articleQueryServiceSearchRespectsFilterLimitAndEmptyQueryBehavior() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let queryService = makeQueryService(harness)

        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "newer",
            title: "Needle Newer",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "older",
            title: "Needle Older",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "read",
            title: "Needle Read",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: "read",
            update: ArticleStateUpsert(isRead: true, updatedAt: Date(timeIntervalSince1970: 10))
        )

        let limitedUnreadResults = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .unread,
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending,
                limit: 1
            )
        ).articles
        let emptyQueryResults = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                query: "   ",
                sortMode: .publishedAtDescending,
                emptyQueryBehavior: .returnsEmpty
            )
        ).articles
        let defaultEmptyQueryResults = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                query: "   ",
                sortMode: .publishedAtDescending,
                limit: 2
            )
        ).articles
        let noMatchSnapshot = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                query: "absent",
                sortMode: .publishedAtDescending
            )
        )

        #expect(limitedUnreadResults.map(\.articleExternalID) == ["newer"])
        #expect(emptyQueryResults.isEmpty)
        #expect(defaultEmptyQueryResults.map(\.articleExternalID) == ["newer", "older"])
        #expect(noMatchSnapshot.articles.isEmpty)
        #expect(noMatchSnapshot.hasScopeContent)
    }

    @Test
    func articleQueryServiceContinuesBoundedSearchPagesWithoutDuplicateStableIDs() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let queryService = makeQueryService(harness)

        for index in 0..<5 {
            _ = try insertArticle(
                into: harness,
                feed: feed,
                externalID: "search-page-\(index)",
                title: "Needle \(index)",
                publishedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let firstPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending,
                limit: 2
            )
        )
        let firstCursor = try #require(firstPage.nextCursor)
        let secondPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending,
                limit: 2,
                cursor: firstCursor
            )
        )
        let secondCursor = try #require(secondPage.nextCursor)
        let thirdPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending,
                limit: 2,
                cursor: secondCursor
            )
        )
        let allArticles = firstPage.articles + secondPage.articles + thirdPage.articles

        #expect(allArticles.map(\.articleExternalID) == [
            "search-page-4", "search-page-3", "search-page-2", "search-page-1", "search-page-0"
        ])
        #expect(Set(allArticles.map(\.id)).count == allArticles.count)
        #expect(thirdPage.nextCursor == nil)
    }

    @Test
    func articleQueryServiceKeysetPaginationPreservesTiedUnreadIDsAfterEarlierPageMutation() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let queryService = makeQueryService(harness)
        let tieDate = Date(timeIntervalSince1970: 1_000)
        var insertedArticles: [Article] = []

        for index in 0..<7 {
            insertedArticles.append(
                try insertArticle(
                    into: harness,
                    feed: feed,
                    externalID: "mutable-page-\(index)",
                    title: "Mutable needle \(index)",
                    publishedAt: tieDate
                )
            )
        }

        let firstPage = try await queryService.fetchArticleSearchSnapshot(
            ArticleSearchRequest(
                selection: .unread,
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending,
                limit: 2
            )
        )
        let firstCursor = try #require(firstPage.nextCursor)
        for article in firstPage.articles {
            try harness.articleStateRepository.upsert(
                feedID: article.feedID,
                articleExternalID: article.articleExternalID,
                update: ArticleStateUpsert(isRead: true)
            )
        }

        var cursor: ArticleSearchRequest.Cursor? = firstCursor
        var remainingIDs: [UUID] = []
        repeat {
            let snapshot = try await queryService.fetchArticleSearchSnapshot(
                ArticleSearchRequest(
                    selection: .unread,
                    sidebarArticleFilter: .allItems,
                    query: "needle",
                    sortMode: .publishedAtDescending,
                    limit: 2,
                    cursor: cursor
                )
            )
            remainingIDs.append(contentsOf: snapshot.articles.map(\.id))
            cursor = snapshot.nextCursor
        } while cursor != nil

        let expectedRemainingIDs = Set(insertedArticles.map(\.id))
            .subtracting(firstPage.articles.map(\.id))
        #expect(Set(remainingIDs) == expectedRemainingIDs)
        #expect(remainingIDs.count == expectedRemainingIDs.count)
    }

    @Test
    func articleQueryServiceTreatsPreparedSearchableTextAsReadOnlyQueryInput() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let article = try insertArticle(
            into: harness,
            feed: feed,
            externalID: "prepared-searchable-text",
            title: "Article",
            contentHTML: "<p>Raw <strong>HTML-only token</strong></p>"
        )
        article.searchableText = ""
        try harness.modelContainer.mainContext.save()

        let operations = SwiftDataRepositoryOperationCounter()
        let repository = SwiftDataArticleRepository(
            modelContext: harness.modelContainer.mainContext,
            persistenceOperationRecorder: operations.record
        )
        let queryService = DefaultArticleQueryService(
            articleRepository: repository,
            articleStateRepository: harness.articleStateRepository,
            feedRepository: harness.feedRepository
        )
        let request = ArticleSearchRequest(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            query: "html-only token",
            sortMode: .publishedAtDescending
        )

        let results = try await queryService.fetchArticleSearchSnapshot(request).articles

        #expect(results.isEmpty)
        #expect(article.searchableText.isEmpty)
        #expect(operations.saveCount == 0)
    }

    private func makeQueryService(
        _ harness: TestHarness,
        searchScanBatchProbe: ArticleSearchScanBatchProbe? = nil
    ) -> DefaultArticleQueryService {
        DefaultArticleQueryService(
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository,
            feedRepository: harness.feedRepository,
            searchScanBatchProbe: searchScanBatchProbe
        )
    }

    private func insertFeed(
        into harness: TestHarness,
        url: String = "https://example.com/feed.xml",
        title: String = "Example Feed",
        folderName: String? = nil
    ) throws -> Feed {
        let folder: Folder?
        if let folderName {
            folder = try harness.folderRepository.insert(Folder(name: folderName, sortOrder: 0))
        } else {
            folder = nil
        }

        return try harness.feedRepository.insert(
            Feed(
                url: url,
                siteURL: "https://example.com/",
                title: title,
                folder: folder
            )
        )
    }

    private func insertArticle(
        into harness: TestHarness,
        feed: Feed,
        id: UUID = UUID(),
        externalID: String,
        title: String,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        updatedAtSource: Date? = nil,
        canonicalURL: String? = nil,
        imageURL: String? = nil,
        archivedAt: Date? = nil,
        fetchedAt: Date? = nil
    ) throws -> Article {
        let article = Article(
            id: id,
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: externalID,
            url: "https://example.com/\(externalID)",
            canonicalURL: canonicalURL,
            title: title,
            summary: summary,
            contentHTML: contentHTML,
            contentText: contentText,
            author: author,
            publishedAt: publishedAt,
            updatedAtSource: updatedAtSource,
            imageURL: imageURL,
            archivedAt: archivedAt,
            fetchedAt: fetchedAt ?? publishedAt ?? Date(timeIntervalSince1970: 0)
        )
        harness.modelContainer.mainContext.insert(article)
        try harness.modelContainer.mainContext.save()
        return article
    }

    private func fetchAllArticleItems(
        from queryService: DefaultArticleQueryService,
        feedID: UUID,
        sortMode: ArticleSortMode,
        pageSize: Int
    ) async throws -> [ArticleListItemDTO] {
        var cursor: ArticleSearchRequest.Cursor?
        var articles: [ArticleListItemDTO] = []

        repeat {
            let snapshot = try await queryService.fetchArticleSearchSnapshot(
                ArticleSearchRequest(
                    selection: .feed(feedID),
                    sidebarArticleFilter: .allItems,
                    query: "",
                    sortMode: sortMode,
                    limit: pageSize,
                    cursor: cursor
                )
            )
            articles.append(contentsOf: snapshot.articles)
            cursor = snapshot.nextCursor
        } while cursor != nil

        return articles
    }
}
