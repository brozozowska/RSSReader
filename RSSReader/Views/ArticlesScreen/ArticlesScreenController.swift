import Foundation
import Observation

nonisolated enum ArticlesScreenSearchPolicy {
    static let debounceDuration: Duration = .milliseconds(250)
}

nonisolated enum ArticlesScreenPaginationPolicy {
    static let pageSize = 50
}

typealias ArticlesScreenSearchDebounceOperation = @MainActor () async throws -> Void
typealias ArticlesScreenSearchQueryOperation = @MainActor (
    ArticleSearchRequest,
    any ArticleQueryService
) async throws -> ArticleSearchResultSnapshot

@MainActor
@Observable
final class ArticlesScreenController {
    var screenState: ArticlesScreenState
    @ObservationIgnored private let searchDebounceOperation: ArticlesScreenSearchDebounceOperation
    @ObservationIgnored private let searchQueryOperation: ArticlesScreenSearchQueryOperation
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var activeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var loadGeneration = 0
    private var lastLoadedSessionContext: ArticleListSession.Context

    init(
        previewScreenState: ArticlesScreenState? = nil,
        searchDebounceOperation: ArticlesScreenSearchDebounceOperation? = nil,
        searchQueryOperation: ArticlesScreenSearchQueryOperation? = nil,
        pageSize: Int = ArticlesScreenPaginationPolicy.pageSize
    ) {
        precondition(pageSize > 0)
        self.screenState = previewScreenState ?? ArticlesScreenState()
        self.searchDebounceOperation = searchDebounceOperation ?? {
            try await Task.sleep(for: ArticlesScreenSearchPolicy.debounceDuration)
        }
        self.searchQueryOperation = searchQueryOperation ?? { request, articleQueryService in
            try articleQueryService.fetchArticleSearchSnapshot(request)
        }
        self.pageSize = pageSize
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
        sidebarArticleFilter: SidebarArticleFilter,
        searchText: String = "",
        dependencies: AppDependencies,
        retainsSessionFilterMutations: Bool = false,
        retainedSessionMembershipStatus: ArticleListEntryMembershipStatus = .retainedAfterFilterMutation,
        preservesRefreshFeedback: Bool = false
    ) async {
        loadGeneration += 1
        let currentLoadGeneration = loadGeneration
        activeLoadTask?.cancel()
        let loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await performLoad(
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                searchText: searchText,
                dependencies: dependencies,
                retainsSessionFilterMutations: retainsSessionFilterMutations,
                retainedSessionMembershipStatus: retainedSessionMembershipStatus,
                preservesRefreshFeedback: preservesRefreshFeedback,
                generation: currentLoadGeneration
            )
        }
        activeLoadTask = loadTask

        await withTaskCancellationHandler {
            await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }

