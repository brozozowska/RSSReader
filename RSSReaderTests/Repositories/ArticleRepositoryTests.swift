import Foundation
import Testing
@testable import RSSReader

@Suite("Repositories / Article")
@MainActor
struct ArticleRepositoryTests {
    @Test
    func articleRepositoryUpsertCreatesAndUpdatesWithoutDuplicates() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let initialFetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedFetchedAt = Date(timeIntervalSince1970: 1_700_000_600)

        let createdArticle = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "article-1",
                guid: "guid-1",
                url: "https://example.com/articles/1",
                title: "Original title",
                summary: "Original summary",
                publishedAtRaw: "Tue, 02 Jan 2024 10:00:00 +0000"
            ),
            into: feed,
            fetchedAt: initialFetchedAt
        )
        let updatedArticle = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "article-1",
                guid: "guid-1-updated",
                url: "https://example.com/articles/1-updated",
                title: "Updated title",
                summary: "Updated summary",
                contentHTML: "<p>Updated HTML</p>",
                author: "Updated Author",
                publishedAtRaw: "Tue, 02 Jan 2024 09:00:00 +0000",
                imageURL: "https://example.com/image.jpg"
            ),
            into: feed,
            fetchedAt: updatedFetchedAt
        )

        let persistedArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        let persistedArticle = try #require(persistedArticles.first)

        #expect(createdArticle?.id == updatedArticle?.id)
        #expect(persistedArticles.count == 1)
        #expect(persistedArticle.externalID == "article-1")
        #expect(persistedArticle.guid == "guid-1-updated")
        #expect(persistedArticle.url == "https://example.com/articles/1-updated")
        #expect(persistedArticle.title == "Updated title")
        #expect(persistedArticle.summary == "Updated summary")
        #expect(persistedArticle.contentHTML == "<p>Updated HTML</p>")
        #expect(persistedArticle.author == "Updated Author")
        #expect(persistedArticle.imageURL == "https://example.com/image.jpg")
        #expect(persistedArticle.fetchedAt == updatedFetchedAt)
    }

    @Test
    func articleRepositoryRefreshFeedProjectionUpdatesStoredFeedFields() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let folder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 0))
        let feed = try insertFeed(
            into: harness,
            title: "Original Feed",
            siteURL: "https://old.example.com/",
            folder: nil
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "article-1",
            url: "https://example.com/articles/1",
            title: "Article"
        )

        feed.title = "Updated Feed"
        feed.displayTitleOverride = "Display Feed"
        feed.siteURL = "https://new.example.com/"
        feed.folder = folder

        let updatedCount = try harness.articleRepository.refreshFeedProjection(for: feed)
        let persistedArticle = try #require(
            try harness.articleRepository.fetchArticle(feedID: feed.id, externalID: "article-1")
        )

        #expect(updatedCount == 3)
        #expect(persistedArticle.feedTitle == "Display Feed")
        #expect(persistedArticle.feedSiteURL == "https://new.example.com/")
        #expect(persistedArticle.feedFolderName == "News")
    }

    @Test
    func articleRepositoryReconcileArchivesMissingArticlesAndReactivatesKeptArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let firstFetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let secondFetchedAt = Date(timeIntervalSince1970: 1_700_000_600)
        let archivedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "archived",
            url: "https://example.com/archived",
            title: "Archived"
        )
        let keptArticle = try harness.insertArticle(
            feed: feed,
            externalID: "kept",
            url: "https://example.com/kept",
            title: "Kept"
        )

        let firstReconcileCount = try harness.articleRepository.reconcileArticles(
            feedID: feed.id,
            keepingExternalIDs: ["kept"],
            fetchedAt: firstFetchedAt
        )

        #expect(firstReconcileCount == 1)
        #expect(archivedArticle.archivedAt == firstFetchedAt)
        #expect(keptArticle.archivedAt == nil)

        let secondReconcileCount = try harness.articleRepository.reconcileArticles(
            feedID: feed.id,
            keepingExternalIDs: [" archived ", "kept"],
            fetchedAt: secondFetchedAt
        )

        #expect(secondReconcileCount == 1)
        #expect(archivedArticle.archivedAt == nil)
        #expect(keptArticle.archivedAt == nil)
    }

    @Test
    func articleRepositoryFetchesFeedAndInboxUsingPublishedAtSortModes() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFeed = try insertFeed(into: harness, url: "https://example.com/first.xml")
        let secondFeed = try insertFeed(into: harness, url: "https://example.com/second.xml")

        _ = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "old",
                url: "https://example.com/old",
                title: "Old",
                publishedAtRaw: "Tue, 02 Jan 2024 09:00:00 +0000"
            ),
            into: firstFeed,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        _ = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "new",
                url: "https://example.com/new",
                title: "New",
                publishedAtRaw: "Tue, 02 Jan 2024 11:00:00 +0000"
            ),
            into: firstFeed,
            fetchedAt: Date(timeIntervalSince1970: 200)
        )
        _ = try harness.articleRepository.upsert(
            makeEntry(
                externalID: "other-feed",
                url: "https://example.com/other",
                title: "Other Feed",
                publishedAtRaw: "Tue, 02 Jan 2024 10:00:00 +0000"
            ),
            into: secondFeed,
            fetchedAt: Date(timeIntervalSince1970: 150)
        )

        let firstFeedDescending = try harness.articleRepository.fetchArticles(
            feedID: firstFeed.id,
            sortMode: .publishedAtDescending
        )
        let firstFeedAscending = try harness.articleRepository.fetchArticles(
            feedID: firstFeed.id,
            sortMode: .publishedAtAscending
        )
        let inboxDescending = try harness.articleRepository.fetchInbox(sortMode: .publishedAtDescending)

        #expect(firstFeedDescending.map { $0.externalID } == ["new", "old"])
        #expect(firstFeedAscending.map { $0.externalID } == ["old", "new"])
        #expect(inboxDescending.map { $0.externalID } == ["new", "other-feed", "old"])
    }

    @Test
    func articleRepositoryDeleteBatchRemovesOnlyRequestedArticles() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness)
        let firstArticle = try harness.insertArticle(
            feed: feed,
            externalID: "delete-1",
            url: "https://example.com/delete-1",
            title: "Delete One"
        )
        let secondArticle = try harness.insertArticle(
            feed: feed,
            externalID: "delete-2",
            url: "https://example.com/delete-2",
            title: "Delete Two"
        )
        let keptArticle = try harness.insertArticle(
            feed: feed,
            externalID: "keep",
            url: "https://example.com/keep",
            title: "Keep"
        )

        try harness.articleRepository.delete([firstArticle, secondArticle])

        let remainingArticles = try harness.articleRepository.fetchArticles(feedID: feed.id)
        #expect(remainingArticles.map { $0.externalID } == [keptArticle.externalID])
    }

    private func insertFeed(
        into harness: TestHarness,
        url: String = "https://example.com/feed.xml",
        title: String = "Example Feed",
        siteURL: String? = "https://example.com/",
        folder: Folder? = nil
    ) throws -> Feed {
        try harness.feedRepository.insert(
            Feed(
                url: url,
                siteURL: siteURL,
                title: title,
                folder: folder
            )
        )
    }

    private func makeEntry(
        externalID: String,
        guid: String? = nil,
        url: String,
        canonicalURL: String? = nil,
        title: String,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        author: String? = nil,
        publishedAtRaw: String? = nil,
        updatedAtRaw: String? = nil,
        imageURL: String? = nil
    ) -> ParsedFeedEntryDTO {
        ParsedFeedEntryDTO(
            externalID: externalID,
            guid: guid,
            url: url,
            canonicalURL: canonicalURL,
            title: title,
            summary: summary,
            contentHTML: contentHTML,
            contentText: contentText,
            author: author,
            publishedAtRaw: publishedAtRaw,
            updatedAtRaw: updatedAtRaw,
            imageURL: imageURL
        )
    }
}
