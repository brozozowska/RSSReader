import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Feeds / Feed Deletion Service")
@MainActor
struct FeedDeletionServiceTests {
    @Test
    func feedDeletionServiceDeletesFeedArticlesStatesAndFetchLogs() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let deletedFeed = try insertFeed(into: harness, url: "https://example.com/delete.xml")
        let keptFeed = try insertFeed(into: harness, url: "https://example.com/keep.xml")

        _ = try harness.insertArticle(
            feed: deletedFeed,
            externalID: "delete-article-1",
            url: "https://example.com/delete/1",
            title: "Delete Article One"
        )
        _ = try harness.insertArticle(
            feed: deletedFeed,
            externalID: "delete-article-2",
            url: "https://example.com/delete/2",
            title: "Delete Article Two"
        )
        _ = try harness.insertArticle(
            feed: keptFeed,
            externalID: "keep-article",
            url: "https://example.com/keep/1",
            title: "Keep Article"
        )

        try insertArticleState(
            into: harness,
            feedID: deletedFeed.id,
            articleExternalID: "delete-article-1"
        )
        try insertArticleState(
            into: harness,
            feedID: deletedFeed.id,
            articleExternalID: "delete-article-2"
        )
        try insertArticleState(
            into: harness,
            feedID: keptFeed.id,
            articleExternalID: "keep-article"
        )

        _ = try harness.feedFetchLogRepository.insert(
            FeedFetchLogEntry(feedID: deletedFeed.id, status: "success")
        )
        _ = try harness.feedFetchLogRepository.insert(
            FeedFetchLogEntry(feedID: deletedFeed.id, status: "failed")
        )
        _ = try harness.feedFetchLogRepository.insert(
            FeedFetchLogEntry(feedID: keptFeed.id, status: "success")
        )

        try FeedDeletionService.delete(deletedFeed, in: harness.modelContainer.mainContext)

        #expect(try harness.feedRepository.fetchFeed(id: deletedFeed.id) == nil)
        #expect(try harness.feedRepository.fetchFeed(id: keptFeed.id)?.id == keptFeed.id)
        #expect(try articleExternalIDs(in: harness, feedID: deletedFeed.id).isEmpty)
        #expect(try articleExternalIDs(in: harness, feedID: keptFeed.id) == ["keep-article"])
        #expect(try articleStateExternalIDs(in: harness, feedID: deletedFeed.id).isEmpty)
        #expect(try articleStateExternalIDs(in: harness, feedID: keptFeed.id) == ["keep-article"])
        #expect(try harness.feedFetchLogRepository.fetchLogs(feedID: deletedFeed.id, limit: nil).isEmpty)
        #expect(try harness.feedFetchLogRepository.fetchLogs(feedID: keptFeed.id, limit: nil).map(\.status) == ["success"])
    }

    @Test
    func feedDeletionServiceSavesModelContextAfterCascadeDeletion() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try insertFeed(into: harness, url: "https://example.com/save.xml")

        _ = try harness.insertArticle(
            feed: feed,
            externalID: "article",
            url: "https://example.com/article",
            title: "Article"
        )
        try insertArticleState(into: harness, feedID: feed.id, articleExternalID: "article")
        _ = try harness.feedFetchLogRepository.insert(
            FeedFetchLogEntry(feedID: feed.id, status: "success")
        )

        try FeedDeletionService.delete(feed, in: harness.modelContainer.mainContext)

        #expect(harness.modelContainer.mainContext.hasChanges == false)
        #expect(try harness.feedRepository.fetchFeed(id: feed.id) == nil)
        #expect(try articleExternalIDs(in: harness, feedID: feed.id).isEmpty)
        #expect(try articleStateExternalIDs(in: harness, feedID: feed.id).isEmpty)
        #expect(try harness.feedFetchLogRepository.fetchLogs(feedID: feed.id, limit: nil).isEmpty)
    }

    private func insertFeed(
        into harness: TestHarness,
        url: String
    ) throws -> Feed {
        try harness.feedRepository.insert(
            Feed(
                url: url,
                siteURL: "https://example.com/",
                title: url
            )
        )
    }

    private func insertArticleState(
        into harness: TestHarness,
        feedID: UUID,
        articleExternalID: String
    ) throws {
        try harness.articleStateRepository.upsert(
            feedID: feedID,
            articleExternalID: articleExternalID,
            update: ArticleStateUpsert(
                isRead: true,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
    }

    private func articleExternalIDs(
        in harness: TestHarness,
        feedID: UUID
    ) throws -> [String] {
        try harness.articleRepository.fetchArticles(feedID: feedID).map(\.externalID)
    }

    private func articleStateExternalIDs(
        in harness: TestHarness,
        feedID: UUID
    ) throws -> [String] {
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate<ArticleState> { state in
                state.feedID == feedID
            },
            sortBy: [
                SortDescriptor(\ArticleState.articleExternalID, order: .forward)
            ]
        )
        return try harness.modelContainer.mainContext.fetch(descriptor).map(\.articleExternalID)
    }
}
