import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / State")
@MainActor
struct ArticlesScreenStateTests {
    @Test
    func articlesScreenStateStartsWithoutSelectionPlaceholder() {
        let state = ArticlesScreenState()

        #expect(state.phase == .noSelection)
        #expect(state.navigationTitle == "Articles")
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.placeholder?.title == "No Source Selected")
        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenStateBeginsPrimaryLoadingWhenSelectionChanges() {
        var state = ArticlesScreenState()

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "3 Unread Items",
            resetsContent: true
        )

        #expect(state.phase == .loading)
        #expect(state.navigationTitle == "Unread")
        #expect(state.navigationSubtitle == "3 Unread Items")
        #expect(state.showsPrimaryLoadingIndicator)
        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenStateBuildsEmptyPlaceholderForCurrentSelection() {
        var state = ArticlesScreenState()

        state.applyLoadedArticles(
            [],
            selection: .starred,
            navigationTitle: "Starred",
            navigationSubtitle: "0 Starred Items"
        )

        #expect(state.phase == .empty)
        #expect(state.navigationTitle == "Starred")
        #expect(state.navigationSubtitle == "0 Starred Items")
        #expect(state.placeholder?.title == "No Articles")
        #expect(state.placeholder?.description == "You have not starred any articles yet.")
    }

    @Test
    func articlesScreenStateBuildsPrimaryFailureForInitialLoad() {
        var state = ArticlesScreenState()

        state.applyLoadingFailure(
            "Article query service is unavailable.",
            selection: .inbox,
            navigationTitle: "All Items",
            navigationSubtitle: "0 Unread Items",
            retainsContent: false
        )

        #expect(state.phase == .failed("Article query service is unavailable."))
        #expect(state.primaryFailureMessage == "Article query service is unavailable.")
        #expect(state.refreshFeedback == nil)
    }

    @Test
    func articlesScreenStateKeepsVisibleArticlesWhenRefreshFails() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.beginLoading(
            for: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            resetsContent: false
        )
        state.applyLoadingFailure(
            "Refresh failed",
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            retainsContent: true
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationTitle == "Feed")
        #expect(state.navigationSubtitle == "1 Unread Item")
        #expect(state.articles.map(\.id) == [unreadItem.id])
        #expect(state.refreshState == .idle)
        #expect(state.refreshFeedback == ArticlesScreenRefreshFeedback(message: "Refresh failed"))
        #expect(state.toolbarActions.isMarkAllAsReadEnabled)
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
    func articlesScreenStateBuildsDerivedToolbarActionsAndSearchPlaceholderForFilteredResults() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(
            title: "SwiftUI Weekly",
            isRead: false,
            isStarred: false
        )
        let readItem = makeArticleListItemDTO(
            title: "Architecture Digest",
            isRead: true,
            isStarred: false
        )

        state.applyLoadedArticles(
            [unreadItem, readItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )

        let loadedViewState = state.derivedViewState(searchText: "swift")
        let emptySearchViewState = state.derivedViewState(searchText: "kotlin")

        #expect(loadedViewState.visibleArticles.map(\.id) == [unreadItem.id])
        #expect(loadedViewState.toolbarActions.isMarkAllAsReadEnabled)
        #expect(emptySearchViewState.visibleArticles.isEmpty)
        #expect(emptySearchViewState.toolbarActions.isMarkAllAsReadEnabled == false)
        #expect(emptySearchViewState.searchPlaceholder?.title == "No Search Results")
        #expect(emptySearchViewState.searchPlaceholder?.description == "No visible articles match \"kotlin\".")
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
        #expect(derivedViewState.refreshBanner?.title == "Refresh Failed")
        #expect(derivedViewState.refreshBanner?.message == "Refresh failed")
        #expect(derivedViewState.refreshBanner?.showsRetryAction == true)
    }

    @Test
    func articlesScreenStateBuildsPrimaryLoadingCopyFromSelection() {
        var state = ArticlesScreenState()

        state.beginLoading(
            for: .folder("Apple"),
            navigationTitle: "Apple",
            navigationSubtitle: "0 Unread Items",
            resetsContent: true
        )

        let derivedViewState = state.derivedViewState(searchText: "")

        #expect(derivedViewState.primaryLoadingState?.title == "Loading Articles")
    }

