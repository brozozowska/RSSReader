import Foundation
import Observation

@MainActor
@Observable
final class ArticlesScreenController {
    var screenState: ArticlesScreenState
    private var lastLoadedSessionContext: ArticleListSession.Context
    private var loadGeneration = 0

    init(previewScreenState: ArticlesScreenState? = nil) {
        self.screenState = previewScreenState ?? ArticlesScreenState()
        if let previewScreenState {
            self.lastLoadedSessionContext = previewScreenState.articleListSession.context
        } else {
            self.lastLoadedSessionContext = .noSelection
        }
    }

    func shouldResetArticleSelection(for selection: SidebarSelection?) -> Bool {
        lastLoadedSessionContext.selection != selection
    }

    func shouldResetArticleSession(for context: ArticleListSession.Context) -> Bool {
        lastLoadedSessionContext != context
    }

    func markArticleAsReadInCurrentSession(_ articleID: UUID) {
        screenState.markArticleAsReadInCurrentSession(articleID: articleID)
    }

    func load(
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        dependencies: AppDependencies,
        retainsSessionReadArticles: Bool = false,
        retainedSessionReadMembershipStatus: ArticleListEntryMembershipStatus = .retainedAfterRead,
        preservesRefreshFeedback: Bool = false
    ) async {
        loadGeneration += 1
        let currentLoadGeneration = loadGeneration
        let sessionContext = ArticleListSession.Context(
            selection: selection,
            sourcesFilter: sourcesFilter
        )
        let sessionContextChanged = shouldResetArticleSession(for: sessionContext)
        let navigationTitle = resolveNavigationTitle(
            selection: selection,
            dependencies: dependencies
        )
        let loadingSubtitle = resolveNavigationSubtitle(
            for: screenState.articles,
            sourcesFilter: sourcesFilter
        )
        screenState.beginLoading(
            for: selection,
            navigationTitle: navigationTitle,
            navigationSubtitle: loadingSubtitle,
            resetsContent: sessionContextChanged,
            sessionContext: sessionContext
        )

        defer {
            if currentLoadGeneration == loadGeneration {
                lastLoadedSessionContext = sessionContext
            }
        }

        guard let articleQueryService = dependencies.articleQueryService else {
            screenState.applyLoadingFailure(
                ReadingLocalization.articleListQueryUnavailableMessage,
                selection: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: loadingSubtitle,
                retainsContent: false,
                sessionContext: sessionContext
            )
            return
        }

        let unreadArticleSortMode = loadUnreadArticleSortMode(dependencies: dependencies)

        do {
            let loadedArticles = try loadArticles(
                for: selection,
                sourcesFilter: sourcesFilter,
                unreadArticleSortMode: unreadArticleSortMode,
                articleQueryService: articleQueryService
            )
            let resolvedEntries = entriesByRetainingSessionReadItems(
                loadedArticles,
                selection: selection,
                sourcesFilter: sourcesFilter,
                retainsCurrentContent: sessionContextChanged == false && retainsSessionReadArticles,
                retainedMembershipStatus: retainedSessionReadMembershipStatus
            )
            let subtitleArticles = resolvedEntries.map(\.article)

            guard currentLoadGeneration == loadGeneration else { return }
            screenState.applyLoadedEntries(
                resolvedEntries,
                selection: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: resolveNavigationSubtitle(
                    for: subtitleArticles,
                    sourcesFilter: sourcesFilter
                ),
                sessionContext: sessionContext,
                preservesRefreshFeedback: preservesRefreshFeedback
            )
        } catch {
            guard currentLoadGeneration == loadGeneration else { return }
            dependencies.logger.error("Failed to load article list for selection \(String(describing: selection)): \(error)")
            screenState.applyLoadingFailure(
                error.localizedDescription,
                selection: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: loadingSubtitle,
                retainsContent: sessionContextChanged == false,
                sessionContext: sessionContext
            )
        }
    }

    @discardableResult
    func refreshCurrentSelection(
        selection: SidebarSelection?,
        dependencies: AppDependencies,
        appState: AppState,
        requestsArticleListReload: Bool = true
    ) async -> FeedRefreshBatchResult? {
        screenState.dismissRefreshFeedback()
        let result = await dependencies.appActions.refreshCurrentSelection(
            using: appState,
            requestsArticleListReload: requestsArticleListReload
        )

        if let result, let refreshFailureMessage = refreshFailureMessage(for: result) {
            screenState.presentRefreshFailure(refreshFailureMessage)
            return result
        }

        if result == nil, selection != nil {
            screenState.presentRefreshFailure(ReadingLocalization.refreshCurrentSelectionFailed)
            return nil
        }

        return result
    }

