import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / State / Toolbar")
@MainActor
struct ArticlesScreenStateToolbarTests {
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
}
