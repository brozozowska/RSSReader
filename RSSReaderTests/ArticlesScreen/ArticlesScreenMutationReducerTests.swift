import Testing
@testable import RSSReader

@Suite("Articles Screen / Mutation Reducer")
@MainActor
struct ArticlesScreenMutationReducerTests {
    @Test
    func articlesScreenMutationReducerRemovesVisibleArticlesAfterMarkAllAsReadInUnreadFilter() {
        let firstUnread = makeArticleListItemDTO(isRead: false, isStarred: false)
        let secondUnread = makeArticleListItemDTO(isRead: false, isStarred: false)
        let remainingRead = makeArticleListItemDTO(isRead: true, isStarred: false)

        let updatedArticles = ArticlesScreenMutationReducer.reduceAfterMarkAllAsRead(
            visibleArticles: [firstUnread, secondUnread],
            allArticles: [firstUnread, secondUnread, remainingRead],
            filter: ArticleListFilter.unread
        )

        #expect(updatedArticles.map { $0.id } == [remainingRead.id])
    }

    @Test
    func articlesScreenMutationReducerProducesRemoveMutationWhenReadToggleHappensInUnreadFilter() {
        let unreadArticle = makeArticleListItemDTO(isRead: false, isStarred: false)

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleReadStatus(
            article: unreadArticle,
            filter: ArticleListFilter.unread
        )

        #expect(mutation == .remove)
    }

    @Test
    func articlesScreenMutationReducerProducesUnreadUpdateWhenReadArticleIsToggledBack() {
        let readArticle = makeArticleListItemDTO(isRead: true, isStarred: false)

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleReadStatus(
            article: readArticle,
            filter: ArticleListFilter.all
        )

        let updatedArticle: ArticleListItemDTO?
        if case .update(let article) = mutation {
            updatedArticle = article
        } else {
            updatedArticle = nil
        }

        #expect(updatedArticle?.isRead == false)
        #expect(updatedArticle?.isStarred == false)
    }

    @Test
    func articlesScreenMutationReducerProducesRemoveMutationWhenUnstarringInsideStarredFilter() {
        let starredArticle = makeArticleListItemDTO(isRead: true, isStarred: true)

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleStarred(
            article: starredArticle,
            filter: ArticleListFilter.starred
        )

        #expect(mutation == .remove)
    }
}
