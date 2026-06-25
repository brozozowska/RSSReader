import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Loading")
@MainActor
struct ArticlesScreenControllerLoadingTests {
    @Test
    func articlesScreenControllerLoadsFeedArticlesForCurrentSelection() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-load.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-load-article",
            url: "https://example.com/articles/controller-load",
            title: "Controller Load"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.navigationTitle == "controller-load.xml")
        #expect(controller.screenState.articles.count == 1)
        #expect(controller.screenState.articles.first?.title == "Controller Load")
    }

    @Test
    func articlesScreenControllerExcludesArchivedArticlesForCurrentSelection() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-archive.xml"]).first)
        let archivedAt = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-archived-article",
            url: "https://example.com/articles/controller-archived",
            title: "Controller Archived",
            archivedAt: archivedAt
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-current-article",
            url: "https://example.com/articles/controller-current",
            title: "Controller Current"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.count == 1)
        #expect(controller.screenState.articles.contains { $0.title == "Controller Archived" } == false)
        #expect(controller.screenState.articles.contains { $0.title == "Controller Current" && $0.archivedAt == nil })
    }

    @Test
    func articlesScreenControllerUsesFeedDisplayTitleOverrideForNavigationTitle() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = Feed(
            url: "https://example.com/display-title.xml",
            title: "XML Feed Title",
            displayTitleOverride: "My Feed"
        )
        try harness.feedRepository.insert(feed)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "display-title-article",
            url: "https://example.com/articles/display-title",
            title: "Display Title Article"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.navigationTitle == "My Feed")
    }

    @Test
    func articlesScreenControllerUsesUnreadCountForFeedNavigationSubtitle() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = Feed(
            url: "https://example.com/last-refresh.xml",
            title: "Last Refresh"
        )
        try harness.feedRepository.insert(feed)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "last-refresh-article",
            url: "https://example.com/articles/last-refresh",
            title: "Last Refresh Article"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 1))
    }

    @Test
    func articlesScreenControllerUsesNewestFirstForAllItemsRegardlessOfUnreadSortSetting() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/all-items-sort.xml"]).first)
        let oldDate = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let newDate = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 2)))
        let oldArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: "all-items-old",
            url: "https://example.com/articles/all-items-old",
            title: "Old Article",
            publishedAt: oldDate,
            fetchedAt: oldDate
        )
        let newArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: "all-items-new",
            url: "https://example.com/articles/all-items-new",
            title: "New Article",
            publishedAt: newDate,
            fetchedAt: newDate
        )
        harness.modelContainer.mainContext.insert(oldArticle)
        harness.modelContainer.mainContext.insert(newArticle)
        try harness.modelContainer.mainContext.save()
        _ = try repository.update(AppSettingsUpdate(unreadArticleSortMode: .publishedAtAscending))
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.articles.map(\.id) == [newArticle.id, oldArticle.id])
    }

    @Test
    func articlesScreenControllerUsesUnreadSortSettingForUnreadFilter() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let repository = try #require(harness.dependencies.appSettingsRepository)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/unread-sort.xml"]).first)
        let oldDate = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let newDate = try #require(Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 2)))
        let oldArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: "unread-old",
            url: "https://example.com/articles/unread-old",
            title: "Old Unread Article",
            publishedAt: oldDate,
            fetchedAt: oldDate
        )
        let newArticle = Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: "unread-new",
            url: "https://example.com/articles/unread-new",
            title: "New Unread Article",
            publishedAt: newDate,
            fetchedAt: newDate
        )
        harness.modelContainer.mainContext.insert(oldArticle)
        harness.modelContainer.mainContext.insert(newArticle)
        try harness.modelContainer.mainContext.save()
        _ = try repository.update(AppSettingsUpdate(unreadArticleSortMode: .publishedAtAscending))
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.articles.map(\.id) == [oldArticle.id, newArticle.id])
    }
}
