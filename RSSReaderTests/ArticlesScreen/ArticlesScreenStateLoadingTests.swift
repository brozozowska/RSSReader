import Foundation
import Testing
@testable import RSSReader

@Suite("Articles Screen / State / Loading")
@MainActor
struct ArticlesScreenStateLoadingTests {
    @Test
    func articlesScreenStateStartsWithoutSelectionPlaceholder() {
        let state = ArticlesScreenState()

        #expect(state.phase == .noSelection)
        #expect(state.navigationTitle == "Articles")
        #expect(state.navigationSubtitle == "No Unread Items")
        #expect(state.customRefreshState == .idle)
        #expect(state.articleListSession.context == .noSelection)
        #expect(state.articleListSession.entries.isEmpty)
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
    func articlesScreenStateMaterializesLoadedArticlesIntoSessionSnapshot() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let context = ArticleListSession.Context(
            selection: .feed(unreadItem.feedID),
            sourcesFilter: .unread
        )

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: "1 Unread Item",
            sessionContext: context
        )

        #expect(state.articleListSession.context == context)
        #expect(state.articleListSession.context.articleListFilter == .unread)
        #expect(state.articleListSession.entries.map(\.id) == [unreadItem.id])
        #expect(state.articleListSession.entries.map(\.membershipStatus) == [.matchesCurrentQuery])
        #expect(state.articles.map(\.id) == [unreadItem.id])
    }

    @Test
    func articlesScreenStatePreservesExplicitEntryMembershipInSessionSnapshot() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)

        state.applyLoadedEntries(
            [
                ArticleListEntry(
                    article: unreadItem,
                    membershipStatus: .retainedAfterRefresh
                )
            ],
            selection: .unread,
            navigationTitle: "Unread",
            navigationSubtitle: "No Unread Items",
            sessionContext: ArticleListSession.Context(
                selection: .unread,
                sourcesFilter: .allItems
            )
        )

        #expect(state.phase == .loaded)
        #expect(state.articleListSession.entries.map(\.membershipStatus) == [.retainedAfterRefresh])
        #expect(state.articles.map(\.id) == [unreadItem.id])
    }

    @Test
    func articleListSessionMergeUpdatesExistingRowsAddsNewRowsAndKeepsRetainedEntries() {
        let retainedID = UUID()
        let updatedID = UUID()
        let newID = UUID()
        let retainedArticle = makeArticleListItemDTO(
            id: retainedID,
            title: "Read In Session",
            isRead: false
        )
        let staleArticle = makeArticleListItemDTO(
            id: updatedID,
            title: "Old Title",
            isRead: false
        )
        let updatedArticle = makeArticleListItemDTO(
            id: updatedID,
            title: "Updated Title",
            isRead: true
        )
        let newArticle = makeArticleListItemDTO(
            id: newID,
            title: "New Query Article",
            isRead: false
        )

        let mergedEntries = ArticleListSessionMergePolicy.merge(
            currentEntries: [
                ArticleListEntry(
                    article: retainedArticle,
                    membershipStatus: .retainedAfterRead
                ),
                ArticleListEntry(article: staleArticle)
            ],
            loadedArticles: [updatedArticle, newArticle],
            retainedArticleIDs: [],
            retainsCurrentContent: true,
            retainedMembershipStatus: .retainedAfterRefresh
        )

        #expect(mergedEntries.map(\.id) == [retainedID, updatedID, newID])
        #expect(mergedEntries.map(\.article.title) == ["Read In Session", "Updated Title", "New Query Article"])
        #expect(mergedEntries.map(\.membershipStatus) == [.retainedAfterRefresh, .matchesCurrentQuery, .matchesCurrentQuery])
        #expect(mergedEntries[1].article.isRead)
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
}
