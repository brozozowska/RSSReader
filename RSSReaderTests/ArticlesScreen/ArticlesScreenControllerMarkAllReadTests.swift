import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Mark All Read")
@MainActor
struct ArticlesScreenControllerMarkAllReadTests {
    @Test
    func articlesScreenControllerPresentsConfirmationWhenAskBeforeMarkingAllAsReadIsEnabled() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let controller = ArticlesScreenController(
            previewScreenState: .previewLoaded(
                selection: .feed(unreadItem.feedID),
                navigationTitle: "Feed",
                navigationSubtitle: "1 Unread Item",
                articles: [unreadItem]
            )
        )

        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: true,
                updatedAt: .distantPast
            )
        )

        await controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(unreadItem.feedID),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.pendingConfirmation == .markAllAsRead)
        #expect(controller.screenState.articles.first?.isRead == false)
    }

    @Test
    func articlesScreenControllerMarksAllAsReadImmediatelyWhenAskBeforeMarkingAllAsReadIsDisabled() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsRepository = try #require(harness.dependencies.appSettingsRepository)
        let articleStateRepository = try #require(harness.dependencies.articleStateRepository)
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-immediately.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "mark-immediately",
            url: "https://example.com/articles/mark-immediately",
            title: "Mark Immediately"
        )
        let controller = ArticlesScreenController()

        _ = try appSettingsRepository.update(
            AppSettingsUpdate(
                askBeforeMarkingAllAsRead: false,
                updatedAt: .distantPast
            )
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        await controller.handleMarkAllAsReadAction(
            searchText: "",
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let persistedState = try articleStateRepository.fetchStateSnapshot(
            feedID: feed.id,
            articleExternalID: article.externalID
        )

        #expect(controller.screenState.pendingConfirmation == nil)
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(persistedState?.isRead == true)
    }

    @Test
    func articlesScreenControllerMarksAccumulatedPagesAndPreservesContinuationCursor() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let first = makeArticleListItemDTO(
            articleExternalID: "mark-page-first",
            isRead: false,
            isStarred: false
        )
        let second = makeArticleListItemDTO(
            feedID: first.feedID,
            articleExternalID: "mark-page-second",
            isRead: false,
            isStarred: false
        )
        let nextCursor = makeArticleSearchCursor(seed: 2)
        var screenState = ArticlesScreenState()
        screenState.applyLoadedArticles(
            [first, second],
            selection: .feed(first.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 2),
            sessionContext: ArticleListSession.Context(
                selection: .feed(first.feedID),
                sidebarArticleFilter: .allItems
            ),
            nextPageCursor: nextCursor
        )
        let controller = ArticlesScreenController(previewScreenState: screenState)

        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .feed(first.feedID),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: true
        )

        #expect(controller.screenState.articles.allSatisfy { $0.isRead })
        #expect(controller.screenState.articleListSession.nextPageCursor == nextCursor)
        #expect(
            controller.screenState.navigationSubtitle
                == ReadingLocalization.noUnreadItemsSubtitle
        )
    }

    @Test
    func articlesScreenControllerMarksEntirePaginatedUnreadScopeAndPublishesFinalEmptySnapshot() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-unread-pages.xml"]).first
        )
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var persistedArticles: [Article] = []
        for index in 0..<3 {
            persistedArticles.append(
                try harness.insertArticle(
                    feed: feed,
                    externalID: "mark-unread-page-\(index)",
                    url: "https://example.com/articles/mark-unread-page-\(index)",
                    title: "Unread Page \(index)",
                    publishedAt: baseDate.addingTimeInterval(TimeInterval(index))
                )
            )
        }
        var requests: [ArticleSearchRequest] = []
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, articleQueryService in
                requests.append(request)
                return try await articleQueryService.fetchArticleSearchSnapshot(request)
            },
            pageSize: 1
        )

        await controller.load(
            selection: .unread,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let originalContext = controller.screenState.articleListSession.context
        _ = try #require(controller.screenState.articleListSession.nextPageCursor)

        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .unread,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.cursor == nil })
        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.screenState.articleListSession.context == originalContext)
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        for article in persistedArticles {
            let state = try harness.articleStateRepository.fetchStateSnapshot(
                feedID: article.feedID,
                articleExternalID: article.externalID
            )
            #expect(state?.isRead == true)
        }
    }

    @Test
    func articlesScreenControllerEndsUnreadSessionAfterMarkingTerminalPageAsRead() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-unread-terminal.xml"]).first
        )
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "mark-unread-terminal",
            url: "https://example.com/articles/mark-unread-terminal",
            title: "Unread Terminal"
        )
        var requestCount = 0
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, articleQueryService in
                requestCount += 1
                return try await articleQueryService.fetchArticleSearchSnapshot(request)
            },
            pageSize: 1
        )

        await controller.load(
            selection: .unread,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies
        )
        let markedArticle = try #require(controller.screenState.articles.first)
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)

        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .unread,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let markedState = try harness.articleStateRepository.fetchStateSnapshot(
            feedID: markedArticle.feedID,
            articleExternalID: markedArticle.articleExternalID
        )

        #expect(requestCount == 2)
        #expect(markedState?.isRead == true)
        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.screenState.articleListSession.nextPageCursor == nil)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
    }

    @Test
    func articlesScreenControllerMarksEveryUnreadSearchMatchAcrossFeedsWithoutTouchingNonmatches() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(urls: [
            "https://example.com/scope-search-a.xml",
            "https://example.com/scope-search-b.xml"
        ])
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        let matchingArticles = try [
            harness.insertArticle(
                feed: firstFeed,
                externalID: "scope-target-a",
                url: "https://example.com/articles/scope-target-a",
                title: "Target Alpha"
            ),
            harness.insertArticle(
                feed: secondFeed,
                externalID: "scope-target-b",
                url: "https://example.com/articles/scope-target-b",
                title: "Target Beta"
            ),
            harness.insertArticle(
                feed: secondFeed,
                externalID: "scope-target-c",
                url: "https://example.com/articles/scope-target-c",
                title: "Target Gamma"
            )
        ]
        let nonmatchingArticle = try harness.insertArticle(
            feed: firstFeed,
            externalID: "scope-other",
            url: "https://example.com/articles/scope-other",
            title: "Unrelated"
        )
        let controller = ArticlesScreenController(pageSize: 1)

        await controller.load(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            searchText: "Target",
            dependencies: harness.dependencies
        )
        #expect(controller.screenState.articles.count == 1)
        #expect(controller.screenState.articleListSession.nextPageCursor != nil)

        await controller.confirmMarkAllAsRead(
            searchText: "Target",
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.count == 1)
        #expect(controller.screenState.articles.first?.isRead == true)
        for article in matchingArticles {
            #expect(
                try harness.articleStateRepository.fetchStateSnapshot(
                    feedID: article.feedID,
                    articleExternalID: article.externalID
                )?.isRead == true
            )
        }
        #expect(
            try harness.articleStateRepository.fetchStateSnapshot(
                feedID: nonmatchingArticle.feedID,
                articleExternalID: nonmatchingArticle.externalID
            ) == nil
        )
    }

    @Test
    func articlesScreenControllerKeepsCurrentSnapshotWhileScopeMutationIsInFlight() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-atomic.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "mark-atomic",
            url: "https://example.com/articles/mark-atomic",
            title: "Atomic Snapshot"
        )
        let gate = ScopeReadMutationGate()
        let controller = ArticlesScreenController(
            scopeReadMutationOperation: { _, _, _ in
                try await gate.suspend()
            }
        )
        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        let originalSessionID = controller.currentArticleListSessionID
        let action = Task { @MainActor in
            await controller.confirmMarkAllAsRead(
                searchText: "",
                selection: .feed(feed.id),
                sidebarArticleFilter: .unread,
                dependencies: harness.dependencies,
                isPreviewMode: false
            )
        }

        await gate.waitUntilSuspended()
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.currentArticleListSessionID == originalSessionID)
        #expect(controller.screenState.placeholder == nil)

        gate.resume()
        await action.value

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
    }

    @Test
    func articlesScreenControllerRefreshesPersistedSnapshotAfterPartialScopeMutationFailure() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-partial-failure.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "mark-partial-failure",
            url: "https://example.com/articles/mark-partial-failure",
            title: "Partial Failure"
        )
        let controller = ArticlesScreenController(
            scopeReadMutationOperation: { _, articleStateService, _ in
                _ = try articleStateService.markAllVisibleAsRead(
                    feedID: feed.id,
                    articleExternalIDs: [article.externalID],
                    at: .now
                )
                throw ScopeReadMutationTestError.injectedFailure
            }
        )
        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(
            try harness.articleStateRepository.fetchStateSnapshot(
                feedID: feed.id,
                articleExternalID: article.externalID
            )?.isRead == true
        )
    }

    @Test
    func articlesScreenControllerRefreshesPersistedSnapshotAfterCancelledScopeMutation() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-cancelled.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "mark-cancelled",
            url: "https://example.com/articles/mark-cancelled",
            title: "Cancelled Mutation"
        )
        let controller = ArticlesScreenController(
            scopeReadMutationOperation: { _, articleStateService, _ in
                _ = try articleStateService.markAllVisibleAsRead(
                    feedID: feed.id,
                    articleExternalIDs: [article.externalID],
                    at: .now
                )
                throw CancellationError()
            }
        )
        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
    }

    @Test
    func articlesScreenControllerIgnoresScopeMutationCompletionFromReplacedSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(urls: [
            "https://example.com/mark-stale-a.xml",
            "https://example.com/mark-stale-b.xml"
        ])
        let firstFeed = try #require(feeds.first)
        let secondFeed = try #require(feeds.last)
        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "mark-stale-a",
            url: "https://example.com/articles/mark-stale-a",
            title: "Stale A"
        )
        let secondArticle = try harness.insertArticle(
            feed: secondFeed,
            externalID: "mark-stale-b",
            url: "https://example.com/articles/mark-stale-b",
            title: "Stale B"
        )
        let gate = ScopeReadMutationGate()
        let controller = ArticlesScreenController(
            scopeReadMutationOperation: { _, _, _ in
                try await gate.suspend()
            }
        )
        await controller.load(
            selection: .feed(firstFeed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        let action = Task { @MainActor in
            await controller.confirmMarkAllAsRead(
                searchText: "",
                selection: .feed(firstFeed.id),
                sidebarArticleFilter: .unread,
                dependencies: harness.dependencies,
                isPreviewMode: false
            )
        }
        await gate.waitUntilSuspended()

        await controller.load(
            selection: .feed(secondFeed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        let secondSessionID = controller.currentArticleListSessionID
        gate.resume()
        await action.value

        #expect(controller.currentArticleListSessionID == secondSessionID)
        #expect(controller.screenState.articleListSession.context.selection == .feed(secondFeed.id))
        #expect(controller.screenState.articles.map(\.id) == [secondArticle.id])
    }

    @Test
    func articlesScreenControllerKeepsUnreadRowWhenMarkAllLosesLWWConflict() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/mark-unread-lww.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "mark-unread-lww",
            url: "https://example.com/articles/mark-unread-lww",
            title: "Mark Unread LWW"
        )
        _ = try harness.articleStateService.markAsUnread(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .distantFuture
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            refreshesScopeMetric: true
        )
        await controller.confirmMarkAllAsRead(
            searchText: "",
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articles.first?.isRead == false)
        #expect(controller.screenState.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: 1))
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 1))
        #expect(
            try harness.articleStateRepository.fetchStateSnapshot(
                feedID: feed.id,
                articleExternalID: article.externalID
            )?.isRead == false
        )
    }
}

@MainActor
private final class ScopeReadMutationGate {
    private var continuation: CheckedContinuation<ArticleScopeReadMutationResult, Error>?
    private var suspendedWaiter: CheckedContinuation<Void, Never>?

    var isSuspended: Bool {
        continuation != nil
    }

    func suspend() async throws -> ArticleScopeReadMutationResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            suspendedWaiter?.resume()
            suspendedWaiter = nil
        }
    }

    func waitUntilSuspended() async {
        guard isSuspended == false else { return }

        await withCheckedContinuation { continuation in
            suspendedWaiter = continuation
        }
    }

    func resume() {
        continuation?.resume(
            returning: ArticleScopeReadMutationResult(
                processedIdentityCount: 0,
                persistedReadCount: 0,
                rejectedIdentityCount: 0,
                processedBatchCount: 0
            )
        )
        continuation = nil
    }
}

private enum ScopeReadMutationTestError: Error {
    case injectedFailure
}
