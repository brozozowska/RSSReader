import Foundation
import Testing
@testable import RSSReader

@Suite("Sidebar / Selection Flow")
@MainActor
struct SidebarSelectionFlowTests {
    @Test
    func sidebarControllerLoadsPersistedLastFeedsRefreshTimestampWithoutRewritingIt() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let lastFeedsRefreshAt = try #require(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 24,
            hour: 17,
            minute: 8
        )))
        _ = try repository.update(
            AppSettingsUpdate(
                lastFeedsRefreshAt: lastFeedsRefreshAt,
                updatedAt: .distantPast
            )
        )
        let controller = SidebarScreenController()

        _ = await controller.loadFeeds(
            showsFullScreenLoading: true,
            dependencies: harness.dependencies,
            currentSelection: nil,
            filter: .allItems,
            refreshedAt: nil
        )

        let persistedSettings = try repository.fetchOrCreate()

        #expect(controller.screenState.refreshStatus == .idle(lastUpdatedAt: lastFeedsRefreshAt))
        #expect(persistedSettings.lastFeedsRefreshAt == lastFeedsRefreshAt)
    }

    @Test
    func folderSelectionInheritsActiveSidebarArticleFilterForSelectedFolder() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/news-feed.xml",
                "https://example.com/tech-feed.xml"
            ]
        )
        let newsFeed = try #require(feeds.first)
        let techFeed = try #require(feeds.last)
        let newsFolder = Folder(name: "News")
        newsFeed.folder = newsFolder
        try harness.saveModelContext()

        let unreadNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-unread",
            url: "https://example.com/news/unread",
            title: "Unread News"
        )
        let starredNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-starred",
            url: "https://example.com/news/starred",
            title: "Starred News"
        )
        let unreadTechArticle = try harness.insertArticle(
            feed: techFeed,
            externalID: "tech-unread",
            url: "https://example.com/tech/unread",
            title: "Unread Tech"
        )
        let readNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-read",
            url: "https://example.com/news/read",
            title: "Read News"
        )
        unreadNewsArticle.publishedAt = Date(timeIntervalSince1970: 200)
        starredNewsArticle.publishedAt = Date(timeIntervalSince1970: 100)
        readNewsArticle.publishedAt = Date(timeIntervalSince1970: 50)
        unreadTechArticle.publishedAt = Date(timeIntervalSince1970: 300)
        unreadNewsArticle.querySortDate = try #require(unreadNewsArticle.publishedAt)
        starredNewsArticle.querySortDate = try #require(starredNewsArticle.publishedAt)
        readNewsArticle.querySortDate = try #require(readNewsArticle.publishedAt)
        unreadTechArticle.querySortDate = try #require(unreadTechArticle.publishedAt)
        try harness.saveModelContext()

        try upsertState(
            harness: harness,
            article: starredNewsArticle,
            update: ArticleStateUpsert(
                isRead: false,
                readAt: nil,
                isStarred: true,
                starredAt: Date(timeIntervalSince1970: 500),
                lastInteractionAt: Date(timeIntervalSince1970: 500),
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        try upsertState(
            harness: harness,
            article: unreadNewsArticle,
            update: ArticleStateUpsert(
                isRead: false,
                readAt: nil,
                isStarred: false,
                starredAt: nil,
                lastInteractionAt: nil,
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        try upsertState(
            harness: harness,
            article: unreadTechArticle,
            update: ArticleStateUpsert(
                isRead: false,
                readAt: nil,
                isStarred: false,
                starredAt: nil,
                lastInteractionAt: nil,
                updatedAt: Date(timeIntervalSince1970: 500)
            )
        )
        try upsertState(
            harness: harness,
            article: readNewsArticle,
            update: ArticleStateUpsert(
                isRead: true,
                readAt: Date(timeIntervalSince1970: 400),
                isStarred: false,
                starredAt: nil,
                lastInteractionAt: Date(timeIntervalSince1970: 400),
                updatedAt: Date(timeIntervalSince1970: 400)
            )
        )

        let queryService = try #require(harness.dependencies.articleQueryService)

        let resolvedUnreadItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .folder(newsFolder.name),
            filter: .unread
        )
        let resolvedStarredItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .folder(newsFolder.name),
            filter: .starred
        )
        let resolvedAllItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .folder(newsFolder.name),
            filter: .all
        )

        #expect(resolvedUnreadItems.map(\.id) == [unreadNewsArticle.id, starredNewsArticle.id])
        #expect(resolvedUnreadItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedUnreadItems.allSatisfy { $0.isRead == false })

        #expect(resolvedStarredItems.map(\.id) == [starredNewsArticle.id])
        #expect(resolvedStarredItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedStarredItems.allSatisfy { $0.isStarred })

        #expect(resolvedAllItems.map(\.id) == [unreadNewsArticle.id, starredNewsArticle.id, readNewsArticle.id])
        #expect(resolvedAllItems.allSatisfy { $0.feedID == newsFeed.id })
    }

    @Test
    func feedSelectionInheritsActiveSidebarArticleFilterForSelectedFeed() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/filter-feed.xml"]).first
        )

        let unreadArticle = try harness.insertArticle(
            feed: feed,
            externalID: "feed-unread",
            url: "https://example.com/feed/unread",
            title: "Unread Feed Article"
        )
        let starredArticle = try harness.insertArticle(
            feed: feed,
            externalID: "feed-starred",
            url: "https://example.com/feed/starred",
            title: "Starred Feed Article"
        )
        let readArticle = try harness.insertArticle(
            feed: feed,
            externalID: "feed-read",
            url: "https://example.com/feed/read",
            title: "Read Feed Article"
        )
        unreadArticle.publishedAt = Date(timeIntervalSince1970: 100)
        starredArticle.publishedAt = Date(timeIntervalSince1970: 200)
        readArticle.publishedAt = Date(timeIntervalSince1970: 300)
        unreadArticle.querySortDate = try #require(unreadArticle.publishedAt)
        starredArticle.querySortDate = try #require(starredArticle.publishedAt)
        readArticle.querySortDate = try #require(readArticle.publishedAt)
        try harness.saveModelContext()

        try upsertState(
            harness: harness,
            article: unreadArticle,
            update: ArticleStateUpsert(
                isRead: false,
                readAt: nil,
                isStarred: false,
                starredAt: nil,
                lastInteractionAt: nil,
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        try upsertState(
            harness: harness,
            article: starredArticle,
            update: ArticleStateUpsert(
                isRead: false,
                readAt: nil,
                isStarred: true,
                starredAt: Date(timeIntervalSince1970: 200),
                lastInteractionAt: Date(timeIntervalSince1970: 200),
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try upsertState(
            harness: harness,
            article: readArticle,
            update: ArticleStateUpsert(
                isRead: true,
                readAt: Date(timeIntervalSince1970: 300),
                isStarred: false,
                starredAt: nil,
                lastInteractionAt: Date(timeIntervalSince1970: 300),
                updatedAt: Date(timeIntervalSince1970: 300)
            )
        )

        let queryService = try #require(harness.dependencies.articleQueryService)

        let resolvedUnreadItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .feed(feed.id),
            filter: .unread
        )
        let resolvedStarredItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .feed(feed.id),
            filter: .starred
        )
        let resolvedAllItems = try await fetchArticleTestPage(
            from: queryService,
            selection: .feed(feed.id),
            filter: .all
        )

        #expect(resolvedUnreadItems.map(\.id) == [starredArticle.id, unreadArticle.id])
        #expect(resolvedUnreadItems.allSatisfy { $0.feedID == feed.id })
        #expect(resolvedUnreadItems.allSatisfy { $0.isRead == false })

        #expect(resolvedStarredItems.map(\.id) == [starredArticle.id])
        #expect(resolvedStarredItems.allSatisfy { $0.feedID == feed.id })
        #expect(resolvedStarredItems.allSatisfy { $0.isStarred })

        #expect(resolvedAllItems.map(\.id) == [readArticle.id, starredArticle.id, unreadArticle.id])
        #expect(resolvedAllItems.allSatisfy { $0.feedID == feed.id })
    }

    @Test
    func sidebarSelectionBehaviorKeepsCurrentFeedSelectionWhenItRemainsVisible() {
        let visibleFeedID = UUID()

        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .feed(visibleFeedID),
            filter: .starred,
            visibleFeedIDs: [visibleFeedID],
            visibleFolderNames: []
        )

        #expect(selection == .feed(visibleFeedID))
    }

    @Test
    func sidebarSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentFeedBecomesHidden() {
        let hiddenFeedID = UUID()

        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .feed(hiddenFeedID),
            filter: .unread,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .unread)
    }

    @Test
    func sidebarSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentSmartSelectionDoesNotMatchFilter() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .inbox,
            filter: .starred,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .starred)
    }

    @Test
    func sidebarSelectionBehaviorKeepsNoSelectionWhenThereIsNoCurrentSelection() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: nil,
            filter: .allItems,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == nil)
    }

    @Test
    func sidebarSelectionBehaviorKeepsCurrentFolderSelectionWhenItRemainsVisible() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .folder("News"),
            filter: .unread,
            visibleFeedIDs: [],
            visibleFolderNames: ["News"]
        )

        #expect(selection == .folder("News"))
    }

    @Test
    func sidebarSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentFolderBecomesHidden() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .folder("News"),
            filter: .starred,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .starred)
    }

    private func upsertState(
        harness: TestHarness,
        article: Article,
        update: ArticleStateUpsert
    ) throws {
        _ = try harness.articleStateRepository.upsert(
            feedID: article.feedID,
            articleExternalID: article.externalID,
            update: update
        )
    }
}
