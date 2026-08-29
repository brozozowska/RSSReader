import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Refresh Feedback")
@MainActor
struct ArticlesScreenControllerRefreshFeedbackTests {
    @Test
    func smartStarredSuccessRefreshesAllFeedsWithoutGenericFailureFromStaleAppState() async throws {
        let urls = [
            "https://example.com/starred-success-a.xml",
            "https://example.com/starred-success-b.xml"
        ]
        let client = ScriptedHTTPClient(
            responsesByURL: Dictionary(
                uniqueKeysWithValues: urls.map { url in
                    (url, .response(statusCode: 304, headers: [:], body: ""))
                }
            )
        )
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: urls)
        let controller = ArticlesScreenController()
        let appState = AppState()
        harness.dependencies.appActions.showFeed(id: feeds[0].id, using: appState)

        await controller.load(
            selection: .starred,
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )
        let result = await controller.refreshCurrentSelection(
            selection: .starred,
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(result?.isCompleteSuccess == true)
        #expect(result?.targetFeedIDs == feeds.map(\.id))
        #expect(await client.recordedRequests().count == feeds.count)
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func feedStarredRefreshUsesDisplayedFeedInsteadOfStaleAppStateSelection() async throws {
        let displayedURL = "https://example.com/starred-displayed-feed.xml"
        let staleURL = "https://example.com/starred-stale-feed.xml"
        let client = ScriptedHTTPClient(
            responsesByURL: [
                displayedURL: .response(statusCode: 304, headers: [:], body: ""),
                staleURL: .response(statusCode: 500, headers: [:], body: "")
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: [displayedURL, staleURL])
        let displayedFeed = feeds[0]
        let staleFeed = feeds[1]
        let controller = ArticlesScreenController()
        let appState = AppState()
        harness.dependencies.appActions.showFeed(id: staleFeed.id, using: appState)

        await controller.load(
            selection: .feed(displayedFeed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )
        let result = await controller.refreshCurrentSelection(
            selection: .feed(displayedFeed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            appState: appState
        )
        let requestedURLs = await client.recordedRequests().map { $0.url.absoluteString }

        #expect(result?.targetFeedIDs == [displayedFeed.id])
        #expect(result?.isCompleteSuccess == true)
        #expect(requestedURLs == [displayedURL])
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func folderStarredPartialFailureRetriesOnlyFailedDisplayedScope() async throws {
        let urls = [
            "https://example.com/starred-folder-success.xml",
            "https://example.com/starred-folder-retry.xml",
            "https://example.com/starred-folder-outside.xml"
        ]
        let client = ScriptedHTTPClient(
            responseSequencesByURL: [
                urls[0]: [.response(statusCode: 304, headers: [:], body: "")],
                urls[1]: [
                    .response(statusCode: 500, headers: [:], body: ""),
                    .response(statusCode: 304, headers: [:], body: "")
                ],
                urls[2]: [.response(statusCode: 500, headers: [:], body: "")]
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: urls)
        let folder = Folder(name: "Starred Folder")
        feeds[0].folder = folder
        feeds[1].folder = folder
        try harness.saveModelContext()
        let controller = ArticlesScreenController()
        let appState = AppState()
        harness.dependencies.appActions.showStarred(using: appState)
        harness.dependencies.appActions.applySidebarArticleFilter(.starred, using: appState)

        await controller.load(
            selection: .folder(folder.name),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )
        let initialResult = await controller.refreshCurrentSelection(
            selection: .folder(folder.name),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            appState: appState
        )
        let retryResult = await controller.refreshCurrentSelection(
            selection: .folder(folder.name),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies,
            appState: appState
        )
        let requestCounts = Dictionary(
            grouping: await client.recordedRequests().map { $0.url.absoluteString },
            by: { $0 }
        ).mapValues(\.count)

        #expect(Set(initialResult?.targetFeedIDs ?? []) == Set([feeds[0].id, feeds[1].id]))
        #expect(initialResult?.retryFeedIDs == [feeds[1].id])
        #expect(retryResult?.targetFeedIDs == [feeds[1].id])
        #expect(retryResult?.isCompleteSuccess == true)
        #expect(requestCounts[urls[0]] == 1)
        #expect(requestCounts[urls[1]] == 2)
        #expect(requestCounts[urls[2]] == nil)
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func articlesScreenAllFeedsRetryRefreshesOnlyFailedTargetsAndClearsFeedback() async throws {
        let successfulFeedURL = "https://example.com/articles-retry-success.xml"
        let retriedFeedURL = "https://example.com/articles-retry-failed.xml"
        let client = ScriptedHTTPClient(
            responseSequencesByURL: [
                successfulFeedURL: [
                    .response(statusCode: 304, headers: [:], body: "")
                ],
                retriedFeedURL: [
                    .response(statusCode: 500, headers: [:], body: ""),
                    .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Retried Articles Feed",
                            channelLink: "https://example.com/articles-retry/",
                            language: "en",
                            itemTitle: "Retried Articles Item",
                            itemLink: "https://example.com/articles-retry/item",
                            itemGUID: "retried-articles-item",
                            itemDescription: "Retry succeeds",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        _ = try harness.insertFeeds(urls: [successfulFeedURL, retriedFeedURL])
        let controller = ArticlesScreenController()
        let appState = AppState()
        harness.dependencies.appActions.showInbox(using: appState)

        await controller.load(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let initialResult = await controller.refreshCurrentSelection(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            appState: appState
        )

        #expect(initialResult?.retryFeedIDs.count == 1)
        #expect(controller.screenState.refreshFeedback != nil)

        let retryResult = await controller.refreshCurrentSelection(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            appState: appState
        )
        let requests = await client.recordedRequests()
        let requestCounts = Dictionary(grouping: requests.map { $0.url.absoluteString }, by: { $0 })
            .mapValues(\.count)

        #expect(retryResult?.isCompleteSuccess == true)
        #expect(retryResult?.targetFeedIDs.count == 1)
        #expect(requestCounts[successfulFeedURL] == 1)
        #expect(requestCounts[retriedFeedURL] == 2)
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
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
            sidebarArticleFilter: .allItems,
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
            sidebarArticleFilter: .allItems,
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

    @Test
    func inFlightAllFeedsFailureDoesNotPublishIntoChangedSelection() async throws {
        let firstFeedURL = "https://example.com/stale-refresh-a.xml"
        let secondFeedURL = "https://example.com/stale-refresh-b.xml"
        let responseGate = ScriptedHTTPClientResponseGate()
        let client = ScriptedHTTPClient(
            responsesByURL: [
                firstFeedURL: .gatedResponse(
                    statusCode: 500,
                    headers: [:],
                    body: "",
                    gate: responseGate
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feeds = try harness.insertFeeds(urls: [firstFeedURL, secondFeedURL])
        _ = try harness.insertArticle(
            feed: feeds[0],
            externalID: "stale-refresh-visible-article",
            url: "https://example.com/stale-refresh-visible-article",
            title: "Visible While Refreshing"
        )
        let controller = ArticlesScreenController()
        let appState = AppState()
        harness.dependencies.appActions.showInbox(using: appState)

        await controller.load(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let refreshTask = Task { @MainActor in
            await controller.refreshCurrentSelection(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                dependencies: harness.dependencies,
                appState: appState
            )
        }
        try await waitForArticlesRefreshCondition("stale refresh request entered gate") {
            await responseGate.hasEntered()
        }

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.title) == ["Visible While Refreshing"])

        harness.dependencies.appActions.showFeed(id: feeds[1].id, using: appState)
        await controller.load(
            selection: .feed(feeds[1].id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        await responseGate.release()
        _ = await refreshTask.value

        #expect(controller.screenState.selection == .feed(feeds[1].id))
        #expect(controller.screenState.refreshFeedback == nil)
    }

    @Test
    func inFlightFeedFailureDoesNotPublishIntoChangedSidebarFilter() async throws {
        let feedURL = "https://example.com/stale-filter-refresh.xml"
        let responseGate = ScriptedHTTPClientResponseGate()
        let client = ScriptedHTTPClient(
            responsesByURL: [
                feedURL: .gatedResponse(
                    statusCode: 500,
                    headers: [:],
                    body: "",
                    gate: responseGate
                )
            ]
        )
        let harness = try TestHarness.make(httpClient: client)
        let feed = try #require(try harness.insertFeeds(urls: [feedURL]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "stale-filter-visible-article",
            url: "https://example.com/stale-filter-visible-article",
            title: "Visible Before Filter Change"
        )
        let controller = ArticlesScreenController()
        let appState = AppState()
        harness.dependencies.appActions.showFeed(id: feed.id, using: appState)

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let refreshTask = Task { @MainActor in
            await controller.refreshCurrentSelection(
                selection: .feed(feed.id),
                sidebarArticleFilter: .allItems,
                dependencies: harness.dependencies,
                appState: appState
            )
        }
        try await waitForArticlesRefreshCondition("stale filter refresh request entered gate") {
            await responseGate.hasEntered()
        }

        harness.dependencies.appActions.applySidebarArticleFilter(.starred, using: appState)
        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .starred,
            dependencies: harness.dependencies
        )
        await responseGate.release()
        _ = await refreshTask.value

        #expect(controller.screenState.articleListSession.context.selection == .feed(feed.id))
        #expect(controller.screenState.articleListSession.context.sidebarArticleFilter == .starred)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.screenState.refreshFeedback == nil)
    }
}

private func waitForArticlesRefreshCondition(
    _ expectation: String,
    condition: () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }
        await Task.yield()
    }
    throw ArticlesRefreshWaitError.timedOut(expectation)
}

private enum ArticlesRefreshWaitError: Error {
    case timedOut(String)
}
