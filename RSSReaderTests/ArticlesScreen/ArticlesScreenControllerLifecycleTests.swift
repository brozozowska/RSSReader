import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Lifecycle")
@MainActor
struct ArticlesScreenControllerLifecycleTests {
    @Test
    func compactBackReentryUsesRetainedSearchInFreshSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/search-reentry.xml"]).first)
        let matching = try harness.insertArticle(
            feed: feed, externalID: "ssh", url: "https://example.com/ssh", title: "SSH"
        )
        let other = try harness.insertArticle(
            feed: feed, externalID: "other", url: "https://example.com/other", title: "Other"
        )
        let controller = ArticlesScreenController(searchDebounceOperation: {})
        controller.selectSearchScope(.unread)
        controller.searchText = "SSH"
        await controller.load(
            selection: .unread, sidebarArticleFilter: .allItems,
            searchText: controller.searchText, dependencies: harness.dependencies
        )
        let originalSessionID = controller.currentArticleListSessionID
        #expect(controller.visibleArticleIDs() == [matching.id])

        controller.endPresentation()
        #expect(controller.searchText(for: .unread) == "SSH")
        #expect(controller.screenState.articles.isEmpty)

        let reentry = try #require(controller.prepareForPresentation(
            selection: .unread, sidebarArticleFilter: .allItems, dependencies: harness.dependencies
        ))
        // The very first presentation context already has the query, before results arrive.
        #expect(controller.screenState.articleListSession.context.normalizedSearchText == "SSH")
        await reentry.value
        #expect(controller.currentArticleListSessionID != originalSessionID)
        #expect(controller.visibleArticleIDs() == [matching.id])
        #expect(controller.searchText == "SSH")

        let otherScope = try #require(controller.prepareForPresentation(
            selection: .feed(feed.id), sidebarArticleFilter: .allItems, dependencies: harness.dependencies
        ))
        #expect(controller.searchText.isEmpty)
        #expect(controller.screenState.articleListSession.context.normalizedSearchText.isEmpty)
        await otherScope.value
        #expect(Set(controller.visibleArticleIDs()) == Set([matching.id, other.id]))
        #expect(controller.screenState.articles.count == 2)
    }

    @Test(arguments: [SidebarSelection.unread, .starred, .folder("News"), .feed(UUID(uuidString: "00000000-0000-0000-0000-000000000849")!)])
    func searchIsRetainedOnlyUntilAnotherSidebarScopeIsSelected(_ scope: SidebarSelection) {
        let controller = ArticlesScreenController()
        controller.selectSearchScope(scope)
        controller.searchText = " SSH "
        controller.endPresentation()
        controller.selectSearchScope(scope)
        #expect(controller.searchText(for: scope) == " SSH ")
        #expect(controller.searchText(for: .inbox).isEmpty)
        controller.selectSearchScope(.inbox)
        #expect(controller.searchText.isEmpty)
        controller.selectSearchScope(scope)
        #expect(controller.searchText.isEmpty)
    }

    @Test
    func articlesScreenControllerReusesControllerAndReplacesSnapshotWhenSidebarSelectionChanges() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/controller-first.xml",
                "https://example.com/controller-second.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        let firstArticle = try harness.insertArticle(
            feed: firstFeed,
            externalID: "controller-first-article",
            url: "https://example.com/articles/controller-first",
            title: "Controller First"
        )
        let secondArticle = try harness.insertArticle(
            feed: secondFeed,
            externalID: "controller-second-article",
            url: "https://example.com/articles/controller-second",
            title: "Controller Second"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(firstFeed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        #expect(controller.screenState.articles.map(\.id) == [firstArticle.id])

        await controller.load(
            selection: .feed(secondFeed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.selection == .feed(secondFeed.id))
        #expect(controller.screenState.articleListSession.context.selection == .feed(secondFeed.id))
        #expect(controller.screenState.articles.map(\.id) == [secondArticle.id])
    }

    @Test
    func articlesScreenControllerReplacesDelayedScopeAndNavigationChromeAsOneSnapshot() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/chrome-first.xml",
                "https://example.com/chrome-second.xml"
            ]
        )
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        let firstArticle = makeArticleListItemDTO(
            feedID: firstFeed.id,
            articleExternalID: "chrome-first",
            title: "First Chrome",
            isRead: false
        )
        let secondArticle = makeArticleListItemDTO(
            feedID: secondFeed.id,
            articleExternalID: "chrome-second",
            title: "Second Chrome",
            isRead: false
        )
        let queryGate = ArticlesScreenSelectionQueryGate(
            suspendedSelection: .feed(secondFeed.id),
            immediateSnapshot: ArticleSearchResultSnapshot(
                articles: [firstArticle],
                hasScopeContent: true
            ),
            suspendedSnapshot: ArticleSearchResultSnapshot(
                articles: [secondArticle],
                hasScopeContent: true,
                nextCursor: makeArticleSearchCursor(seed: 1),
                scopeMetric: ArticleScopeMetric(kind: .unread, count: 12)
            )
        )
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, _ in
                try await queryGate.execute(request)
            }
        )

        await controller.load(
            selection: .feed(firstFeed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        let firstChrome = controller.screenState.derivedViewState().navigationChrome

        let presentationLoad = try #require(controller.prepareForPresentation(
            selection: .feed(secondFeed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        ))
        let preparedChrome = controller.screenState.derivedViewState().navigationChrome
        #expect(controller.screenState.phase == .loading)
        #expect(controller.screenState.articles.isEmpty)
        #expect(preparedChrome != firstChrome)
        #expect(preparedChrome.sessionContext.selection == .feed(secondFeed.id))
        #expect(preparedChrome.title == secondFeed.displayTitle)
        #expect(preparedChrome.subtitle == ReadingLocalization.loadingArticlesTitle)

        defer { presentationLoad.cancel(); queryGate.releaseSuspendedRequest() }
        try await waitUntil("second feed query suspended") {
            queryGate.hasSuspendedRequest
        }
        var coalescedCallerEntered = false
        let coalescedLoad = Task { @MainActor in
            coalescedCallerEntered = true
            await controller.load(
                selection: .feed(secondFeed.id),
                sidebarArticleFilter: .unread,
                dependencies: harness.dependencies,
                policy: .retainSession
            )
        }
        try await waitUntil("coalesced primary load caller entered") { coalescedCallerEntered }

        #expect(controller.screenState.phase == .loading)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.screenState.derivedViewState().navigationChrome == preparedChrome)
        #expect(queryGate.requestCount == 2)

        queryGate.releaseSuspendedRequest()
        await presentationLoad.value
        await coalescedLoad.value

        let secondChrome = controller.screenState.derivedViewState().navigationChrome
        #expect(secondChrome.sessionContext.selection == .feed(secondFeed.id))
        #expect(secondChrome.title == secondFeed.displayTitle)
        #expect(secondChrome.subtitle == ReadingLocalization.unreadItemsSubtitle(count: 12))
        #expect(controller.screenState.articles == [secondArticle])
    }


}