    private func resolveNavigationTitle(
        selection: SidebarSelection?,
        dependencies: AppDependencies
    ) -> String {
        let selectedFeedTitle: String?
        if case .feed(let feedID) = selection {
            selectedFeedTitle = try? dependencies.feedRepository?.fetchFeed(id: feedID)?.displayTitle
        } else {
            selectedFeedTitle = nil
        }

        return ArticlesScreenNavigationTitleResolver.resolve(
            selection: selection,
            selectedFeedTitle: selectedFeedTitle
        )
    }

    private func resolveNavigationSubtitle(
        for articles: [ArticleListItemDTO],
        sourcesFilter: SourcesFilter
    ) -> String {
        ArticlesScreenSubtitleResolver.resolve(
            articles: articles,
            sourcesFilter: sourcesFilter
        )
    }

    private func loadUnreadArticleSortMode(dependencies: AppDependencies) -> ArticleSortMode {
        guard let appSettingsService = dependencies.appSettingsService else {
            return .publishedAtDescending
        }

        do {
            return try appSettingsService.fetchSettings().unreadArticleSortMode
        } catch {
            dependencies.logger.error("Failed to load app settings for unread article sort mode: \(error)")
            return .publishedAtDescending
        }
    }

    private func loadArticles(
        for selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        unreadArticleSortMode: ArticleSortMode,
        articleQueryService: any ArticleQueryService
    ) throws -> [ArticleListItemDTO] {
        let articleListFilter = articleListFilter(
            for: selection,
            sourcesFilter: sourcesFilter
        )
        let articleListSortMode = articleListSortMode(
            for: articleListFilter,
            unreadArticleSortMode: unreadArticleSortMode
        )

        return switch selection {
        case .inbox:
            try articleQueryService.fetchInboxListItems(
                sortMode: articleListSortMode,
                filter: articleListFilter
            )
        case .unread:
            try articleQueryService.fetchInboxListItems(
                sortMode: articleListSortMode,
                filter: articleListFilter
            )
        case .starred:
            try articleQueryService.fetchInboxListItems(
                sortMode: articleListSortMode,
                filter: articleListFilter
            )
        case .folder(let folderName):
            try articleQueryService.fetchFolderListItems(
                folderName: folderName,
                sortMode: articleListSortMode,
                filter: articleListFilter
            )
        case .feed(let selectedFeedID):
            try articleQueryService.fetchArticleListItems(
                feedID: selectedFeedID,
                sortMode: articleListSortMode,
                filter: articleListFilter
            )
        case .none:
            []
        }
    }

    private func articleListFilter(
        for selection: SidebarSelection?,
        sourcesFilter: SourcesFilter
    ) -> ArticleListFilter {
        switch selection {
        case .unread:
            .unread
        case .starred:
            .starred
        case .inbox, .folder, .feed, .none:
            SourcesFilterArticleListFilterResolver.resolve(for: sourcesFilter)
        }
    }

    private func articleListSortMode(
        for filter: ArticleListFilter,
        unreadArticleSortMode: ArticleSortMode
    ) -> ArticleSortMode {
        filter == .unread ? unreadArticleSortMode : .publishedAtDescending
    }

    private func entriesByRetainingSessionReadItems(
        _ loadedArticles: [ArticleListItemDTO],
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        retainsCurrentContent: Bool,
        retainedMembershipStatus: ArticleListEntryMembershipStatus
    ) -> [ArticleListEntry] {
        guard retainsCurrentContent,
              ArticlesScreenMutationReducer.articleListFilter(
                selection: selection,
                sourcesFilter: sourcesFilter
              ) == .unread else {
            return ArticleListSessionMergePolicy.merge(
                currentEntries: screenState.articleListSession.entries,
                loadedArticles: loadedArticles,
                retainedArticleIDs: [],
                retainsCurrentContent: false,
                retainedMembershipStatus: retainedMembershipStatus
            )
        }

        return ArticleListSessionMergePolicy.merge(
            currentEntries: screenState.articleListSession.entries,
            loadedArticles: loadedArticles,
            retainedArticleIDs: [],
            retainsCurrentContent: true,
            retainedMembershipStatus: retainedMembershipStatus
        )
    }

    private func refreshFailureMessage(for result: FeedRefreshBatchResult) -> String? {
        guard result.summary.failedCount > 0 else {
            return nil
        }

        if let firstError = result.failureDescriptions.first {
            if result.summary.failedCount == 1 {
                return firstError
            }
            return ReadingLocalization.multipleSourcesRefreshFailed(
                count: result.summary.failedCount,
                firstError: firstError
            )
        }

        if result.summary.failedCount == 1 {
            return ReadingLocalization.singleSourceRefreshFailed
        }

        return ReadingLocalization.multipleSourcesRefreshFailed(count: result.summary.failedCount)
    }
}
