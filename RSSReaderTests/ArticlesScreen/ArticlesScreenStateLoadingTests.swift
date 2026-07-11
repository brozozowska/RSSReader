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
        #expect(state.navigationTitle == ReadingLocalization.articlesTitle)
        #expect(state.navigationSubtitle == ReadingLocalization.noUnreadItemsSubtitle)
        #expect(state.customRefreshState == .idle)
        #expect(state.articleListSession.context == .noSelection)
        #expect(state.articleListSession.entries.isEmpty)
        #expect(state.placeholder?.title == ReadingLocalization.noSidebarSelectionTitle)
        #expect(state.toolbarActions.showsSearchAction == false)
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenStateBeginsPrimaryLoadingWhenSelectionChanges() {
        var state = ArticlesScreenState()

        state.beginLoading(
            for: .unread,
            navigationTitle: ReadingLocalization.unreadTitle,
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 3),
            resetsContent: true
        )

        #expect(state.phase == .loading)
        #expect(state.navigationTitle == ReadingLocalization.unreadTitle)
        #expect(state.navigationSubtitle == ReadingLocalization.unreadItemsSubtitle(count: 3))
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
            navigationTitle: ReadingLocalization.starredTitle,
            navigationSubtitle: ReadingLocalization.starredItemsSubtitle(count: 0)
        )

        #expect(state.phase == .empty)
        #expect(state.navigationTitle == ReadingLocalization.starredTitle)
        #expect(state.navigationSubtitle == ReadingLocalization.starredItemsSubtitle(count: 0))
        #expect(state.placeholder?.title == ReadingLocalization.noArticlesTitle)
        #expect(state.placeholder?.description == ReadingLocalization.starredEmptyDescription)
    }

    @Test
    func articlesScreenStateMaterializesLoadedArticlesIntoSessionSnapshot() {
        var state = ArticlesScreenState()
        let unreadItem = makeArticleListItemDTO(isRead: false, isStarred: false)
        let context = ArticleListSession.Context(
            selection: .feed(unreadItem.feedID),
            sidebarArticleFilter: .unread
        )

        state.applyLoadedArticles(
            [unreadItem],
            selection: .feed(unreadItem.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1),
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
            navigationTitle: ReadingLocalization.unreadTitle,
            navigationSubtitle: ReadingLocalization.noUnreadItemsSubtitle,
            sessionContext: ArticleListSession.Context(
                selection: .unread,
                sidebarArticleFilter: .allItems
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
                    membershipStatus: .retainedAfterFilterMutation
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
            ReadingLocalization.articleListQueryUnavailableMessage,
            selection: .inbox,
            navigationTitle: ReadingLocalization.allItemsTitle,
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 0),
            retainsContent: false
        )

        #expect(state.phase == .failed(ReadingLocalization.articleListQueryUnavailableMessage))
        #expect(state.primaryFailureMessage == ReadingLocalization.articleListQueryUnavailableMessage)
        #expect(state.refreshFeedback == nil)
    }
}
