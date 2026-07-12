import Foundation
import Testing
@testable import RSSReader

@Suite("Sidebar / Query")
@MainActor
struct SidebarQueryServiceTests {
    @Test
    func sidebarQuerySnapshotAggregatesUnreadAndStarredStateForFeeds() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let emptyFolder = try harness.folderRepository.insert(Folder(name: "Empty", sortOrder: 0))
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/sidebar-feed-one.xml",
                "https://example.com/sidebar-feed-two.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)

        let unreadArticle = try harness.insertArticle(
            feed: firstFeed,
            externalID: "sidebar-unread",
            url: "https://example.com/articles/unread",
            title: "Unread Article"
        )
        let starredArticle = try harness.insertArticle(
            feed: secondFeed,
            externalID: "sidebar-starred",
            url: "https://example.com/articles/starred",
            title: "Starred Article"
        )
        _ = try harness.insertArticle(
            feed: secondFeed,
            externalID: "sidebar-read",
            url: "https://example.com/articles/read",
            title: "Read Article"
        )
        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "sidebar-archived-unread",
            url: "https://example.com/articles/archived-unread",
            title: "Archived Unread Article",
            archivedAt: .distantPast
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.toggleStarred(article: starredArticle, at: .now)
        _ = try stateService.markAsRead(feedID: secondFeed.id, articleExternalID: "sidebar-read", at: .now)
        _ = unreadArticle

        let snapshot = try harness.dependencies.sidebarQueryService?.fetchSnapshot()
        let resolvedSnapshot = try #require(snapshot)

        #expect(resolvedSnapshot.folders.map(\.id) == [emptyFolder.id])
        #expect(resolvedSnapshot.folders.map(\.name) == ["Empty"])
        #expect(resolvedSnapshot.feeds.map(\.id) == feeds.map(\.id))
        #expect(resolvedSnapshot.feeds.map(\.unreadCount) == [2, 1])
        #expect(resolvedSnapshot.feeds.map(\.starredCount) == [0, 1])
        #expect(resolvedSnapshot.unreadSmartCount == 3)
        #expect(resolvedSnapshot.starredSmartCount == 1)
        #expect(resolvedSnapshot.starredFeedIDs == [secondFeed.id])
    }
}
