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
        #expect(state.toolbarActions.showsMarkAllAsReadAction == false)
    }

    @Test
    func articlesScreenStateEndsPresentationWithFreshEmptySession() {
        var state = ArticlesScreenState()
        let article = makeArticleListItemDTO()
        let context = ArticleListSession.Context(
            selection: .feed(article.feedID),
            sidebarArticleFilter: .unread
        )
        state.applyLoadedArticles(
            [article],
            selection: context.selection,
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1),
            sessionContext: context
        )
        let previousSessionID = state.articleListSession.id

        state.endPresentation()

        #expect(state.phase == .noSelection)
        #expect(state.selection == nil)
        #expect(state.articleListSession.id != previousSessionID)
        #expect(state.articleListSession.context == .noSelection)
        #expect(state.articleListSession.entries.isEmpty)
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
    func articlesScreenStateDisablesListAnimationForContextReplacementSnapshots() {
        var state = ArticlesScreenState()
        let firstFeedArticle = makeArticleListItemDTO()
        let secondFeedArticle = makeArticleListItemDTO()

        state.applyLoadedArticles(
            [firstFeedArticle],
            selection: .feed(firstFeedArticle.feedID),
            navigationTitle: "First Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )
        state.applyArticleRowMutation(
            articleID: firstFeedArticle.id,
            mutation: .update(firstFeedArticle)
        )

        #expect(state.listAnimationState.changeKind == .localMutation)

        state.beginLoading(
            for: .feed(secondFeedArticle.feedID),
            navigationTitle: "Second Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1),
            resetsContent: true
        )

        #expect(state.listAnimationState.changeKind == .snapshotReplacement)
        #expect(state.listAnimationState.allowsAnimation(reduceMotion: false) == false)

        state.applyLoadedArticles(
            [secondFeedArticle],
            selection: .feed(secondFeedArticle.feedID),
            navigationTitle: "Second Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )

        #expect(state.articleListSession.context.selection == .feed(secondFeedArticle.feedID))
        #expect(state.articles.map(\.id) == [secondFeedArticle.id])
        #expect(state.listAnimationState.changeKind == .snapshotReplacement)
        #expect(state.listAnimationState.allowsAnimation(reduceMotion: false) == false)
    }

    @Test
    func articlesScreenStateAnimatesIncrementalPageAppendUnlessReduceMotionIsEnabled() {
        var state = ArticlesScreenState()
        let firstArticle = makeArticleListItemDTO(
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let nextArticle = makeArticleListItemDTO(
            feedID: firstArticle.feedID,
            publishedAt: Date(timeIntervalSince1970: 100)
        )

        state.applyLoadedArticles(
            [firstArticle],
            selection: .feed(firstArticle.feedID),
            navigationTitle: "Feed",
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 1)
        )
        let snapshotRevision = state.listAnimationState.revision

        state.applyLoadedNextPage(
            [nextArticle],
            nextPageCursor: nil,
            navigationSubtitle: ReadingLocalization.unreadItemsSubtitle(count: 2)
        )

        #expect(state.articles.map(\.id) == [firstArticle.id, nextArticle.id])
        #expect(state.listAnimationState.revision == snapshotRevision + 1)
        #expect(state.listAnimationState.changeKind == .localMutation)
        #expect(state.listAnimationState.allowsAnimation(reduceMotion: false))
        #expect(state.listAnimationState.allowsAnimation(reduceMotion: true) == false)
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
            publishedAt: Date(timeIntervalSince1970: 300),
            isRead: false
        )
        let staleArticle = makeArticleListItemDTO(
            id: updatedID,
            title: "Old Title",
            publishedAt: Date(timeIntervalSince1970: 200),
            isRead: false
        )
        let updatedArticle = makeArticleListItemDTO(
            id: updatedID,
            title: "Updated Title",
            publishedAt: Date(timeIntervalSince1970: 200),
            isRead: true
        )
        let newArticle = makeArticleListItemDTO(
            id: newID,
            title: "New Query Article",
            publishedAt: Date(timeIntervalSince1970: 400),
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
            retainedMembershipStatus: .retainedAfterRefresh,
            sortMode: .publishedAtDescending
        )

        #expect(mergedEntries.map(\.id) == [newID, retainedID, updatedID])
        #expect(mergedEntries.map(\.article.title) == ["New Query Article", "Read In Session", "Updated Title"])
        #expect(mergedEntries.map(\.membershipStatus) == [.matchesCurrentQuery, .retainedAfterRefresh, .matchesCurrentQuery])
        #expect(mergedEntries[2].article.isRead)
    }

    @Test
    func articleListSessionMergeDeduplicatesMultiPageEntriesAndKeepsCanonicalAscendingOrder() {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        let currentArticles = (0..<60).map { index in
            makeArticleListItemDTO(
                title: "Current \(index)",
                publishedAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
        }
        let retainedArticle = currentArticles[55]
        let newArticle = makeArticleListItemDTO(
            title: "New First Page Article",
            publishedAt: baseDate.addingTimeInterval(-1)
        )
        let freshFirstPage = [newArticle] + Array(currentArticles.prefix(49))

        let firstMerge = ArticleListSessionMergePolicy.merge(
            currentEntries: currentArticles.enumerated().map { index, article in
                ArticleListEntry(
                    article: article,
                    membershipStatus: index == 55
                        ? .retainedAfterFilterMutation
                        : .matchesCurrentQuery
                )
            },
            loadedArticles: freshFirstPage + [freshFirstPage[10]],
            retainedArticleIDs: [],
            retainsCurrentContent: true,
            retainedMembershipStatus: .retainedAfterRefresh,
            sortMode: .publishedAtAscending
        )
        let repeatedMerge = ArticleListSessionMergePolicy.merge(
            currentEntries: firstMerge,
            loadedArticles: freshFirstPage,
            retainedArticleIDs: [],
            retainsCurrentContent: true,
            retainedMembershipStatus: .retainedAfterRefresh,
            sortMode: .publishedAtAscending
        )

        #expect(firstMerge.count == 51)
        #expect(Set(firstMerge.map(\.id)).count == firstMerge.count)
        #expect(firstMerge.map(\.id) == [newArticle.id] + currentArticles.prefix(49).map(\.id) + [retainedArticle.id])
        #expect(firstMerge.last?.membershipStatus == .retainedAfterRefresh)
        #expect(repeatedMerge == firstMerge)
    }

    @Test
    func articleListSessionAppendPageDeduplicatesAndRestoresCanonicalDescendingOrder() {
        let duplicateID = UUID()
        let olderArticle = makeArticleListItemDTO(
            title: "Older",
            publishedAt: Date(timeIntervalSince1970: 100)
        )
        let staleDuplicate = makeArticleListItemDTO(
            id: duplicateID,
            title: "Stale Duplicate",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let refreshedDuplicate = makeArticleListItemDTO(
            id: duplicateID,
            title: "Refreshed Duplicate",
            publishedAt: Date(timeIntervalSince1970: 200)
        )
        let newerArticle = makeArticleListItemDTO(
            title: "Newer",
            publishedAt: Date(timeIntervalSince1970: 300)
        )
        var session = ArticleListSession(
            context: ArticleListSession.Context(
                selection: .inbox,
                sidebarArticleFilter: .allItems,
                sortMode: .publishedAtDescending
            ),
            entries: [ArticleListEntry(article: olderArticle), ArticleListEntry(article: staleDuplicate)]
        )

        session.appendPage(
            [newerArticle, refreshedDuplicate, newerArticle],
            nextPageCursor: nil
        )

        #expect(session.entries.map(\.id) == [newerArticle.id, duplicateID, olderArticle.id])
        #expect(Set(session.entries.map(\.id)).count == session.entries.count)
        #expect(session.entries[1].article.title == "Refreshed Duplicate")
    }

    @Test
    func articleListSessionOrderingUsesStableArticleIdentityForEqualSortDates() throws {
        let lowerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let higherID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let tieDate = Date(timeIntervalSince1970: 500)
        let lowerArticle = makeArticleListItemDTO(
            id: lowerID,
            updatedAtSource: tieDate,
            fetchedAt: Date(timeIntervalSince1970: 800)
        )
        let higherArticle = makeArticleListItemDTO(
            id: higherID,
            updatedAtSource: tieDate,
            fetchedAt: Date(timeIntervalSince1970: 900)
        )

        let descendingEntries = ArticleListSessionMergePolicy.merge(
            currentEntries: [],
            loadedArticles: [lowerArticle, higherArticle],
            retainedArticleIDs: [],
            retainsCurrentContent: false,
            retainedMembershipStatus: .retainedAfterRefresh,
            sortMode: .publishedAtDescending
        )
        let ascendingEntries = ArticleListSessionMergePolicy.merge(
            currentEntries: [],
            loadedArticles: [higherArticle, lowerArticle],
            retainedArticleIDs: [],
            retainsCurrentContent: false,
            retainedMembershipStatus: .retainedAfterRefresh,
            sortMode: .publishedAtAscending
        )

        #expect(descendingEntries.map(\.id) == [higherID, lowerID])
        #expect(ascendingEntries.map(\.id) == [lowerID, higherID])
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