        if currentLoadGeneration == loadGeneration {
            activeLoadTask = nil
        }
    }

    private func performLoad(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        searchText: String,
        dependencies: AppDependencies,
        retainsSessionFilterMutations: Bool,
        retainedSessionMembershipStatus: ArticleListEntryMembershipStatus,
        preservesRefreshFeedback: Bool,
        generation currentLoadGeneration: Int
    ) async {
        let normalizedSearchText = ArticleSearchScope.normalizedSearchText(searchText)
        let sessionContext = ArticleListSession.Context(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            normalizedSearchText: normalizedSearchText
        )
        let sessionContextChanged = shouldResetArticleSession(for: sessionContext)
        let navigationTitle = resolveNavigationTitle(
            selection: selection,
            dependencies: dependencies
        )
        let loadingSubtitle = resolveNavigationSubtitle(
            for: screenState.articles,
            sidebarArticleFilter: sidebarArticleFilter
        )

        do {
            if selection != nil, normalizedSearchText.isEmpty == false {
                try await searchDebounceOperation()
            }
            try Task.checkCancellation()
            guard currentLoadGeneration == loadGeneration else { return }

            screenState.beginLoading(
                for: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: loadingSubtitle,
                resetsContent: sessionContextChanged,
                sessionContext: sessionContext
            )

            guard let articleQueryService = dependencies.articleQueryService else {
                screenState.applyLoadingFailure(
                    ReadingLocalization.articleListQueryUnavailableMessage,
                    selection: selection,
                    navigationTitle: navigationTitle,
                    navigationSubtitle: loadingSubtitle,
                    retainsContent: false,
                    sessionContext: sessionContext
                )
                lastLoadedSessionContext = sessionContext
                return
            }

            let loadResult = try await loadArticles(
                for: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                normalizedSearchText: normalizedSearchText,
                unreadArticleSortMode: loadUnreadArticleSortMode(dependencies: dependencies),
                articleQueryService: articleQueryService
            )
            try Task.checkCancellation()
            let resolvedEntries = entriesByRetainingSessionItems(
                loadResult.articles,
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                retainsCurrentContent: sessionContextChanged == false && retainsSessionFilterMutations,
                retainedMembershipStatus: retainedSessionMembershipStatus
            )
            let subtitleArticles = resolvedEntries.map(\.article)

            guard currentLoadGeneration == loadGeneration else { return }
            lastLoadedSessionContext = sessionContext
            screenState.applyLoadedEntries(
                resolvedEntries,
                selection: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: resolveNavigationSubtitle(
                    for: subtitleArticles,
                    sidebarArticleFilter: sidebarArticleFilter
                ),
                sessionContext: sessionContext,
                preservesRefreshFeedback: preservesRefreshFeedback,
                emptyContentKind: loadResult.emptyContentKind,
                nextPageCursor: loadResult.nextPageCursor
            )
        } catch is CancellationError {
            return
        } catch {
            guard currentLoadGeneration == loadGeneration else { return }
            lastLoadedSessionContext = sessionContext
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

    func loadNextPage(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        searchText: String = "",
        dependencies: AppDependencies
    ) async {
        let normalizedSearchText = ArticleSearchScope.normalizedSearchText(searchText)
        let sessionContext = ArticleListSession.Context(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            normalizedSearchText: normalizedSearchText
        )
        guard sessionContext == lastLoadedSessionContext,
              sessionContext == screenState.articleListSession.context,
              let nextPageCursor = screenState.articleListSession.nextPageCursor,
              screenState.beginLoadingNextPage() else {
            return
        }

        let currentLoadGeneration = loadGeneration
        guard let articleQueryService = dependencies.articleQueryService else {
            screenState.endLoadingNextPage()
            return
        }

        do {
            let loadResult = try await loadArticles(
                for: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                normalizedSearchText: normalizedSearchText,
                unreadArticleSortMode: loadUnreadArticleSortMode(dependencies: dependencies),
                articleQueryService: articleQueryService,
                cursor: nextPageCursor
            )
            try Task.checkCancellation()
            guard currentLoadGeneration == loadGeneration,
                  sessionContext == lastLoadedSessionContext,
                  sessionContext == screenState.articleListSession.context else {
                screenState.endLoadingNextPage()
                return
            }

            let existingArticleIDs = Set(screenState.articles.map(\.id))
            let newArticles = loadResult.articles.filter {
                existingArticleIDs.contains($0.id) == false
            }
            let allArticles = screenState.articles + newArticles
            screenState.applyLoadedNextPage(
                newArticles,
                nextPageCursor: loadResult.nextPageCursor,
                navigationSubtitle: resolveNavigationSubtitle(
                    for: allArticles,
                    sidebarArticleFilter: sidebarArticleFilter
                )
            )
        } catch is CancellationError {
            screenState.endLoadingNextPage()
        } catch {
            dependencies.logger.error(
                "Failed to load next article list page for selection \(String(describing: selection)): \(error)"
            )
            screenState.endLoadingNextPage()
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
        sidebarArticleFilter: SidebarArticleFilter
    ) -> String {
        ArticlesScreenSubtitleResolver.resolve(
            articles: articles,
            sidebarArticleFilter: sidebarArticleFilter
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
        sidebarArticleFilter: SidebarArticleFilter,
        normalizedSearchText: String,
        unreadArticleSortMode: ArticleSortMode,
        articleQueryService: any ArticleQueryService,
        cursor: ArticleSearchRequest.Cursor? = nil
    ) async throws -> ArticleListLoadResult {
        let articleListFilter = articleListFilter(
            for: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
        let articleListSortMode = articleListSortMode(
            for: articleListFilter,
            unreadArticleSortMode: unreadArticleSortMode
        )

        let request = ArticleSearchRequest(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            query: normalizedSearchText,
            sortMode: articleListSortMode,
            limit: pageSize,
            cursor: cursor
        )
        let snapshot = try await searchQueryOperation(request, articleQueryService)

        return ArticleListLoadResult(
            articles: snapshot.articles,
            emptyContentKind: emptyContentKind(snapshot: snapshot, request: request),
            nextPageCursor: snapshot.nextCursor
        )
    }

    private func emptyContentKind(
        snapshot: ArticleSearchResultSnapshot,
        request: ArticleSearchRequest
    ) -> ArticlesScreenEmptyContentKind {
        guard snapshot.articles.isEmpty,
              request.normalizedQuery.isEmpty == false else {
            return .selection
        }

        return snapshot.hasScopeContent ? .searchResults : .selection
    }

    private func articleListFilter(
        for selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) -> ArticleListFilter {
        ArticleSearchScope.listFilter(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
    }

    private func articleListSortMode(
        for filter: ArticleListFilter,
        unreadArticleSortMode: ArticleSortMode
    ) -> ArticleSortMode {
        filter == .unread ? unreadArticleSortMode : .publishedAtDescending
    }

    private func entriesByRetainingSessionItems(
        _ loadedArticles: [ArticleListItemDTO],
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        retainsCurrentContent: Bool,
        retainedMembershipStatus: ArticleListEntryMembershipStatus
    ) -> [ArticleListEntry] {
        let filter = ArticlesScreenMutationReducer.articleListFilter(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
        guard retainsCurrentContent,
              filter == .unread || filter == .starred else {
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
            return ReadingLocalization.multipleFeedsRefreshFailed(
                count: result.summary.failedCount,
                firstError: firstError
            )
        }

        if result.summary.failedCount == 1 {
            return ReadingLocalization.singleFeedRefreshFailed
        }

        return ReadingLocalization.multipleFeedsRefreshFailed(count: result.summary.failedCount)
    }
}

private struct ArticleListLoadResult {
    let articles: [ArticleListItemDTO]
    let emptyContentKind: ArticlesScreenEmptyContentKind
    let nextPageCursor: ArticleSearchRequest.Cursor?
}
