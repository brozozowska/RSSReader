import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / State / Toolbar")
@MainActor
struct ArticlesScreenStateToolbarTests {
    @Test
    func articlesScreenStateBuildsDerivedToolbarActionsFromLoadedSearchSnapshot() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(
            title: "SwiftUI Weekly",
            isRead: false,
            isStarred: false
        )

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )

        let loadedViewState = state.derivedViewState(searchText: "swift")

        #expect(loadedViewState.visibleArticles.map(\.id) == [unreadItem.id])
        #expect(loadedViewState.toolbarActions.isMarkAllAsReadEnabled)
        #expect(loadedViewState.searchPlaceholder == nil)
    }

    @Test
    func articlesScreenStateBuildsSearchPlaceholderForEmptyLoadedSearchSnapshot() {
        var state = ArticlesScreenState()

        state.applyLoadedArticles(
            [],
            selection: .inbox,
            navigationTitle: ReadingLocalization.allItemsTitle,
            navigationSubtitle: ReadingLocalization.noUnreadItemsSubtitle,
            emptyContentKind: .searchResults
        )

        let emptySearchViewState = state.derivedViewState(searchText: "kotlin")

        #expect(emptySearchViewState.visibleArticles.isEmpty)
        #expect(emptySearchViewState.toolbarActions.isMarkAllAsReadEnabled == false)
        #expect(emptySearchViewState.searchPlaceholder?.title == ReadingLocalization.noSearchResultsTitle)
        #expect(emptySearchViewState.searchPlaceholder?.description == ReadingLocalization.noSearchResultsDescription(query: "kotlin"))
    }

    @Test
    func articlesScreenStateKeepsSelectionEmptyPlaceholderWhenSearchScopeHasNoArticles() {
        var state = ArticlesScreenState()

        state.applyLoadedArticles(
            [],
            selection: .inbox,
            navigationTitle: ReadingLocalization.allItemsTitle,
            navigationSubtitle: ReadingLocalization.noUnreadItemsSubtitle,
            emptyContentKind: .selection
        )

        let emptySelectionViewState = state.derivedViewState(searchText: "kotlin")

        #expect(emptySelectionViewState.searchPlaceholder == nil)
        #expect(state.placeholder?.title == ReadingLocalization.noArticlesTitle)
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

        #expect(derivedViewState.primaryLoadingState?.title == ReadingLocalization.loadingArticlesTitle)
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
