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

        let loadedViewState = state.derivedViewState()

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
            sessionContext: ArticleListSession.Context(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                normalizedSearchText: "kotlin"
            ),
            emptyContentKind: .searchResults
        )

        let emptySearchViewState = state.derivedViewState()

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
            sessionContext: ArticleListSession.Context(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                normalizedSearchText: "kotlin"
            ),
            emptyContentKind: .selection
        )

        let emptySelectionViewState = state.derivedViewState()

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

        let derivedViewState = state.derivedViewState()

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
    func articlesScreenMutationActionsAreHiddenDuringPrimaryLoading() {
        var state = ArticlesScreenState()

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            resetsContent: true
        )

        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenQueryFailurePreservesSearchContextAndHidesMutationActions() {
        var state = ArticlesScreenState()
        let sessionContext = ArticleListSession.Context(
            selection: .unread,
            sidebarArticleFilter: .allItems,
            normalizedSearchText: "swift"
        )

        state.beginLoading(
            for: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            resetsContent: true,
            startsNewSession: true,
            sessionContext: sessionContext
        )

        state.applyLoadingFailure(
            "Unable to load the current selection.",
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "0 Unread Items",
            retainsContent: false,
            sessionContext: sessionContext
        )

        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
        #expect(state.articleListSession.context.normalizedSearchText == "swift")
    }

    @Test
    func articlesScreenMutationActionsPreservePhaseGuardsAcrossSearchAndClearTransitions() {
        var state = ArticlesScreenState()
        let baseItem = makeArticleListItemDTO(title: "SwiftUI Weekly", isRead: false)
        let selection = SidebarSelection.feed(baseItem.feedID)

        state.applyLoadedArticles(
            [baseItem],
            selection: selection,
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        #expect(state.toolbarActions.showsMarkAllAsReadAction)

        state.beginLoading(
            for: selection,
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            resetsContent: true,
            startsNewSession: true,
            sessionContext: ArticleListSession.Context(
                selection: selection,
                sidebarArticleFilter: .allItems,
                normalizedSearchText: "swift"
            )
        )
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)

        state.applyLoadedArticles(
            [],
            selection: selection,
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            sessionContext: ArticleListSession.Context(
                selection: selection,
                sidebarArticleFilter: .allItems,
                normalizedSearchText: "swift"
            ),
            emptyContentKind: .searchResults
        )
        #expect(state.toolbarActions.showsMarkAllAsReadAction)

        state.beginLoading(
            for: selection,
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            resetsContent: true,
            startsNewSession: true,
            sessionContext: ArticleListSession.Context(
                selection: selection,
                sidebarArticleFilter: .allItems,
                normalizedSearchText: ""
            )
        )
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)

        state.applyLoadedArticles(
            [baseItem],
            selection: selection,
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item"
        )
        #expect(state.toolbarActions.showsMarkAllAsReadAction)
    }

    @Test
    func articleListSearchLifecycleKeepsSearchUIAttachedAcrossCompactBackAndReentry() {
        let selection = SidebarSelection.unread
        let activeState = ArticleListSearchLifecycleState(
            retainedSelection: selection,
            presentedSelection: selection
        )
        let compactBackState = ArticleListSearchLifecycleState(
            retainedSelection: selection,
            presentedSelection: nil
        )
        let reentryState = ArticleListSearchLifecycleState(
            retainedSelection: selection,
            presentedSelection: selection
        )
        let invalidatedState = ArticleListSearchLifecycleState(
            retainedSelection: nil,
            presentedSelection: nil
        )

        #expect(activeState.keepsSearchUIAttached)
        #expect(activeState.allowsQueryLoad)
        #expect(compactBackState.keepsSearchUIAttached)
        #expect(compactBackState.allowsQueryLoad == false)
        #expect(reentryState.keepsSearchUIAttached)
        #expect(reentryState.allowsQueryLoad)
        #expect(invalidatedState.keepsSearchUIAttached == false)
        #expect(invalidatedState.allowsQueryLoad == false)
    }
}
