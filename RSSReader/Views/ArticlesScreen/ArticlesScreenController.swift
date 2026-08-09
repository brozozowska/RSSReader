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
typealias ArticlesScreenScopeReadMutationOperation = @MainActor (
    ArticleSearchRequest,
    any ArticleStateServicing,
    any ArticleQueryService
) async throws -> ArticleScopeReadMutationResult

@MainActor
@Observable
final class ArticlesScreenController {
    var screenState: ArticlesScreenState
    @ObservationIgnored private let searchDebounceOperation: ArticlesScreenSearchDebounceOperation
    @ObservationIgnored private let searchQueryOperation: ArticlesScreenSearchQueryOperation
    @ObservationIgnored let scopeReadMutationOperation: ArticlesScreenScopeReadMutationOperation
    @ObservationIgnored let pageSize: Int
    @ObservationIgnored private var activeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var activeLoadSessionContext: ArticleListSession.Context?
    @ObservationIgnored private var loadGeneration = 0
    private var lastLoadedSessionContext: ArticleListSession.Context

    init(
        previewScreenState: ArticlesScreenState? = nil,
        searchDebounceOperation: ArticlesScreenSearchDebounceOperation? = nil,
        searchQueryOperation: ArticlesScreenSearchQueryOperation? = nil,
        scopeReadMutationOperation: ArticlesScreenScopeReadMutationOperation? = nil,
        pageSize: Int = ArticlesScreenPaginationPolicy.pageSize
    ) {
        precondition(pageSize > 0)
        self.screenState = previewScreenState ?? ArticlesScreenState()
        self.searchDebounceOperation = searchDebounceOperation ?? {
            try await Task.sleep(for: ArticlesScreenSearchPolicy.debounceDuration)
        }
        self.searchQueryOperation = searchQueryOperation ?? { request, articleQueryService in
            try await articleQueryService.fetchArticleSearchSnapshot(request)
        }
        self.scopeReadMutationOperation = scopeReadMutationOperation ?? {
            request,
            articleStateService,
            articleQueryService in
            try await articleStateService.markAllMatchingAsRead(
                request: request,
                articleQueryService: articleQueryService,
                at: .now
            )
        }
        self.pageSize = pageSize
        if let previewScreenState {
            self.lastLoadedSessionContext = previewScreenState.articleListSession.context
        } else {
            self.lastLoadedSessionContext = .noSelection
        }
    }

    func shouldResetArticleSelection(for selection: SidebarSelection?) -> Bool {
        screenState.articleListSession.context.selection != selection
    }

    func shouldResetArticleSession(for context: ArticleListSession.Context) -> Bool {
        screenState.articleListSession.context != context
    }

