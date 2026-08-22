import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Article State")
@MainActor
struct ArticleStateServiceTests {
    @Test
    func articleStateReadUnreadTransitionUpdatesStateAndInteractionTimestamps() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-read.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "state-read-article",
            url: "https://example.com/state-read/articles/1",
            title: "State Read Article"
        )
        let baseTime = Date().addingTimeInterval(60)
        let readAt = baseTime
        let unreadAt = baseTime.addingTimeInterval(600)

        let readSnapshot = try harness.articleStateService.markAsRead(article: article, at: readAt)
        let unreadSnapshot = try harness.articleStateService.markAsUnread(article: article, at: unreadAt)

        #expect(readSnapshot.isRead == true)
        #expect(readSnapshot.readAt == readAt)
        #expect(readSnapshot.lastInteractionAt == readAt)
        #expect(readSnapshot.updatedAt == readAt)

        #expect(unreadSnapshot.isRead == false)
        #expect(unreadSnapshot.readAt == nil)
        #expect(unreadSnapshot.lastInteractionAt == unreadAt)
        #expect(unreadSnapshot.updatedAt == unreadAt)

        let persistedSnapshot = try harness.articleStateService.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        let state = try #require(persistedSnapshot)
        #expect(state.isRead == false)
        #expect(state.readAt == nil)
        #expect(state.lastInteractionAt == unreadAt)
        #expect(state.updatedAt == unreadAt)
    }

    @Test
    func articleStateToggleStarredTransitionsOnAndOffWithFreshTimestamps() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-star.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "state-star-article",
            url: "https://example.com/state-star/articles/1",
            title: "State Star Article"
        )
        let baseTime = Date().addingTimeInterval(60)
        let starredAt = baseTime
        let unstarredAt = baseTime.addingTimeInterval(300)

        let starredSnapshot = try harness.articleStateService.toggleStarred(article: article, at: starredAt)
        let unstarredSnapshot = try harness.articleStateService.toggleStarred(article: article, at: unstarredAt)

        #expect(starredSnapshot.isStarred == true)
        #expect(starredSnapshot.starredAt == starredAt)
        #expect(starredSnapshot.lastInteractionAt == starredAt)
        #expect(starredSnapshot.updatedAt == starredAt)

        #expect(unstarredSnapshot.isStarred == false)
        #expect(unstarredSnapshot.starredAt == nil)
        #expect(unstarredSnapshot.lastInteractionAt == unstarredAt)
        #expect(unstarredSnapshot.updatedAt == unstarredAt)
    }

    @Test
    func articleStateBulkMarkAllVisibleAsReadMarksArticlesAcrossFeeds() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/state-bulk-1.xml",
                "https://example.com/state-bulk-2.xml"
            ]
        )
        let firstArticle = try harness.insertArticle(
            feed: feeds[0],
            externalID: "bulk-article-1",
            url: "https://example.com/state-bulk-1/articles/1",
            title: "Bulk Article One"
        )
        let secondArticle = try harness.insertArticle(
            feed: feeds[0],
            externalID: "bulk-article-2",
            url: "https://example.com/state-bulk-1/articles/2",
            title: "Bulk Article Two"
        )
        let thirdArticle = try harness.insertArticle(
            feed: feeds[1],
            externalID: "bulk-article-3",
            url: "https://example.com/state-bulk-2/articles/1",
            title: "Bulk Article Three"
        )
        let actionAt = Date().addingTimeInterval(60)

        let snapshots = try harness.articleStateService.markAllVisibleAsRead(
            [firstArticle, secondArticle, thirdArticle],
            at: actionAt
        )

        #expect(snapshots.count == 3)
        #expect(snapshots.allSatisfy { $0.isRead })
        #expect(snapshots.allSatisfy { $0.readAt == actionAt })
        #expect(snapshots.allSatisfy { $0.lastInteractionAt == actionAt })
        #expect(snapshots.allSatisfy { $0.updatedAt == actionAt })

        let persistedSnapshots = try harness.articleStateService.fetchStateSnapshots(
            for: [firstArticle, secondArticle, thirdArticle]
        )
        #expect(persistedSnapshots.count == 3)
        #expect(Array(persistedSnapshots.values).allSatisfy { $0.isRead })
        #expect(persistedSnapshots.values.allSatisfy { $0.readAt == actionAt })
    }

    @Test
    func articleStateMarksMatchingUnreadScopeInBoundedBatchesAndIsIdempotent() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/state-scope.xml"]).first
        )
        let unreadStarredArticles = try (0..<3).map { index in
            try harness.insertArticle(
                feed: feed,
                externalID: "scope-starred-\(index)",
                url: "https://example.com/state-scope/articles/\(index)",
                title: "Scope Starred \(index)"
            )
        }
        let unreadNotStarred = try harness.insertArticle(
            feed: feed,
            externalID: "scope-not-starred",
            url: "https://example.com/state-scope/articles/not-starred",
            title: "Scope Not Starred"
        )
        for article in unreadStarredArticles {
            _ = try harness.articleStateService.toggleStarred(article: article, at: .distantPast)
        }
        let request = ArticleSearchRequest(
            selection: .starred,
            sidebarArticleFilter: .allItems,
            query: "",
            sortMode: .publishedAtDescending,
            limit: 1,
            requiresUnread: true
        )
        let queryService = try #require(harness.dependencies.articleQueryService)

        let firstResult = try await harness.articleStateService.markAllMatchingAsRead(
            request: request,
            articleQueryService: queryService,
            at: .now
        )
        let repeatedResult = try await harness.articleStateService.markAllMatchingAsRead(
            request: request,
            articleQueryService: queryService,
            at: .now
        )

        #expect(firstResult.processedIdentityCount == 3)
        #expect(firstResult.persistedReadCount == 3)
        #expect(firstResult.rejectedIdentityCount == 0)
        #expect(firstResult.processedBatchCount == 3)
        #expect(repeatedResult.processedIdentityCount == 0)
        #expect(repeatedResult.processedBatchCount == 0)
        for article in unreadStarredArticles {
            #expect(
                try harness.articleStateRepository.fetchStateSnapshot(
                    feedID: feed.id,
                    articleExternalID: article.externalID
                )?.isRead == true
            )
        }
        #expect(
            try harness.articleStateRepository.fetchStateSnapshot(
                feedID: feed.id,
                articleExternalID: unreadNotStarred.externalID
            ) == nil
        )
    }

    @Test
    func articleStateRejectsStaleTransitionWhenUpdatedAtIsOlderThanCurrentState() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/state-lww.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "state-lww-article",
            url: "https://example.com/state-lww/articles/1",
            title: "State LWW Article"
        )
        let newerTimestamp = Date().addingTimeInterval(120)
        let olderTimestamp = Date().addingTimeInterval(60)

        _ = try harness.articleStateService.markAsRead(article: article, at: newerTimestamp)
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: article.externalID,
            update: ArticleStateUpsert(
                isRead: false,
                readAt: nil,
                lastInteractionAt: olderTimestamp,
                updatedAt: olderTimestamp
            )
        )

        let persistedSnapshot = try harness.articleStateService.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )
        let state = try #require(persistedSnapshot)
        #expect(state.isRead == true)
        #expect(state.readAt == newerTimestamp)
        #expect(state.lastInteractionAt == newerTimestamp)
        #expect(state.updatedAt == newerTimestamp)
    }
}
