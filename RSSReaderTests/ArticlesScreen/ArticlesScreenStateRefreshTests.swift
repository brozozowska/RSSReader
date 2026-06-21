import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / State / Refresh")
@MainActor
struct ArticlesScreenStateRefreshTests {
    @Test
    func articlesScreenStateKeepsVisibleArticlesWhenRefreshFails() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )
        state.beginLoading(
            for: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1),
            resetsContent: false
        )
        state.applyLoadingFailure(
            "Refresh failed",
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1),
            retainsContent: true
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationTitle == "Feed")
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 1))
        #expect(state.articles.map(\.id) == [unreadItem.id])
        #expect(state.refreshState == .idle)
        #expect(state.refreshFeedback == ArticlesScreenRefreshFeedback(message: "Refresh failed"))
        #expect(state.toolbarActions.isMarkAllAsReadEnabled)
    }

    @Test
    func articlesScreenStatePreservesCurrentSessionEntriesWhenRefreshBegins() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedEntries(
            [
                ArticleListEntry(
                    article: unreadItem,
                    membershipStatus: .retainedAfterRead
                )
            ],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: ReadingLocalization.noUnreadItemsSubtitle,
            sessionContext: ArticleListSession.Context(
                selection: .unread,
                sidebarArticleFilter: .allItems
            )
        )

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: ReadingLocalization.noUnreadItemsSubtitle,
            resetsContent: false,
            sessionContext: ArticleListSession.Context(
                selection: .unread,
                sidebarArticleFilter: .allItems
            )
        )

        #expect(state.refreshState == .refreshing)
        #expect(state.articleListSession.entries.map(\.id) == [unreadItem.id])
        #expect(state.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRead])
    }

    @Test
    func articlesScreenStateDoesNotShowCustomRefreshBannerDuringNativeRefresh() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item"
        )
        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item",
            resetsContent: false
        )

        let derivedViewState = state.derivedViewState(searchText: "")

        #expect(state.refreshState == .refreshing)
        #expect(derivedViewState.primaryLoadingState == nil)
        #expect(derivedViewState.refreshBanner == nil)
        #expect(derivedViewState.customRefreshState == .idle)
    }

    @Test
    func articlesScreenStateTracksCustomRefreshGestureSeparatelyFromDataRefresh() {
        var state = ArticlesScreenState()

        state.updateCustomRefreshPullProgress(0.45)

        #expect(state.customRefreshState.phase == .pulling)
        #expect(state.customRefreshState.pullProgress == 0.45)
        #expect(state.refreshState == .idle)
        #expect(state.articleListSession.context == .noSelection)

        state.updateCustomRefreshPullProgress(1)

        #expect(state.customRefreshState.phase == .ready)
        #expect(state.refreshState == .idle)

        state.beginCustomRefresh()

        #expect(state.customRefreshState == .refreshing)
        #expect(state.refreshState == .idle)

        state.updateCustomRefreshPullProgress(0.2)

        #expect(state.customRefreshState == .refreshing)

        state.endCustomRefresh()

        #expect(state.customRefreshState == .idle)
        #expect(state.refreshState == .idle)
    }

    @Test
    func articlesScreenDerivedViewStateExposesCustomRefreshState() {
        var state = ArticlesScreenState()

        state.updateCustomRefreshPullProgress(0.7)

        let viewState = state.derivedViewState(searchText: "")

        #expect(viewState.customRefreshState.phase == .pulling)
        #expect(viewState.customRefreshState.pullProgress == 0.7)
        #expect(viewState.customRefreshState.indicatorState == .pulling(progress: 0.7))
    }

    @Test
    func articlesScreenStateKeepsCustomRefreshIndicatorVisibleUntilPostRefreshReloadFinishes() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item"
        )
        state.beginCustomRefresh()

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item",
            resetsContent: false
        )

        #expect(state.customRefreshState == .refreshing)
        #expect(state.refreshState == .refreshing)
        #expect(state.articles.map(\.id) == [unreadItem.id])

        state.applyLoadedArticles(
            [],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: ReadingLocalization.noUnreadItemsSubtitle,
            sessionContext: ArticleListSession.Context(
                selection: .unread,
                sidebarArticleFilter: .allItems
            )
        )

        #expect(state.customRefreshState == .idle)
        #expect(state.phase == .empty)
        #expect(state.articles.isEmpty)
    }

    @Test
    func articlesScreenStateClearsRefreshFeedbackWhenPrimaryReloadStarts() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentRefreshFailure("Refresh failed")

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item",
            resetsContent: true
        )

        #expect(state.phase == .loading)
        #expect(state.refreshFeedback == nil)
    }

    @Test
    func articlesScreenStateBuildsRefreshBannerForVisibleRefreshFailure() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentRefreshFailure("Refresh failed")

        let derivedViewState = state.derivedViewState(searchText: "")

        #expect(derivedViewState.refreshBanner?.style == .failed)
        #expect(derivedViewState.refreshBanner?.title == ReadingLocalization.refreshFailedTitle)
        #expect(derivedViewState.refreshBanner?.message == "Refresh failed")
        #expect(derivedViewState.refreshBanner?.showsRetryAction == true)
    }

    @Test
    func articlesScreenStateCanPreserveRefreshFeedbackAfterPostRefreshReload() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentRefreshFailure("Refresh failed")

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            preservesRefreshFeedback: true
        )

        #expect(state.phase == .loaded)
        #expect(state.refreshFeedback == ArticlesScreenRefreshFeedback(message: "Refresh failed"))
    }
}
