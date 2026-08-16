import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / State / Mutations")
@MainActor
struct ArticlesScreenStateMutationTests {
    @Test
    func articlesScreenStateAppliesMarkAllAsReadAndRefreshesToolbarState() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: true)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
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
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 0)
        )

        #expect(state.pendingConfirmation == nil)
        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 0))
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
            navigationTitle: ReadingLocalization.unreadTitle,
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )
        state.presentMarkAllAsReadConfirmation()
        state.applyMarkAllAsRead([], navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 0))

        #expect(state.pendingConfirmation == nil)
        #expect(state.phase == .empty)
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 0))
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
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )
        state.applyArticleRowMutation(
            articleID: unreadItem.id,
            mutation: .update(updatedItem)
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(state.articleListSession.entries.count == 1)
        #expect(state.articleListSession.entries.first?.article.isRead == true)
        #expect(state.articles.count == 1)
        #expect(state.articles.first?.isRead == true)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
        #expect(state.listAnimationState.changeKind == .localMutation)
        #expect(state.listAnimationState.allowsAnimation(reduceMotion: false))
        #expect(state.listAnimationState.allowsAnimation(reduceMotion: true) == false)
    }

    @Test
    func articlesScreenStateUpdatesExactScopeMetricFromPersistedRowMutations() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: true)
        let readItem = unreadItem.updating(isRead: true, isStarred: true)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 42),
            scopeMetric: ArticleScopeMetric(kind: .unread, count: 42)
        )
        state.applyArticleRowMutation(
            articleID: unreadItem.id,
            mutation: .update(readItem)
        )

        #expect(state.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: 41))
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 41))

        state.applyArticleRowMutation(
            articleID: unreadItem.id,
            mutation: .update(readItem)
        )

        #expect(state.articleListSession.scopeMetric == ArticleScopeMetric(kind: .unread, count: 41))
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 41))
    }

    @Test
    func articlesScreenStateMarksUnreadSessionArticleAsReadWithoutRemovingIt() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedArticles(
            [unreadItem],
            selection: .unread,
            navigationTitle: ReadingLocalization.unreadTitle,
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1),
            sessionContext: ArticleListSession.Context(
                selection: .unread,
                sidebarArticleFilter: .allItems
            )
        )

        state.markArticleAsReadInCurrentSession(articleID: unreadItem.id)

        #expect(state.phase == .loaded)
        #expect(state.articles.map(\.id) == [unreadItem.id])
        #expect(state.articles.first?.isRead == true)
        #expect(state.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterFilterMutation])
        #expect(state.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)

        let derivedViewState = state.derivedViewState()

        #expect(derivedViewState.visibleArticles.map(\.id) == [unreadItem.id])
        #expect(derivedViewState.visibleArticles.first?.isRead == true)
        #expect(derivedViewState.toolbarActions.isMarkAllAsReadEnabled == false)
    }

    @Test
    func articlesScreenStateRetainsArticleRowForReadActionInUnreadSelection() {
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
            selection: .unread,
            navigationTitle: ReadingLocalization.unreadTitle,
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )
        state.applyArticleRowMutation(
            articleID: unreadItem.id,
            mutation: .update(
                updatedItem,
                membershipStatus: .retainedAfterFilterMutation
            )
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(state.articles.map(\.id) == [unreadItem.id])
        #expect(state.articles.first?.isRead == true)
        #expect(state.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterFilterMutation])
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
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
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )
        state.applyArticleRowMutation(
            articleID: item.id,
            mutation: .update(updatedItem)
        )

        #expect(state.phase == .loaded)
        #expect(state.articles.first?.isStarred == true)
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 1))
    }

    @Test
    func articlesScreenStateRetainsArticleRowWhenUnstarredInsideStarredSelection() {
        var state = ArticlesScreenState()
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)
        let updatedItem = makeArticleListItemDTO(
            id: starredItem.id,
            feedID: starredItem.feedID,
            articleExternalID: starredItem.articleExternalID,
            isRead: true,
            isStarred: false
        )

        state.applyLoadedArticles(
            [starredItem],
            selection: .starred,
            navigationTitle: ReadingLocalization.starredTitle,
            navigationSubtitle: ReadingLocalization.starredItemsSubtitle(count: 1),
            sessionContext: ArticleListSession.Context(
                selection: .starred,
                sidebarArticleFilter: .starred
            )
        )
        state.applyArticleRowMutation(
            articleID: starredItem.id,
            mutation: .update(
                updatedItem,
                membershipStatus: .retainedAfterFilterMutation
            )
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == ReadingLocalization.starredItemsSubtitle(count: 0))
        #expect(state.articles.map(\.id) == [starredItem.id])
        #expect(state.articles.first?.isStarred == false)
        #expect(state.derivedViewState().visibleArticles.map(\.id) == [starredItem.id])
        #expect(
            state.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterFilterMutation]
        )
    }

    @Test
    func articlesScreenStateUpdatesExactStarredMetricWhenPersistedMutationRemovesMembership() {
        var state = ArticlesScreenState()
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)
        let unstarredItem = starredItem.updating(isRead: true, isStarred: false)

        state.applyLoadedArticles(
            [starredItem],
            selection: .starred,
            navigationTitle: ReadingLocalization.starredTitle,
            navigationSubtitle: ReadingLocalization.starredItemsSubtitle(count: 8),
            sessionContext: ArticleListSession.Context(
                selection: .starred,
                sidebarArticleFilter: .starred
            ),
            scopeMetric: ArticleScopeMetric(kind: .starred, count: 8)
        )
        state.applyArticleRowMutation(
            articleID: starredItem.id,
            mutation: .update(
                unstarredItem,
                membershipStatus: .retainedAfterFilterMutation
            )
        )

        #expect(state.articleListSession.scopeMetric == ArticleScopeMetric(kind: .starred, count: 7))
        #expect(state.navigationSubtitle == ReadingLocalization.starredItemsSubtitle(count: 7))
    }
}
