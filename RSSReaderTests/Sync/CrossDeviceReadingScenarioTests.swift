import Foundation
import Testing
@testable import RSSReader

@Suite("Sync / Cross-Device")
@MainActor
struct CrossDeviceReadingScenarioTests {
    @Test
    func crossDeviceReadingScenarioDeclaresSyncAndMaterializationContract() {
        let scenario = CrossDeviceReadingScenario.current

        #expect(scenario.syncsSourceStructure)
        #expect(scenario.syncsArticleState)
        #expect(scenario.usesLocalArticleCache)
        #expect(scenario.requiresAppAuthorization == false)
        #expect(scenario.materializesArticles(after: .manualRefresh))
        #expect(scenario.materializesArticles(after: .backgroundRefresh))
        #expect(
            scenario.settingsSectionFooter
                == "Feeds, folders, and reading state should sync across devices. Articles stay local to each device and appear after manual or background refresh, without a separate app sign-in."
        )
    }

    @Test
    func crossDeviceManualRefreshMaterializesArticlesAndAppliesSyncedArticleState() async throws {
        let feedURL = "https://example.com/cross-device-feed.xml"
        let articleURL = "https://example.com/articles/cross-device"
        let articleTitle = "Cross-Device Article"
        let articleGUID = "cross-device-article"
        let articleExternalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: feedURL,
                guid: articleGUID,
                articleURL: articleURL,
                title: articleTitle
            )
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Cross Device Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: articleTitle,
                            itemLink: articleURL,
                            itemGUID: articleGUID,
                            itemDescription: "Materialized after manual refresh",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let folder = try harness.folderRepository.insert(Folder(name: "News"))
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Cross Device Feed",
                folder: folder
            )
        )
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: articleExternalID,
            update: ArticleStateUpsert(
                isRead: true,
                readAt: syncedAt,
                isStarred: true,
                starredAt: syncedAt,
                lastInteractionAt: syncedAt,
                updatedAt: syncedAt
            )
        )

        let preRefreshSidebar = try #require(try harness.dependencies.sourcesSidebarQueryService?.fetchSnapshot())
        let preRefreshAllItems = try #require(
            try harness.dependencies.articleQueryService?.fetchInboxListItems(
                sortMode: .publishedAtDescending,
                filter: .all
            )
        )

        #expect(preRefreshSidebar.feeds.count == 1)
        #expect(preRefreshSidebar.feeds.first?.id == feed.id)
        #expect(preRefreshSidebar.feeds.first?.folderName == "News")
        #expect(preRefreshAllItems.isEmpty)

        let refreshResult = await harness.service.refresh(feedID: feed.id)

        #expect(refreshResult.status == .fetched)
        #expect(refreshResult.upsertedEntryCount == 1)

        let postRefreshAllItems = try #require(
            try harness.dependencies.articleQueryService?.fetchInboxListItems(
                sortMode: .publishedAtDescending,
                filter: .all
            )
        )
        let postRefreshUnreadItems = try #require(
            try harness.dependencies.articleQueryService?.fetchInboxListItems(
                sortMode: .publishedAtDescending,
                filter: .unread
            )
        )
        let postRefreshStarredItems = try #require(
            try harness.dependencies.articleQueryService?.fetchInboxListItems(
                sortMode: .publishedAtDescending,
                filter: .starred
            )
        )
        let refreshedArticle = try #require(postRefreshAllItems.first)
        let postRefreshSidebar = try #require(try harness.dependencies.sourcesSidebarQueryService?.fetchSnapshot())

        #expect(postRefreshAllItems.count == 1)
        #expect(refreshedArticle.feedID == feed.id)
        #expect(refreshedArticle.articleExternalID == articleExternalID)
        #expect(refreshedArticle.isRead)
        #expect(refreshedArticle.isStarred)
        #expect(postRefreshUnreadItems.isEmpty)
        #expect(postRefreshStarredItems.map(\.articleExternalID) == [articleExternalID])
        #expect(postRefreshSidebar.unreadSmartCount == 0)
        #expect(postRefreshSidebar.starredSmartCount == 1)
        #expect(postRefreshSidebar.starredFeedIDs == [feed.id])
    }

    @Test
    func crossDeviceBackgroundRefreshMaterializesArticlesAndAppliesSyncedArticleState() async throws {
        let feedURL = "https://example.com/cross-device-background-feed.xml"
        let articleURL = "https://example.com/articles/background-cross-device"
        let articleTitle = "Background Materialized Article"
        let articleGUID = "background-cross-device-article"
        let articleExternalID = ArticleIdentityService.makeExternalID(
            from: ArticleIdentityInput(
                feedURL: feedURL,
                guid: articleGUID,
                articleURL: articleURL,
                title: articleTitle
            )
        )
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/rss+xml; charset=utf-8"
                        ],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Background Cross Device Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: articleTitle,
                            itemLink: articleURL,
                            itemGUID: articleGUID,
                            itemDescription: "Materialized after background refresh",
                            pubDate: "Wed, 03 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let feed = try harness.feedRepository.insert(
            Feed(
                url: feedURL,
                title: "Background Cross Device Feed"
            )
        )
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_100)
        _ = try harness.articleStateRepository.upsert(
            feedID: feed.id,
            articleExternalID: articleExternalID,
            update: ArticleStateUpsert(
                isRead: true,
                readAt: syncedAt,
                isStarred: true,
                starredAt: syncedAt,
                lastInteractionAt: syncedAt,
                updatedAt: syncedAt
            )
        )
        let appSettingsService = try #require(harness.dependencies.appSettingsService)
        _ = try appSettingsService.updateSettings(
            AppSettingsPatch(
                refreshIntervalPreference: .hourly,
                useiCloudSync: true,
                updatedAt: syncedAt
            )
        )
        let backgroundRefreshService = try #require(harness.dependencies.backgroundRefreshService)

        let preRefreshAllItems = try #require(
            try harness.dependencies.articleQueryService?.fetchInboxListItems(
                sortMode: .publishedAtDescending,
                filter: .all
            )
        )
        #expect(preRefreshAllItems.isEmpty)

        let backgroundResult = await backgroundRefreshService.performScheduledRefresh()
        let resolvedBackgroundResult = try #require(backgroundResult)

        #expect(resolvedBackgroundResult.trigger == .background)
        #expect(resolvedBackgroundResult.summary.totalFeedCount == 1)
        #expect(resolvedBackgroundResult.summary.fetchedCount == 1)
        #expect(resolvedBackgroundResult.summary.failedCount == 0)
        #expect(resolvedBackgroundResult.summary.cancelledCount == 0)
        #expect(resolvedBackgroundResult.summary.totalUpsertedEntryCount == 1)

        let postRefreshAllItems = try #require(
            try harness.dependencies.articleQueryService?.fetchInboxListItems(
                sortMode: .publishedAtDescending,
                filter: .all
            )
        )
        let postRefreshUnreadItems = try #require(
            try harness.dependencies.articleQueryService?.fetchInboxListItems(
                sortMode: .publishedAtDescending,
                filter: .unread
            )
        )
        let postRefreshStarredItems = try #require(
            try harness.dependencies.articleQueryService?.fetchInboxListItems(
                sortMode: .publishedAtDescending,
                filter: .starred
            )
        )
        let refreshedArticle = try #require(postRefreshAllItems.first)

        #expect(postRefreshAllItems.count == 1)
        #expect(refreshedArticle.feedID == feed.id)
        #expect(refreshedArticle.articleExternalID == articleExternalID)
        #expect(refreshedArticle.isRead)
        #expect(refreshedArticle.isStarred)
        #expect(postRefreshUnreadItems.isEmpty)
        #expect(postRefreshStarredItems.map(\.articleExternalID) == [articleExternalID])
    }
}