    @Test
    func articlesScreenStatePresentsConfirmationOnlyWhenUnreadArticlesAreVisible() {
        var state = ArticlesScreenState()
        let readItem = makeArticleListItemDTO(isRead: true, isStarred: false)
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [readItem],
            selection: .feed(readItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "0 Unread Items"
        )
        state.presentMarkAllAsReadConfirmation()
        #expect(state.pendingConfirmation == nil)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentMarkAllAsReadConfirmation()
        #expect(state.pendingConfirmation == .markAllAsRead)
    }

    @Test
    func articlesScreenToolbarActionsAreHiddenDuringPrimaryLoading() {
        var state = ArticlesScreenState()

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            resetsContent: true
        )

        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenToolbarActionsAreHiddenAfterPrimaryFailure() {
        var state = ArticlesScreenState()

        state.applyLoadingFailure(
            "Unable to load the current selection.",
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            retainsContent: false
        )

        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenStateAppliesMarkAllAsReadAndRefreshesToolbarState() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: true)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentMarkAllAsReadConfirmation()
        state.applyMarkAllAsRead(
            [
                makeArticleListItemDTO(
                    id: unreadItem.id,
                    feedID: unreadItem.feedID,
                    articleExternalID: unreadItem.articleExternalID,
                    isRead: true,
                    isStarred: true
                )
            ],
            navigationSubtitle: "0 Unread Items"
        )

        #expect(state.pendingConfirmation == nil)
        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.articles.count == 1)
        #expect(state.articles.first?.isRead == true)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
    }

    @Test
    func articlesScreenStateAppliesMarkAllAsReadToUnreadFilterAndTransitionsToEmpty() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item"
        )
        state.presentMarkAllAsReadConfirmation()
        state.applyMarkAllAsRead([], navigationSubtitle: "0 Unread Items")

        #expect(state.pendingConfirmation == nil)
        #expect(state.phase == .empty)
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.articles.isEmpty)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
    }

    @Test
    func articlesScreenStateAppliesArticleRowUpdateForReadAction() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let updatedItem = makeArticleListItemDTO(
            id: unreadItem.id,
            feedID: unreadItem.feedID,
            articleExternalID: unreadItem.articleExternalID,
            isRead: true,
            isStarred: false
        )

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.applyArticleRowMutation(
            articleID: unreadItem.id,
            mutation: .update(updatedItem),
            navigationSubtitle: "0 Unread Items"
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.articles.count == 1)
        #expect(state.articles.first?.isRead == true)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
    }

    @Test
    func articlesScreenStateRemovesArticleRowForReadActionInUnreadSelection() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item"
        )
        state.applyArticleRowMutation(
            articleID: unreadItem.id,
            mutation: .remove,
            navigationSubtitle: "0 Unread Items"
        )

        #expect(state.phase == .empty)
        #expect(state.navigationSubtitle == "0 Unread Items")
        #expect(state.articles.isEmpty)
    }

    @Test
    func articlesScreenStateAppliesArticleRowUpdateForStarActionOutsideStarredSelection() {
        var state = ArticlesScreenState()
        let item = makeArticleListItemDTO(isRead: false, isStarred: false)
        let updatedItem = makeArticleListItemDTO(
            id: item.id,
            feedID: item.feedID,
            articleExternalID: item.articleExternalID,
            isRead: false,
            isStarred: true
        )

        state.applyLoadedArticles(
            [item],
            selection: .feed(item.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        state.applyArticleRowMutation(
            articleID: item.id,
            mutation: .update(updatedItem),
            navigationSubtitle: "1 Unread Item"
        )

        #expect(state.phase == .loaded)
        #expect(state.articles.first?.isStarred == true)
        #expect(state.navigationSubtitle == "1 Unread Item")
    }

    @Test
    func articlesScreenStateRemovesArticleRowWhenUnstarredInsideStarredSelection() {
        var state = ArticlesScreenState()
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)

        state.applyLoadedArticles(
            [starredItem],
            selection: .starred,
            navigationTitle: "Starred",
            navigationSubtitle: "1 Starred Item"
        )
        state.applyArticleRowMutation(
            articleID: starredItem.id,
            mutation: .remove,
            navigationSubtitle: "0 Starred Items"
        )

        #expect(state.phase == .empty)
        #expect(state.navigationSubtitle == "0 Starred Items")
        #expect(state.articles.isEmpty)
    }
}
