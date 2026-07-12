import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Queries / Article Query Service")
@MainActor
struct ArticleQueryServiceTests {
    @Test
    func articleQueryServiceAppliesListFiltersAndStateOverlay() throws {
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

        let allItems = try queryService.fetchInboxListItems(sortMode: .publishedAtDescending, filter: .all)
        let unreadItems = try queryService.fetchInboxListItems(sortMode: .publishedAtDescending, filter: .unread)
        let starredItems = try queryService.fetchInboxListItems(sortMode: .publishedAtDescending, filter: .starred)
        let hiddenItems = try queryService.fetchInboxListItems(sortMode: .publishedAtDescending, filter: .hidden)

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
    func articleQueryServiceFiltersFolderItemsByStoredFeedFolderName() throws {
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

        let newsItems = try queryService.fetchFolderListItems(
            folderName: "News Folder",
            sortMode: .publishedAtDescending,
            filter: .all
        )

        #expect(newsItems.map { $0.articleExternalID } == ["news-article"])
        #expect(newsItems.first?.feedTitle == "News")
    }

    @Test
    func articleQueryServiceReturnsReaderArticleForExistingHiddenArticleAndNilForMissingArticle() throws {
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

        let listItems = try queryService.fetchInboxListItems(sortMode: .publishedAtDescending, filter: .all)
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
        #expect(readerArticle.articleURL == "https://example.com/hidden-reader")
        #expect(readerArticle.canonicalURL == "https://example.com/canonical")
        #expect(readerArticle.imageURL == "https://example.com/image.jpg")
        #expect(readerArticle.isRead)
        #expect(readerArticle.isStarred)
        #expect(readerArticle.isHidden)
        #expect(missingReaderArticle == nil)
    }

    @Test
    func articleQueryServiceSearchesDocumentedFieldsWithinSelectionScope() throws {
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

        let results = try queryService.fetchArticleSearchResults(
            ArticleSearchRequest(
                selection: .folder("News"),
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending
            )
        )

        #expect(results.map(\.articleExternalID) == ["title-match", "content-text-match", "content-html-match"])
    }

    @Test
    func articleQueryServiceSearchRespectsFilterLimitAndEmptyQueryBehavior() throws {
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

        let limitedUnreadResults = try queryService.fetchArticleSearchResults(
            ArticleSearchRequest(
                selection: .unread,
                sidebarArticleFilter: .allItems,
                query: "needle",
                sortMode: .publishedAtDescending,
                limit: 1
            )
        )
        let emptyQueryResults = try queryService.fetchArticleSearchResults(
            ArticleSearchRequest(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                query: "   ",
                sortMode: .publishedAtDescending,
                emptyQueryBehavior: .returnsEmpty
            )
        )
        let defaultEmptyQueryResults = try queryService.fetchArticleSearchResults(
            ArticleSearchRequest(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                query: "   ",
                sortMode: .publishedAtDescending,
                limit: 2
            )
        )

        #expect(limitedUnreadResults.map(\.articleExternalID) == ["newer"])
        #expect(emptyQueryResults.isEmpty)
        #expect(defaultEmptyQueryResults.map(\.articleExternalID) == ["newer", "older"])
    }

    private func makeQueryService(_ harness: TestHarness) -> DefaultArticleQueryService {
        DefaultArticleQueryService(
            articleRepository: harness.articleRepository,
            articleStateRepository: harness.articleStateRepository
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
        archivedAt: Date? = nil
    ) throws -> Article {
        let article = Article(
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
            fetchedAt: publishedAt ?? Date(timeIntervalSince1970: 0)
        )
        harness.modelContainer.mainContext.insert(article)
        try harness.modelContainer.mainContext.save()
        return article
    }
}
