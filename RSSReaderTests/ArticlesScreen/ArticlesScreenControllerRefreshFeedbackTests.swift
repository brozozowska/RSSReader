import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Refresh Feedback")
@MainActor
struct ArticlesScreenControllerRefreshFeedbackTests {
    func articlesScreenControllerPresentsRefreshFailureFromBatchRefreshResult() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/controller-refresh.xml": .response(
                    statusCode: 500,
                    headers: [:],
                    body: ""
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-refresh.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-refresh-article",
            url: "https://example.com/articles/controller-refresh",
            title: "Controller Refresh"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)

        await controller.refreshCurrentSelection(
            selection: .feed(feed.id),
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.refreshFeedback?.message.contains("invalidStatusCode") == true)
    }

    @Test
    func articlesScreenControllerCanPreserveRefreshFailureDuringPostRefreshReload() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-refresh-preserve.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-refresh-preserve-article",
            url: "https://example.com/articles/controller-refresh-preserve",
            title: "Controller Refresh Preserve"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        controller.screenState.presentRefreshFailure("Refresh failed")

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: false,
            retainedSessionMembershipStatus: .retainedAfterRefresh,
            preservesRefreshFeedback: true
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.title) == ["Controller Refresh Preserve"])
        #expect(controller.screenState.refreshFeedback == ArticlesScreenRefreshFeedback(message: "Refresh failed"))
    }

    @Test
    func articlesScreenControllerClearsPreviousRefreshErrorAfterSuccessfulRefresh() async throws {
        let client = ScriptedHTTPClient(
            responsesByURL: [
                "https://example.com/controller-refresh-success.xml": .response(
                    statusCode: 200,
                    headers: [
                        "Content-Type": "application/rss+xml; charset=utf-8"
                    ],
                    body: makeValidRSSFeedXML(
                        channelTitle: "Refresh Success Feed",
                        channelLink: "https://example.com/refresh-success/",
                        language: "en",
                        itemTitle: "Refreshed Article",
                        itemLink: "https://example.com/articles/refreshed",
                        itemGUID: "refreshed-article",
                        itemDescription: "Readable summary",
                        pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                    )
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let appState = AppState()
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-refresh-success.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "controller-refresh-success-article",
            url: "https://example.com/articles/controller-refresh-success",
            title: "Controller Refresh Success"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        controller.screenState.presentRefreshFailure("Previous refresh failed")
        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)

        await controller.refreshCurrentSelection(
            selection: .feed(feed.id),
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func articlesScreenControllerClearsStaleRefreshErrorWhenSelectionChanges() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let firstFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-selection-a.xml"]).first)
        let secondFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/controller-selection-b.xml"]).first)

        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "controller-selection-a-article",
            url: "https://example.com/articles/controller-selection-a",
            title: "First Selection"
        )
        _ = try harness.insertArticle(
            feed: secondFeed,
            externalID: "controller-selection-b-article",
            url: "https://example.com/articles/controller-selection-b",
            title: "Second Selection"
        )

        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(firstFeed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        controller.screenState.presentRefreshFailure("Refresh failed for first feed")

        await controller.load(
            selection: .feed(secondFeed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.selection == .feed(secondFeed.id))
        #expect(controller.screenState.articles.first?.title == "Second Selection")
        #expect(controller.screenState.refreshFeedback == nil)
    }
}
