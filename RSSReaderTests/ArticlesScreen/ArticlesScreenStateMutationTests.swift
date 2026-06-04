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
            navigationTitle: "Unread",
            navigationSubtitle: "1 Unread Item",
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
        #expect(state.navigationSubtitle == "No Unread Items")
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
