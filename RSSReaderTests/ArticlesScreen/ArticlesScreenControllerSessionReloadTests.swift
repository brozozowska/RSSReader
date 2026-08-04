import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Articles Screen / Controller / Session Reload")
@MainActor
struct ArticlesScreenControllerSessionReloadTests {
    @Test
    func articlesScreenControllerRetainsUnreadArticleAfterManualReadToggleInCurrentSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/manual-read-retention.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "manual-read-retention-article",
            url: "https://example.com/articles/manual-read-retention",
            title: "Manual Read Retention"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        let loadedArticle = try #require(controller.screenState.articles.first)
        controller.toggleArticleReadStatus(
            loadedArticle,
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        let persistedState = try #require(
            try harness.articleStateRepository.fetchState(
                feedID: feed.id,
                articleExternalID: article.externalID
            )
        )

        #expect(persistedState.isRead)
        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(
            controller.screenState.articleListSession.entries.map(\.membershipStatus)
                == [.retainedAfterFilterMutation]
        )
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(controller.screenState.toolbarActions.isMarkAllAsReadEnabled == false)
    }

    @Test
    func articlesScreenControllerRetainsSessionReadArticleOnlyForRetainingReloads() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-unread.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "session-unread-article",
            url: "https://example.com/articles/session-unread",
            title: "Session Unread"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: true
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(
            controller.screenState.articleListSession.entries.map(\.membershipStatus)
                == [.retainedAfterFilterMutation]
        )
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)

        let newEntryController = ArticlesScreenController()
        await newEntryController.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        #expect(newEntryController.screenState.phase == .empty)
        #expect(newEntryController.screenState.articles.isEmpty)
    }

    @Test
    func articlesScreenControllerMarksSessionReadRetentionAfterRefresh() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-refresh.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "session-refresh-article",
            url: "https://example.com/articles/session-refresh",
            title: "Session Refresh"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: true,
            retainedSessionMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRefresh])
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
    }

    @Test
    func articlesScreenControllerAppliesFreshQuerySnapshotAfterRefreshWithoutRetainingReadEntries() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-refresh-reset.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "session-refresh-reset-article",
            url: "https://example.com/articles/session-refresh-reset",
            title: "Session Refresh Reset"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: false,
            retainedSessionMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.screenState.articleListSession.entries.isEmpty)
        #expect(controller.screenState.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
    }

    @Test
    func articlesScreenControllerKeepsScrollPositionAndRemovesRetainedReadArticleAfterReturnRefresh() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/return-refresh.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "return-refresh-article",
            url: "https://example.com/articles/return-refresh",
            title: "Return Refresh"
        )
        let appState = AppState()
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        appState.updateArticleListScrollPosition(
            article.id,
            sidebarSelection: .feed(feed.id),
            sidebarArticleFilter: .unread
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articles.first?.isRead == true)
        #expect(
            controller.screenState.articleListSession.entries.map(\.membershipStatus)
                == [.retainedAfterFilterMutation]
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: false,
            retainedSessionMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(
            appState.articleListScrollPositionID(
                sidebarSelection: .feed(feed.id),
                sidebarArticleFilter: .unread
            ) == article.id
        )
    }

    @Test
    func articlesScreenControllerResetsSessionWhenSidebarArticleFilterChanges() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-filter-reset.xml"]).first)
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "session-filter-reset-article",
            url: "https://example.com/articles/session-filter-reset",
            title: "Session Filter Reset"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(article.id)

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: true
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articleListSession.context == ArticleListSession.Context(
            selection: .feed(feed.id),
            sidebarArticleFilter: .allItems
        ))
        #expect(controller.screenState.articles.map(\.id) == [article.id])
        #expect(controller.screenState.articleListSession.entries.map(\.membershipStatus) == [.matchesCurrentQuery])
        #expect(controller.screenState.articles.first?.isRead == true)
    }

    @Test
    func articlesScreenControllerMergesFreshQuerySnapshotWithCurrentRetainedEntries() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let articleStateService = try #require(harness.dependencies.articleStateService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/session-merge.xml"]).first)
        let retainedArticle = try harness.insertArticle(
            feed: feed,
            externalID: "session-merge-retained",
            url: "https://example.com/articles/session-merge-retained",
            title: "Retained Article"
        )
        let currentArticle = try harness.insertArticle(
            feed: feed,
            externalID: "session-merge-current",
            url: "https://example.com/articles/session-merge-current",
            title: "Current Article"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )

        _ = try articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: retainedArticle.externalID,
            at: .now
        )
        controller.markArticleAsReadInCurrentSession(retainedArticle.id)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "session-merge-new",
            url: "https://example.com/articles/session-merge-new",
            title: "New Article"
        )

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            retainsSessionFilterMutations: true,
            retainedSessionMembershipStatus: .retainedAfterRefresh
        )

        #expect(controller.screenState.phase == .loaded)
        #expect(controller.screenState.articles.contains { $0.id == retainedArticle.id })
        #expect(controller.screenState.articles.contains { $0.id == currentArticle.id })
        #expect(controller.screenState.articles.contains { $0.title == "New Article" })
        #expect(
            controller.screenState.articleListSession.entries.first {
                $0.id == retainedArticle.id
            }?.membershipStatus == .retainedAfterRefresh
        )
        #expect(
            controller.screenState.articleListSession.entries.filter {
                $0.membershipStatus == .matchesCurrentQuery
            }.count == 2
        )
    }

    @Test
    func articlesScreenControllerEndsUnreadSessionOnSidebarBackAndRequeriesSameFeed() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/unread-back-reentry.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "unread-back-reentry",
            url: "https://example.com/articles/unread-back-reentry",
            title: "Unread Back Re-entry"
        )
        let controller = ArticlesScreenController()

        await controller.load(
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        let originalSessionID = controller.currentArticleListSessionID
        let persistedState = try harness.articleStateService.markAsRead(
            feedID: feed.id,
            articleExternalID: article.externalID,
            at: .now
        )
        let readEvent = ArticleReadOnOpenEvent(
            articleID: article.id,
            articleListSessionID: originalSessionID,
            sidebarSelection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            isRead: persistedState.isRead
        )

        #expect(controller.applyArticleReadOnOpenEvent(readEvent))
        #expect(controller.screenState.articleListSession.entries.first?.isRetained == true)

        controller.endPresentation()

        #expect(controller.screenState.phase == .noSelection)
        #expect(controller.screenState.articleListSession.context == .noSelection)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.currentArticleListSessionID != originalSessionID)
        #expect(controller.applyArticleReadOnOpenEvent(readEvent) == false)

        let reentryLoad = try #require(
            controller.prepareForPresentation(
                selection: .feed(feed.id),
                sidebarArticleFilter: .unread,
                dependencies: harness.dependencies
            )
        )
        await reentryLoad.value

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articleListSession.context.selection == .feed(feed.id))
        #expect(controller.screenState.articles.isEmpty)
    }

    @Test
    func articlesScreenControllerPublishesFreshUnreadSessionAcrossFastFeedReentry() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feeds = try harness.insertFeeds(
            urls: [
                "https://example.com/unread-reentry-a.xml",
                "https://example.com/unread-reentry-b.xml"
            ]
        )
        let feedA = try #require(feeds.first)
        let feedB = try #require(feeds.last)
        let articleA = try harness.insertArticle(
            feed: feedA,
            externalID: "unread-reentry-a",
            url: "https://example.com/articles/unread-reentry-a",
            title: "Unread Re-entry A"
        )
        _ = try harness.insertArticle(
            feed: feedB,
            externalID: "unread-reentry-b",
            url: "https://example.com/articles/unread-reentry-b",
            title: "Unread Re-entry B"
        )
        let queryGate = UnreadSessionReentryQueryGate(feedAID: feedA.id, feedBID: feedB.id)
        let controller = ArticlesScreenController(
            searchQueryOperation: { request, articleQueryService in
                await queryGate.suspendIfNeeded(for: request.selection)
                return try await articleQueryService.fetchArticleSearchSnapshot(request)
            }
        )

        await controller.load(
            selection: .feed(feedA.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies
        )
        let originalFeedASessionID = controller.currentArticleListSessionID
        let persistedState = try harness.articleStateService.markAsRead(
            feedID: feedA.id,
            articleExternalID: articleA.externalID,
            at: .now
        )
        let oldSessionReadEvent = ArticleReadOnOpenEvent(
            articleID: articleA.id,
            articleListSessionID: originalFeedASessionID,
            sidebarSelection: .feed(feedA.id),
            sidebarArticleFilter: .unread,
            isRead: persistedState.isRead
        )

        #expect(controller.applyArticleReadOnOpenEvent(oldSessionReadEvent))
        #expect(controller.screenState.articleListSession.entries.first?.isRetained == true)

        let feedBLoad = Task { @MainActor in
            await controller.load(
                selection: .feed(feedB.id),
                sidebarArticleFilter: .unread,
                dependencies: harness.dependencies,
                retainsSessionFilterMutations: true
            )
        }
        await waitUntilSessionReload("feed B query suspended") {
            queryGate.hasSuspendedFeedBRequest
        }

        let feedAReentryLoad = Task { @MainActor in
            await controller.load(
                selection: .feed(feedA.id),
                sidebarArticleFilter: .unread,
                dependencies: harness.dependencies,
                retainsSessionFilterMutations: true
            )
        }
        await waitUntilSessionReload("feed A re-entry query suspended") {
            queryGate.hasSuspendedFeedAReentryRequest
        }

        #expect(controller.screenState.articleListSession.context.selection == .feed(feedA.id))
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.currentArticleListSessionID != originalFeedASessionID)

        queryGate.releaseFeedAReentryRequest()
        await feedAReentryLoad.value

        #expect(controller.screenState.phase == .empty)
        #expect(controller.screenState.articles.isEmpty)
        #expect(controller.applyArticleReadOnOpenEvent(oldSessionReadEvent) == false)

        queryGate.releaseFeedBRequest()
        await feedBLoad.value

        #expect(controller.screenState.articleListSession.context.selection == .feed(feedA.id))
        #expect(controller.screenState.articles.isEmpty)
    }

    @Test
    func articlesScreenControllerUsesPersistedReadStateWhenManualToggleLosesLWWConflict() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/unread-toggle-lww.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "unread-toggle-lww",
            url: "https://example.com/articles/unread-toggle-lww",
            title: "Unread Toggle LWW"
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
            dependencies: harness.dependencies
        )
        let loadedArticle = try #require(controller.screenState.articles.first)
        controller.toggleArticleReadStatus(
            loadedArticle,
            selection: .feed(feed.id),
            sidebarArticleFilter: .unread,
            dependencies: harness.dependencies,
            isPreviewMode: false
        )

        #expect(controller.screenState.articles.first?.isRead == false)
        #expect(
            controller.screenState.articleListSession.entries.first?.membershipStatus
                == .matchesCurrentQuery
        )
        #expect(
            try harness.articleStateRepository.fetchStateSnapshot(
                feedID: feed.id,
                articleExternalID: article.externalID
            )?.isRead == false
        )
    }
}