    func prepareForPresentation(
        selection: SidebarSelection,
        sidebarArticleFilter: SidebarArticleFilter,
        dependencies: AppDependencies
    ) -> Task<Void, Never>? {
        let loadPlan = makeLoadPlan(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            searchText: "",
            dependencies: dependencies
        )
        guard loadPlan.sessionContextChanged else { return nil }

        loadGeneration += 1
        let currentLoadGeneration = loadGeneration
        activeLoadTask?.cancel()
        prepareScreenStateForLoad(loadPlan, startsNewSession: true)
        let currentSessionID = screenState.articleListSession.id
        let loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await performLoad(
                plan: loadPlan,
                dependencies: dependencies,
                retainsSessionFilterMutations: true,
                retainedSessionMembershipStatus: .retainedAfterFilterMutation,
                preservesRefreshFeedback: false,
                sessionID: currentSessionID,
                generation: currentLoadGeneration
            )
        }
        activeLoadTask = loadTask
        activeLoadSessionContext = loadPlan.sessionContext
        Task { @MainActor [weak self] in
            await loadTask.value
            guard let self, currentLoadGeneration == loadGeneration else { return }
            activeLoadTask = nil
            activeLoadSessionContext = nil
        }
        return loadTask
    }

    var currentArticleListSessionID: UUID {
        screenState.articleListSession.id
    }

    func endPresentation() {
        loadGeneration += 1
        activeLoadTask?.cancel()
        activeLoadTask = nil
        activeLoadSessionContext = nil
        lastLoadedSessionContext = .noSelection
        screenState.endPresentation()
    }

    func markArticleAsReadInCurrentSession(_ articleID: UUID) {
        screenState.markArticleAsReadInCurrentSession(articleID: articleID)
    }

    @discardableResult
    func applyArticleReadOnOpenEvent(_ event: ArticleReadOnOpenEvent) -> Bool {
        guard event.articleListSessionID == currentArticleListSessionID,
              event.sidebarSelection == screenState.articleListSession.context.selection,
              event.sidebarArticleFilter == screenState.articleListSession.context.sidebarArticleFilter,
              let article = screenState.articles.first(where: { $0.id == event.articleID }) else {
            return false
        }

        applyArticleRowMutation(
            ArticlesScreenMutationReducer.mutationAfterSettingReadStatus(
                article: article,
                isRead: event.isRead,
                filter: screenState.articleListSession.context.articleListFilter
            ),
            articleID: article.id,
            sidebarArticleFilter: screenState.articleListSession.context.sidebarArticleFilter
        )
        return true
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
        let loadPlan = makeLoadPlan(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            searchText: searchText,
            dependencies: dependencies
        )
        if retainsSessionFilterMutations,
           activeLoadSessionContext == loadPlan.sessionContext,
           let activeLoadTask {
            await activeLoadTask.value
            return
        }

        loadGeneration += 1
        let currentLoadGeneration = loadGeneration
        activeLoadTask?.cancel()
        prepareScreenStateForLoad(
            loadPlan,
            startsNewSession: loadPlan.sessionContextChanged || retainsSessionFilterMutations == false
        )
        let currentSessionID = screenState.articleListSession.id
        let loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await performLoad(
                plan: loadPlan,
                dependencies: dependencies,
                retainsSessionFilterMutations: retainsSessionFilterMutations,
                retainedSessionMembershipStatus: retainedSessionMembershipStatus,
                preservesRefreshFeedback: preservesRefreshFeedback,
                sessionID: currentSessionID,
                generation: currentLoadGeneration
            )
        }
        activeLoadTask = loadTask
        activeLoadSessionContext = loadPlan.sessionContext

        await withTaskCancellationHandler {
            await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }

        if currentLoadGeneration == loadGeneration {
            activeLoadTask = nil
            activeLoadSessionContext = nil
        }
    }

    private func performLoad(
        plan: ArticlesScreenLoadPlan,
        dependencies: AppDependencies,
        retainsSessionFilterMutations: Bool,
        retainedSessionMembershipStatus: ArticleListEntryMembershipStatus,
        preservesRefreshFeedback: Bool,
        sessionID currentSessionID: UUID,
        generation currentLoadGeneration: Int
    ) async {
        do {
            if plan.selection != nil, plan.normalizedSearchText.isEmpty == false {
                try await searchDebounceOperation()
            }
            try Task.checkCancellation()
            guard isCurrentLoad(
                generation: currentLoadGeneration,
                sessionID: currentSessionID,
                context: plan.sessionContext
            ) else { return }

            guard let articleQueryService = dependencies.articleQueryService else {
                screenState.applyLoadingFailure(
                    ReadingLocalization.articleListQueryUnavailableMessage,
                    selection: plan.selection,
                    navigationTitle: plan.navigationTitle,
                    navigationSubtitle: plan.loadingSubtitle,
                    retainsContent: false,
                    sessionContext: plan.sessionContext
                )
                lastLoadedSessionContext = plan.sessionContext
                return
            }

            let loadResult = try await loadArticles(
                for: plan.selection,
                sidebarArticleFilter: plan.sidebarArticleFilter,
                normalizedSearchText: plan.normalizedSearchText,
                sortMode: plan.sortMode,
                articleQueryService: articleQueryService
            )
            try Task.checkCancellation()
            let resolvedEntries = entriesByRetainingSessionItems(
                loadResult.articles,
                selection: plan.selection,
                sidebarArticleFilter: plan.sidebarArticleFilter,
                retainsCurrentContent: plan.sessionContextChanged == false && retainsSessionFilterMutations,
                retainedMembershipStatus: retainedSessionMembershipStatus
            )
            let resolvedArticles = resolvedEntries.map(\.article)
            let navigationSubtitle = ArticlesScreenSubtitleResolver.resolve(
                articles: resolvedArticles,
                sidebarArticleFilter: plan.sidebarArticleFilter,
                hasMorePages: loadResult.nextPageCursor != nil
            )
            guard isCurrentLoad(
                generation: currentLoadGeneration,
                sessionID: currentSessionID,
                context: plan.sessionContext
            ) else { return }
            lastLoadedSessionContext = plan.sessionContext
            screenState.applyLoadedEntries(
                resolvedEntries,
                selection: plan.selection,
                navigationTitle: plan.navigationTitle,
                navigationSubtitle: navigationSubtitle,
                sessionContext: plan.sessionContext,
                preservesRefreshFeedback: preservesRefreshFeedback,
                emptyContentKind: loadResult.emptyContentKind,
                nextPageCursor: loadResult.nextPageCursor
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentLoad(
                generation: currentLoadGeneration,
                sessionID: currentSessionID,
                context: plan.sessionContext
            ) else { return }
            lastLoadedSessionContext = plan.sessionContext
            dependencies.logger.error(
                "Failed to load article list for selection \(String(describing: plan.selection)): \(error)"
            )
            screenState.applyLoadingFailure(
                error.localizedDescription,
                selection: plan.selection,
                navigationTitle: plan.navigationTitle,
                navigationSubtitle: plan.loadingSubtitle,
                retainsContent: plan.sessionContextChanged == false,
                sessionContext: plan.sessionContext
            )
        }
    }

    private func makeLoadPlan(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        searchText: String,
        dependencies: AppDependencies
    ) -> ArticlesScreenLoadPlan {
        let normalizedSearchText = ArticleSearchScope.normalizedSearchText(searchText)
        let sortMode = articleListSortMode(
            for: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            dependencies: dependencies
        )
        let sessionContext = ArticleListSession.Context(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            normalizedSearchText: normalizedSearchText,
            sortMode: sortMode
        )
        let sessionContextChanged = shouldResetArticleSession(for: sessionContext)

        return ArticlesScreenLoadPlan(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            normalizedSearchText: normalizedSearchText,
            sortMode: sortMode,
            sessionContext: sessionContext,
            sessionContextChanged: sessionContextChanged,
            navigationTitle: resolveNavigationTitle(
                selection: selection,
                dependencies: dependencies
            ),
            loadingSubtitle: sessionContextChanged
                ? ReadingLocalization.loadingArticlesTitle
                : ArticlesScreenSubtitleResolver.resolve(
                    articles: screenState.articles,
                    sidebarArticleFilter: sidebarArticleFilter,
                    hasMorePages: screenState.articleListSession.nextPageCursor != nil
                )
        )
    }

    private func prepareScreenStateForLoad(
        _ plan: ArticlesScreenLoadPlan,
        startsNewSession: Bool
    ) {
        screenState.beginLoading(
            for: plan.selection,
            navigationTitle: plan.navigationTitle,
            navigationSubtitle: plan.loadingSubtitle,
            resetsContent: plan.sessionContextChanged,
            startsNewSession: startsNewSession,
            sessionContext: plan.sessionContext
        )
    }

    private func isCurrentLoad(
        generation: Int,
        sessionID: UUID,
        context: ArticleListSession.Context
    ) -> Bool {
        generation == loadGeneration
            && sessionID == screenState.articleListSession.id
            && context == screenState.articleListSession.context
    }

    func loadNextPage(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        searchText: String = "",
        dependencies: AppDependencies
    ) async {
        let normalizedSearchText = ArticleSearchScope.normalizedSearchText(searchText)
        let effectiveSortMode = articleListSortMode(
            for: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            dependencies: dependencies
        )
        let sessionContext = ArticleListSession.Context(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            normalizedSearchText: normalizedSearchText,
            sortMode: effectiveSortMode
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
                sortMode: effectiveSortMode,
                articleQueryService: articleQueryService,
                cursor: nextPageCursor
            )
            try Task.checkCancellation()
            guard currentLoadGeneration == loadGeneration,
                  sessionContext == lastLoadedSessionContext,
                  sessionContext == screenState.articleListSession.context,
                  sessionContext == articleListSessionContext(
                    selection: selection,
                    sidebarArticleFilter: sidebarArticleFilter,
                    normalizedSearchText: normalizedSearchText,
                    dependencies: dependencies
                  ) else {
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
                navigationSubtitle: ArticlesScreenSubtitleResolver.resolve(
                    articles: allArticles,
                    sidebarArticleFilter: sidebarArticleFilter,
                    hasMorePages: loadResult.nextPageCursor != nil
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
        sortMode: ArticleSortMode,
        articleQueryService: any ArticleQueryService,
        cursor: ArticleSearchRequest.Cursor? = nil
    ) async throws -> ArticleListLoadResult {
        let request = ArticleSearchRequest(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            query: normalizedSearchText,
            sortMode: sortMode,
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

    private func articleListSortMode(
        for selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        dependencies: AppDependencies
    ) -> ArticleSortMode {
        articleListSortMode(
            for: articleListFilter(
                for: selection,
                sidebarArticleFilter: sidebarArticleFilter
            ),
            unreadArticleSortMode: loadUnreadArticleSortMode(dependencies: dependencies)
        )
    }

    private func articleListSessionContext(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        normalizedSearchText: String,
        dependencies: AppDependencies
    ) -> ArticleListSession.Context {
        ArticleListSession.Context(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            normalizedSearchText: normalizedSearchText,
            sortMode: articleListSortMode(
                for: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                dependencies: dependencies
            )
        )
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

private struct ArticlesScreenLoadPlan {
    let selection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let normalizedSearchText: String
    let sortMode: ArticleSortMode
    let sessionContext: ArticleListSession.Context
    let sessionContextChanged: Bool
    let navigationTitle: String
    let loadingSubtitle: String
}
