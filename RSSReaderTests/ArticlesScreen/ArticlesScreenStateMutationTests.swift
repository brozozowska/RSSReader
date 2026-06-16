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
            mutation: .update(updatedItem),
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 0)
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 0))
        #expect(state.articleListSession.entries.count == 1)
        #expect(state.articleListSession.entries.first?.article.isRead == true)
        #expect(state.articles.count == 1)
        #expect(state.articles.first?.isRead == true)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
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
                sourcesFilter: .allItems
            )
        )

        state.markArticleAsReadInCurrentSession(articleID: unreadItem.id)

        #expect(state.phase == .loaded)
        #expect(state.articles.map(\.id) == [unreadItem.id])
        #expect(state.articles.first?.isRead == true)
        #expect(state.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRead])
        #expect(state.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(state.toolbarActions.isMarkAllAsReadEnabled == false)
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
                membershipStatus: .retainedAfterRead
            ),
            navigationSubtitle: ReadingLocalization.noUnreadItemsSubtitle
        )

        #expect(state.phase == .loaded)
        #expect(state.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(state.articles.map(\.id) == [unreadItem.id])
        #expect(state.articles.first?.isRead == true)
        #expect(state.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRead])
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
            mutation: .update(updatedItem),
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )

        #expect(state.phase == .loaded)
        #expect(state.articles.first?.isStarred == true)
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 1))
    }

    @Test
    func articlesScreenStateRemovesArticleRowWhenUnstarredInsideStarredSelection() {
        var state = ArticlesScreenState()
        let starredItem = makeArticleListItemDTO(isRead: true, isStarred: true)

        state.applyLoadedArticles(
            [starredItem],
            selection: .starred,
            navigationTitle: ReadingLocalization.starredTitle,
            navigationSubtitle: ReadingLocalization.starredItemsSubtitle(count: 1)
        )
        state.applyArticleRowMutation(
            articleID: starredItem.id,
            mutation: .remove,
            navigationSubtitle: ReadingLocalization.starredItemsSubtitle(count: 0)
        )

        #expect(state.phase == .empty)
        #expect(state.navigationSubtitle == ReadingLocalization.starredItemsSubtitle(count: 0))
        #expect(state.articles.isEmpty)
    }
}