@MainActor
private final class UnreadSessionReentryQueryGate {
    let feedAID: UUID
    let feedBID: UUID
    private var feedARequestCount = 0
    private var feedAReentryContinuation: CheckedContinuation<Void, Never>?
    private var feedBContinuation: CheckedContinuation<Void, Never>?

    init(feedAID: UUID, feedBID: UUID) {
        self.feedAID = feedAID
        self.feedBID = feedBID
    }

    var hasSuspendedFeedAReentryRequest: Bool {
        feedAReentryContinuation != nil
    }

    var hasSuspendedFeedBRequest: Bool {
        feedBContinuation != nil
    }

    func suspendIfNeeded(for selection: SidebarSelection?) async {
        guard case .feed(let feedID) = selection else { return }

        if feedID == feedAID {
            feedARequestCount += 1
            guard feedARequestCount > 1 else { return }
            await withCheckedContinuation { continuation in
                feedAReentryContinuation = continuation
            }
        } else if feedID == feedBID {
            await withCheckedContinuation { continuation in
                feedBContinuation = continuation
            }
        }
    }

    func releaseFeedAReentryRequest() {
        feedAReentryContinuation?.resume()
        feedAReentryContinuation = nil
    }

    func releaseFeedBRequest() {
        feedBContinuation?.resume()
        feedBContinuation = nil
    }
}

@MainActor
private func waitUntilSessionReload(
    _ description: String,
    timeout: Duration = .seconds(5),
    condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if condition() { return }
        await Task.yield()
    }

    Issue.record("Timed out waiting for \(description)")
}
