import Foundation
import SwiftUI
import SwiftData
import Testing
@testable import RSSReader

@MainActor
struct RSSReaderTests {
    @Test
    func appDependenciesExposeSeparateFolderRepositoryWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.folderRepository != nil)
    }

    @Test
    func appDependenciesExposeSourceManagementServiceWhenSwiftDataIsAvailable() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())

        #expect(harness.dependencies.sourceManagementService != nil)
    }

    @Test
    func folderRepositoryPersistsInsertedFoldersAndReturnsSortedList() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.folderRepository)

        _ = try repository.insert(Folder(name: "Archive", sortOrder: 2))
        _ = try repository.insert(Folder(name: "News", sortOrder: 0))
        _ = try repository.insert(Folder(name: "Tech", sortOrder: 1))

        let folders = try repository.fetchAllFolders()
        let techFolder = try repository.fetchFolder(name: "Tech")

        #expect(folders.map(\.name) == ["News", "Tech", "Archive"])
        #expect(folders.map(\.sortOrder) == [0, 1, 2])
        #expect(techFolder?.sortOrder == 1)
    }

    @Test
    func feedRepositoryUpdatesFolderAssignmentThroughExplicitPersistencePath() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let techFolder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let newsFolder = try harness.folderRepository.insert(Folder(name: "News", sortOrder: 1))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/feeds/folder-assignment.xml",
                title: "Folder Assignment Feed",
                kind: .rss
            )
        )

        let techAssignmentDate = Date(timeIntervalSince1970: 1_705_000_000)
        let newsAssignmentDate = techAssignmentDate.addingTimeInterval(60)
        let ungroupedAssignmentDate = newsAssignmentDate.addingTimeInterval(60)

        let techAssignedFeed = try harness.feedRepository.updateFolderAssignment(
            for: feed.id,
            with: FeedFolderAssignmentUpdate(
                folder: techFolder,
                updatedAt: techAssignmentDate
            )
        )
        let techPersistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(techAssignedFeed?.folder?.id == techFolder.id)
        #expect(techAssignedFeed?.updatedAt == techAssignmentDate)
        #expect(techPersistedFeed?.folder?.id == techFolder.id)

        let newsAssignedFeed = try harness.feedRepository.updateFolderAssignment(
            for: feed.id,
            with: FeedFolderAssignmentUpdate(
                folder: newsFolder,
                updatedAt: newsAssignmentDate
            )
        )
        let newsPersistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(newsAssignedFeed?.folder?.id == newsFolder.id)
        #expect(newsAssignedFeed?.updatedAt == newsAssignmentDate)
        #expect(newsPersistedFeed?.folder?.id == newsFolder.id)

        let ungroupedFeed = try harness.feedRepository.updateFolderAssignment(
            for: feed.id,
            with: FeedFolderAssignmentUpdate(
                folder: nil,
                updatedAt: ungroupedAssignmentDate
            )
        )
        let ungroupedPersistedFeed = try harness.feedRepository.fetchFeed(id: feed.id)

        #expect(ungroupedFeed?.folder == nil)
        #expect(ungroupedFeed?.updatedAt == ungroupedAssignmentDate)
        #expect(ungroupedPersistedFeed?.folder == nil)
    }


    @Test
    func folderSelectionInheritsActiveSourcesFilterForSelectedFolder() throws {
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
        let readNewsArticle = try harness.insertArticle(
            feed: newsFeed,
            externalID: "news-read",
            url: "https://example.com/news/read",
            title: "Read News"
        )
        let starredTechArticle = try harness.insertArticle(
            feed: techFeed,
            externalID: "tech-starred",
            url: "https://example.com/tech/starred",
            title: "Starred Tech"
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.toggleStarred(article: starredNewsArticle, at: .now)
        _ = try stateService.markAsRead(article: starredNewsArticle, at: .now)
        _ = try stateService.markAsRead(article: readNewsArticle, at: .now)
        _ = try stateService.toggleStarred(article: starredTechArticle, at: .now)

        let unreadItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .unread
        )
        let resolvedUnreadItems = try #require(unreadItems)

        let starredItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .starred
        )
        let resolvedStarredItems = try #require(starredItems)

        let allItems = try harness.dependencies.articleQueryService?.fetchFolderListItems(
            folderName: "News",
            sortMode: .publishedAtDescending,
            filter: .all
        )
        let resolvedAllItems = try #require(allItems)

        #expect(resolvedUnreadItems.map(\.id) == [unreadNewsArticle.id])
        #expect(resolvedUnreadItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedUnreadItems.allSatisfy { $0.isRead == false })

        #expect(resolvedStarredItems.map(\.id) == [starredNewsArticle.id])
        #expect(resolvedStarredItems.allSatisfy { $0.feedID == newsFeed.id })
        #expect(resolvedStarredItems.allSatisfy { $0.isStarred })

        #expect(resolvedAllItems.map(\.id) == [readNewsArticle.id, starredNewsArticle.id, unreadNewsArticle.id])
        #expect(resolvedAllItems.allSatisfy { $0.feedID == newsFeed.id })
    }

    @Test
    func feedSelectionInheritsActiveSourcesFilterForSelectedSource() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/source-feed.xml"]).first)

        let unreadArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-unread",
            url: "https://example.com/source/unread",
            title: "Unread Source"
        )
        let starredArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-starred",
            url: "https://example.com/source/starred",
            title: "Starred Source"
        )
        let readArticle = try harness.insertArticle(
            feed: feed,
            externalID: "source-read",
            url: "https://example.com/source/read",
            title: "Read Source"
        )

        let stateService = try #require(harness.dependencies.articleStateService)
        _ = try stateService.toggleStarred(article: starredArticle, at: .now)
        _ = try stateService.markAsRead(article: starredArticle, at: .now)
        _ = try stateService.markAsRead(article: readArticle, at: .now)

        let unreadItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .unread
        )
        let resolvedUnreadItems = try #require(unreadItems)

        let starredItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .starred
        )
        let resolvedStarredItems = try #require(starredItems)

        let allItems = try harness.dependencies.articleQueryService?.fetchArticleListItems(
            feedID: feed.id,
            sortMode: .publishedAtDescending,
            filter: .all
        )
        let resolvedAllItems = try #require(allItems)

        #expect(resolvedUnreadItems.map(\.id) == [unreadArticle.id])
        #expect(resolvedUnreadItems.allSatisfy { $0.feedID == feed.id })
        #expect(resolvedUnreadItems.allSatisfy { $0.isRead == false })

        #expect(resolvedStarredItems.map(\.id) == [starredArticle.id])
        #expect(resolvedStarredItems.allSatisfy { $0.feedID == feed.id })
        #expect(resolvedStarredItems.allSatisfy { $0.isStarred })

        #expect(resolvedAllItems.map(\.id) == [readArticle.id, starredArticle.id, unreadArticle.id])
        #expect(resolvedAllItems.allSatisfy { $0.feedID == feed.id })
    }

    @Test
    func sourcesFilterArticleListFilterResolverMapsSourcesFilterToExpectedArticleFilter() {
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .allItems) == .all)
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .unread) == .unread)
        #expect(SourcesFilterArticleListFilterResolver.resolve(for: .starred) == .starred)
    }

    @Test
    func sourcesSmartViewsShowOnlyActiveFilterRow() {
        #expect(SmartSidebarItem.visibleItems(for: .allItems, hasFeeds: true) == [.allItems])
        #expect(SmartSidebarItem.visibleItems(for: .unread, hasFeeds: true) == [.unread])
        #expect(SmartSidebarItem.visibleItems(for: .starred, hasFeeds: true) == [.starred])
    }

    @Test
    func sourcesSmartViewsAreHiddenWhenThereAreNoFeeds() {
        #expect(SmartSidebarItem.visibleItems(for: .allItems, hasFeeds: false).isEmpty)
        #expect(SmartSidebarItem.visibleItems(for: .unread, hasFeeds: false).isEmpty)
        #expect(SmartSidebarItem.visibleItems(for: .starred, hasFeeds: false).isEmpty)
    }

    @Test
    func sourcesSelectionBehaviorKeepsCurrentFeedSelectionWhenItRemainsVisible() {
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
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentFeedBecomesHidden() {
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
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentSmartSelectionDoesNotMatchFilter() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .inbox,
            filter: .starred,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .starred)
    }

    @Test
    func sourcesSelectionBehaviorKeepsNoSelectionWhenThereIsNoCurrentSelection() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: nil,
            filter: .allItems,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == nil)
    }

    @Test
    func sourcesSelectionBehaviorKeepsCurrentFolderSelectionWhenItRemainsVisible() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .folder("News"),
            filter: .unread,
            visibleFeedIDs: [],
            visibleFolderNames: ["News"]
        )

        #expect(selection == .folder("News"))
    }

    @Test
    func sourcesSelectionBehaviorFallsBackToActiveSmartRowWhenCurrentFolderBecomesHidden() {
        let selection = SidebarSelectionBehavior.resolvedSelection(
            currentSelection: .folder("News"),
            filter: .starred,
            visibleFeedIDs: [],
            visibleFolderNames: []
        )

        #expect(selection == .starred)
    }

    @Test
    func sourcesSidebarShowsOnlyFeedsWithStarredArticlesWhenStarredFilterIsActive() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let filteredFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .starred,
            starredFeedIDs: [feedTwoID]
        )

        #expect(filteredFeeds.map(\.id) == [feedTwoID])
    }

    @Test
    func sourcesSidebarKeepsAllFeedsVisibleForAllItemsFilter() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let allItemsFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .allItems,
            starredFeedIDs: [feedTwoID]
        )

        #expect(allItemsFeeds.map(\.id) == feeds.map(\.id))
        #expect(allItemsFeeds.map(\.unreadCount) == feeds.map(\.unreadCount))
    }

    @Test
    func sourcesSidebarShowsOnlyFeedsWithUnreadArticlesWhenUnreadFilterIsActive() {
        let feedOneID = UUID()
        let feedTwoID = UUID()
        let newsFolder = Folder(name: "News")
        let feeds = [
            FeedSidebarItem(
                feed: Feed(id: feedOneID, url: "https://example.com/feed-one.xml", title: "Feed One", folder: newsFolder),
                unreadCount: 2
            ),
            FeedSidebarItem(
                feed: Feed(id: feedTwoID, url: "https://example.com/feed-two.xml", title: "Feed Two"),
                unreadCount: 0
            )
        ]

        let filteredFeeds = SidebarFeedVisibility.filteredFeeds(
            feeds: feeds,
            filter: .unread,
            starredFeedIDs: []
        )

        #expect(filteredFeeds.map(\.id) == [feedOneID])
    }

    @Test
    func sourcesSidebarHidesFoldersSectionWhenFilteredFeedsDoNotContainFolders() {
        let ungroupedFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Ungrouped Feed"),
            unreadCount: 1
        )

        let groups = FolderSidebarGroup.groups(from: [ungroupedFeed])

        #expect(groups.isEmpty)
    }

    @Test
    func sourcesSidebarHidesUngroupedSectionWhenFilteredFeedsDoNotContainUngroupedSources() {
        let folder = Folder(name: "News")
        let groupedFeed = FeedSidebarItem(
            feed: Feed(id: UUID(), url: "https://example.com/feed.xml", title: "Grouped Feed", folder: folder),
            unreadCount: 1
        )

        let ungroupedFeeds = SidebarUngroupedFeeds.visibleFeeds(from: [groupedFeed])

        #expect(ungroupedFeeds.isEmpty)
    }

    @Test
    func shellActionEntryPointsUpdateSelectionAndFilterInAppState() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.showFeed(id: feedID, using: appState)
        harness.dependencies.selectArticle(id: articleID, using: appState)
        harness.dependencies.applySourcesFilter(.unread, using: appState)

        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
        #expect(appState.selectedSourcesFilter == .unread)

        harness.dependencies.showInbox(using: appState)

        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)

        harness.dependencies.showFolder(named: "News", using: appState)

        #expect(appState.selectedSidebarSelection == .folder("News"))
        #expect(appState.selectedArticleID == nil)
        #expect(appState.selectedDetailRoute == .none)

        harness.dependencies.showUnread(using: appState)
        #expect(appState.selectedSidebarSelection == .unread)

        harness.dependencies.showStarred(using: appState)
        #expect(appState.selectedSidebarSelection == .starred)
    }

    @Test
    func settingsPresentationStateLivesInAppStateAndDoesNotResetReadingShellContext() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feedID = UUID()
        let articleID = UUID()

        harness.dependencies.showFeed(id: feedID, using: appState)
        harness.dependencies.selectArticle(id: articleID, using: appState)

        harness.dependencies.showSettings(using: appState)

        #expect(appState.isPresentingSettingsScreen)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))

        harness.dependencies.dismissSettings(using: appState)

        #expect(appState.isPresentingSettingsScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feedID))
        #expect(appState.selectedArticleID == articleID)
        #expect(appState.selectedDetailRoute == .article(articleID))
    }


    @Test
    func shellActionEntryPointsOpenAndCloseArticleWebViewViaDependencies() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/shell-web.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "shell-web-article",
            url: "https://example.com/articles/1",
            title: "Shell Web Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/1/canonical"
        try harness.saveModelContext()
        let readerArticle = try harness.dependencies.articleQueryService?.fetchReaderArticle(id: articleModel.id)
        let article = try #require(readerArticle)

        harness.dependencies.selectArticle(id: article.id, using: appState)
        harness.dependencies.openArticleInWebView(article, using: appState)

        #expect(appState.selectedDetailRoute == .webView(ArticleWebViewRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!)))
        #expect(appState.presentedWebViewRoute == ArticleWebViewRoute(articleID: article.id, url: URL(string: "https://example.com/articles/1/canonical")!))

        harness.dependencies.closePresentedArticleWebView(using: appState)

        #expect(appState.selectedDetailRoute == .article(article.id))
        #expect(appState.presentedWebViewRoute == nil)
    }

    @Test
    func shellActionEntryPointsSelectArticleOpensWebViewWhenDefaultReaderModeIsBrowser() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: ["https://example.com/default-reader-mode.xml"])
        let feed = try #require(feeds.first)
        let articleModel = try harness.insertArticle(
            feed: feed,
            externalID: "default-browser-article",
            url: "https://example.com/articles/browser-mode",
            title: "Default Browser Mode Article"
        )
        articleModel.canonicalURL = "https://example.com/articles/browser-mode/canonical"
        try harness.dependencies.appSettingsRepository?.update(
            AppSettingsUpdate(defaultReaderMode: .browser)
        )
        try harness.saveModelContext()

        harness.dependencies.selectArticle(id: articleModel.id, using: appState)

        #expect(appState.selectedArticleID == articleModel.id)
        #expect(
            appState.selectedDetailRoute == .webView(
                ArticleWebViewRoute(
                    articleID: articleModel.id,
                    url: URL(string: "https://example.com/articles/browser-mode/canonical")!
                )
            )
        )
        #expect(
            appState.presentedWebViewRoute == ArticleWebViewRoute(
                articleID: articleModel.id,
                url: URL(string: "https://example.com/articles/browser-mode/canonical")!
            )
        )
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSourceTriggersReloadAfterFeedRefresh() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/shell-refresh-current.xml": .response(
                    statusCode: 304,
                    headers: ["ETag": "\"etag-shell-current\""],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/shell-refresh-current.xml"]).first)
        let reloadIDBeforeRefresh = appState.articleListReloadID

        harness.dependencies.showFeed(id: feed.id, using: appState)
        let reloadIDAfterSourceSelection = appState.articleListReloadID

        let result = await harness.dependencies.refreshCurrentSource(using: appState)

        #expect(result?.status == .notModified)
        #expect(appState.articleListReloadID != reloadIDAfterSourceSelection)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshAfterAddingFeedRefreshesNewSourceSelectsItAndClosesModalFlow() async throws {
        let feedURL = "https://example.com/shell-refresh-added.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Shell Refreshed Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Shell Refreshed Article",
                            itemLink: "https://example.com/articles/shell-refreshed",
                            itemGUID: "shell-refreshed-article",
                            itemDescription: "Shell refreshed description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let appState = AppState()
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sourcesSidebarReloadID
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Shell Feed",
                kind: .rss
            )
        )

        harness.dependencies.showSourceManagement(using: appState)

        let result = await harness.dependencies.refreshAfterAddingFeed(id: feed.id, using: appState)
        let refreshedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result?.status == .fetched)
        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeRefresh)
        #expect(refreshedFeed.lastFetchedAt != nil)
        #expect(refreshedFeed.lastSuccessfulFetchAt != nil)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Shell Refreshed Article")
    }

    @Test
    func shellActionCompletionHelpersCreateFolderReloadsSidebarAndKeepsModalFlowOpen() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()

        harness.dependencies.showInbox(using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishCreatingFolder(named: "Research", using: appState)

        #expect(appState.isPresentingSourceManagementScreen)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID == articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersMoveSourceReloadsSelectedFeedAndDismissesModalFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-move.xml",
                title: "Helper Move",
                kind: .rss
            )
        )

        harness.dependencies.showFeed(id: feed.id, using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishMovingSource(
            feedID: feed.id,
            previousFolderName: "News",
            updatedFolderName: "Tech",
            using: appState
        )

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersEditFolderRetargetsSelectionAndDismissesModalFlow() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()

        harness.dependencies.showFolder(named: "News", using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishFolderEditing(
            previousName: "News",
            updatedFolderName: "World News",
            using: appState
        )

        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .folder("World News"))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersSaveFeedRefreshesSelectionAndDismissesModalFlow() async throws {
        let feedURL = "https://example.com/helper-save.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: Self.validRSSFeedXML(
                            channelTitle: "Helper Saved Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Helper Saved Article",
                            itemLink: "https://example.com/articles/helper-saved",
                            itemGUID: "helper-saved-article",
                            itemDescription: "Helper saved description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Helper Feed",
                kind: .rss
            )
        )

        harness.dependencies.showInbox(using: appState)
        harness.dependencies.showSourceManagement(using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        let result = await harness.dependencies.finishSavingFeed(id: feed.id, using: appState)
        let articles = try harness.articleRepository.fetchArticles(feedID: feed.id)

        #expect(result?.status == .fetched)
        #expect(appState.isPresentingSourceManagementScreen == false)
        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
        #expect(articles.count == 1)
        #expect(articles.first?.title == "Helper Saved Article")
    }

    @Test
    func shellActionCompletionHelpersUnsubscribeFeedKeepsCurrentSelectionWhenAnotherSourceIsRemoved() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let selectedFeed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-selected.xml",
                title: "Selected Feed",
                kind: .rss
            )
        )
        let removedFeedID = UUID()

        harness.dependencies.showFeed(id: selectedFeed.id, using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishUnsubscribingFeed(id: removedFeedID, using: appState)

        #expect(appState.selectedSidebarSelection == .feed(selectedFeed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionCompletionHelpersDeleteFolderKeepsCurrentSelectionWhenAnotherFolderIsRemoved() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/helper-delete-folder.xml",
                title: "Current Feed",
                kind: .rss
            )
        )

        harness.dependencies.showFeed(id: feed.id, using: appState)
        let sidebarReloadIDBeforeCompletion = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeCompletion = appState.articleListReloadID

        harness.dependencies.finishDeletingFolder(named: "Archived", using: appState)

        #expect(appState.selectedSidebarSelection == .feed(feed.id))
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeCompletion)
        #expect(appState.articleListReloadID != articleReloadIDBeforeCompletion)
    }

    @Test
    func shellActionEntryPointsUnsubscribeFeedRemovesSourceAndResetsSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/unsubscribe.xml",
                title: "Unsubscribe Me",
                kind: .rss
            )
        )
        let sidebarReloadIDBeforeDelete = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeDelete = appState.articleListReloadID

        harness.dependencies.showFeed(id: feed.id, using: appState)
        harness.dependencies.unsubscribeFeed(id: feed.id, using: appState)

        #expect(try harness.feedRepository.fetchFeed(id: feed.id) == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeDelete)
        #expect(appState.articleListReloadID != articleReloadIDBeforeDelete)
    }

    @Test
    func shellActionEntryPointsDeleteFolderUngroupsFeedsAndResetsFolderSelection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let folder = try harness.folderRepository.insert(Folder(name: "Tech", sortOrder: 0))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: "https://example.com/folder-delete.xml",
                title: "Folder Feed",
                kind: .rss,
                folder: folder
            )
        )
        let sidebarReloadIDBeforeDelete = appState.sourcesSidebarReloadID
        let articleReloadIDBeforeDelete = appState.articleListReloadID

        harness.dependencies.showFolder(named: "Tech", using: appState)
        harness.dependencies.deleteFolder(named: "Tech", using: appState)

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))

        #expect(try harness.folderRepository.fetchFolder(name: "Tech") == nil)
        #expect(persistedFeed.folder == nil)
        #expect(appState.selectedSidebarSelection == .inbox)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeDelete)
        #expect(appState.articleListReloadID != articleReloadIDBeforeDelete)
    }

    @Test
    func shellActionEntryPointsRefreshVisibleSourcesTriggersReloadAfterBatchRefresh() async throws {
        let urls = [
            "https://example.com/shell-refresh-all-1.xml",
            "https://example.com/shell-refresh-all-2.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-shell-all-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-shell-all-2\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        _ = try harness.insertFeeds(urls: urls)
        let reloadIDBeforeRefresh = appState.articleListReloadID

        let result = await harness.dependencies.refreshVisibleSources(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != reloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionRefreshesOnlyFolderFeeds() async throws {
        let urls = [
            "https://example.com/folder-refresh-1.xml",
            "https://example.com/folder-refresh-2.xml",
            "https://example.com/folder-refresh-3.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-2\""],
                body: ""
            ),
            urls[2]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-folder-3\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        let feeds = try harness.insertFeeds(urls: urls)
        let techFolder = Folder(name: "Tech")
        feeds[0].folder = techFolder
        feeds[1].folder = techFolder
        try harness.saveModelContext()
        let articleReloadIDBeforeRefresh = appState.articleListReloadID
        let sidebarReloadIDBeforeRefresh = appState.sourcesSidebarReloadID

        harness.dependencies.showFolder(named: "Tech", using: appState)

        let result = await harness.dependencies.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
        #expect(appState.articleListReloadID != articleReloadIDBeforeRefresh)
        #expect(appState.sourcesSidebarReloadID != sidebarReloadIDBeforeRefresh)
    }

    @Test
    func shellActionEntryPointsRefreshCurrentSelectionRefreshesAllFeedsForInbox() async throws {
        let urls = [
            "https://example.com/inbox-refresh-1.xml",
            "https://example.com/inbox-refresh-2.xml"
        ]
        let responses = [
            urls[0]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-inbox-1\""],
                body: ""
            ),
            urls[1]: ScriptedHTTPClient.Step.response(
                statusCode: 304,
                headers: ["ETag": "\"etag-inbox-2\""],
                body: ""
            )
        ]
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient(responsesByURL: responses))
        let appState = AppState()
        _ = try harness.insertFeeds(urls: urls)

        harness.dependencies.showInbox(using: appState)

        let result = await harness.dependencies.refreshCurrentSelection(using: appState)

        #expect(result?.summary.totalFeedCount == 2)
        #expect(result?.summary.notModifiedCount == 2)
    }

    @Test
    func feedNormalizationKeepsFaviconLikeIconURLAndNormalizesIt() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "HTTPS://Example.com",
                iconURL: "HTTPS://CDN.EXAMPLE.COM/Favicon-32x32.png?cache=1#fragment"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.siteURL == "https://example.com/")
        #expect(normalized.metadata.iconURL == "https://cdn.example.com/Favicon-32x32.png?cache=1")
    }

    @Test
    func feedNormalizationRewritesLogoAssetToSiteFaviconWhenSiteURLIsKnown() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "https://example.com/news/",
                iconURL: "https://cdn.example.com/assets/header-logo.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func feedNormalizationKeepsOriginalIconURLWhenItCannotBuildSiteFaviconFallback() {
        let feed = ParsedFeedDTO(
            kind: .atom,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                iconURL: "https://cdn.example.com/assets/banner-logo.png"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.iconURL == "https://cdn.example.com/assets/banner-logo.png")
    }

    @Test
    func feedNormalizationUsesSiteFaviconWhenFeedDidNotProvideIconURL() {
        let feed = ParsedFeedDTO(
            kind: .rss,
            metadata: ParsedFeedMetadataDTO(
                title: "Example Feed",
                siteURL: "HTTPS://Example.com/news"
            ),
            entries: []
        )

        let normalized = FeedNormalizationService.normalize(feed, feedURL: "https://example.com/feed.xml")

        #expect(normalized.metadata.siteURL == "https://example.com/news")
        #expect(normalized.metadata.iconURL == "https://example.com/favicon.ico")
    }

    @Test
    func sourceIconCacheReturnsCachedDataWithoutSecondNetworkRequest() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .response(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary"
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient)

        let firstLoad = try await service.imageData(for: iconURL)
        let secondLoad = try await service.imageData(for: iconURL)

        #expect(firstLoad == Data("icon-binary".utf8))
        #expect(secondLoad == firstLoad)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
    }

    @Test
    func sourceIconCacheSharesInFlightRequestBetweenConcurrentConsumers() async throws {
        let iconURL = try #require(URL(string: "https://example.com/favicon.ico"))
        let httpClient = ScriptedHTTPClient(
            responsesByURL: [
                iconURL.absoluteString: .delayedResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "image/x-icon"],
                    body: "icon-binary",
                    delayNanoseconds: 50_000_000
                )
            ]
        )
        let service = SourceIconCacheService(httpClient: httpClient)

        async let firstLoad = service.imageData(for: iconURL)
        async let secondLoad = service.imageData(for: iconURL)
        let (firstResult, secondResult) = try await (firstLoad, secondLoad)

        #expect(firstResult == secondResult)

        let requests = await httpClient.recordedRequests()
        #expect(requests.count == 1)
        #expect(await httpClient.maxConcurrentExecutions() == 1)
    }
}
