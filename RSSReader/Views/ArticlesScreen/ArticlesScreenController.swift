import Foundation
import Observation

nonisolated enum ArticlesScreenSearchPolicy {
    static let debounceDuration: Duration = .milliseconds(250)
}

nonisolated enum ArticlesScreenPaginationPolicy {
    static let pageSize = 50
}

struct ArticleListContinuationSnapshot: Equatable, Sendable {
    let sessionID: UUID
    let visibleArticleIDs: [UUID]
    let hasMorePages: Bool
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
    @ObservationIgnored private var activeNextPageTask: Task<ArticleListContinuationSnapshot?, Never>?
    @ObservationIgnored private var activeNextPageIdentity: ArticleListNextPageIdentity?
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
            refreshesScopeMetric: true,
            dependencies: dependencies
        )
        guard loadPlan.sessionContextChanged else { return nil }

        loadGeneration += 1
        let currentLoadGeneration = loadGeneration
        activeLoadTask?.cancel()
        cancelActiveNextPageLoad()
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
        cancelActiveNextPageLoad()
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
            articleID: article.id
        )
        return true
    }

    func load(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        searchText: String = "",
        dependencies: AppDependencies,
        refreshesScopeMetric: Bool = false,
        retainsSessionFilterMutations: Bool = false,
        retainedSessionMembershipStatus: ArticleListEntryMembershipStatus = .retainedAfterFilterMutation,
        preservesRefreshFeedback: Bool = false
    ) async {
        let loadPlan = makeLoadPlan(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            searchText: searchText,
            refreshesScopeMetric: refreshesScopeMetric,
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
        cancelActiveNextPageLoad()
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
                loadsScopeMetric: plan.refreshesScopeMetric,
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
            let resolvedScopeMetric = loadResult.scopeMetric
                ?? screenState.articleListSession.scopeMetric
            let navigationSubtitle = ArticlesScreenSubtitleResolver.resolve(
                articles: resolvedArticles,
                sidebarArticleFilter: plan.sidebarArticleFilter,
                scopeMetric: resolvedScopeMetric
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
                nextPageCursor: loadResult.nextPageCursor,
                scopeMetric: resolvedScopeMetric
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
        refreshesScopeMetric: Bool,
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
            refreshesScopeMetric: refreshesScopeMetric,
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
                    scopeMetric: screenState.articleListSession.scopeMetric
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

    private func cancelActiveNextPageLoad() {
        activeNextPageTask?.cancel()
        activeNextPageTask = nil
        activeNextPageIdentity = nil
        screenState.endLoadingNextPage()
    }

    private func isCurrentNextPageLoad(
        _ identity: ArticleListNextPageIdentity
    ) -> Bool {
        identity.generation == loadGeneration
            && identity.sessionID == screenState.articleListSession.id
            && identity.context == lastLoadedSessionContext
            && identity.context == screenState.articleListSession.context
            && identity.cursor == screenState.articleListSession.nextPageCursor
    }

    private func currentContinuationSnapshot(
        for identity: ArticleListNextPageIdentity
    ) -> ArticleListContinuationSnapshot? {
        guard identity.generation == loadGeneration,
              identity.sessionID == screenState.articleListSession.id,
              identity.context == screenState.articleListSession.context else {
            return nil
        }

        return ArticleListContinuationSnapshot(
            sessionID: identity.sessionID,
            visibleArticleIDs: visibleArticleIDs(),
            hasMorePages: screenState.articleListSession.nextPageCursor != nil
        )
    }

    private func performNextPageLoad(
        identity: ArticleListNextPageIdentity,
        articleQueryService: any ArticleQueryService,
        dependencies: AppDependencies
    ) async -> ArticleListContinuationSnapshot? {
        do {
            let loadResult = try await loadArticles(
                for: identity.context.selection,
                sidebarArticleFilter: identity.context.sidebarArticleFilter,
                normalizedSearchText: identity.context.normalizedSearchText,
                sortMode: identity.context.sortMode,
                loadsScopeMetric: false,
                articleQueryService: articleQueryService,
                cursor: identity.cursor
            )
            try Task.checkCancellation()
            guard isCurrentNextPageLoad(identity),
                  identity.context == articleListSessionContext(
                    selection: identity.context.selection,
                    sidebarArticleFilter: identity.context.sidebarArticleFilter,
                    normalizedSearchText: identity.context.normalizedSearchText,
                    dependencies: dependencies
                  ) else {
                return nil
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
                    sidebarArticleFilter: identity.context.sidebarArticleFilter,
                    scopeMetric: loadResult.scopeMetric
                        ?? screenState.articleListSession.scopeMetric
                ),
                scopeMetric: loadResult.scopeMetric
            )
            return currentContinuationSnapshot(for: identity)
        } catch is CancellationError {
            if isCurrentNextPageLoad(identity) {
                screenState.endLoadingNextPage()
            }
            return nil
        } catch {
            guard isCurrentNextPageLoad(identity) else { return nil }
            dependencies.logger.error(
                "Failed to load next article list page for selection \(String(describing: identity.context.selection)): \(error)"
            )
            screenState.endLoadingNextPage()
            return currentContinuationSnapshot(for: identity)
        }
    }

    @discardableResult
    func loadNextPage(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        searchText: String = "",
        dependencies: AppDependencies
    ) async -> ArticleListContinuationSnapshot? {
        let requestedContext = articleListSessionContext(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            normalizedSearchText: ArticleSearchScope.normalizedSearchText(searchText),
            dependencies: dependencies
        )
        guard requestedContext == screenState.articleListSession.context else {
            return nil
        }

        return await loadNextPage(dependencies: dependencies)
    }

    @discardableResult
    func loadNextPage(
        dependencies: AppDependencies
    ) async -> ArticleListContinuationSnapshot? {
        let sessionContext = screenState.articleListSession.context
        guard sessionContext == lastLoadedSessionContext,
              sessionContext == articleListSessionContext(
                selection: sessionContext.selection,
                sidebarArticleFilter: sessionContext.sidebarArticleFilter,
                normalizedSearchText: sessionContext.normalizedSearchText,
                dependencies: dependencies
              ),
              let nextPageCursor = screenState.articleListSession.nextPageCursor else {
            return nil
        }

        let identity = ArticleListNextPageIdentity(
            generation: loadGeneration,
            sessionID: screenState.articleListSession.id,
            context: sessionContext,
            cursor: nextPageCursor
        )
        if activeNextPageIdentity == identity,
           let activeNextPageTask {
            return await activeNextPageTask.value
        }

        guard activeNextPageTask == nil,
              let articleQueryService = dependencies.articleQueryService,
              screenState.beginLoadingNextPage() else {
            return nil
        }

        let nextPageTask = Task<ArticleListContinuationSnapshot?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            return await performNextPageLoad(
                identity: identity,
                articleQueryService: articleQueryService,
                dependencies: dependencies
            )
        }
        activeNextPageIdentity = identity
        activeNextPageTask = nextPageTask

        let snapshot = await nextPageTask.value
        if activeNextPageIdentity == identity {
            activeNextPageIdentity = nil
            activeNextPageTask = nil
        }
        return snapshot
    }

    func hasNextPageContinuation(for sessionID: UUID) -> Bool {
        sessionID == screenState.articleListSession.id
            && screenState.articleListSession.nextPageCursor != nil
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
        loadsScopeMetric: Bool,
        articleQueryService: any ArticleQueryService,
        cursor: ArticleSearchRequest.Cursor? = nil
    ) async throws -> ArticleListLoadResult {
        let request = ArticleSearchRequest(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            query: normalizedSearchText,
            sortMode: sortMode,
            limit: pageSize,
            cursor: cursor,
            scopeMetricLoadingPolicy: loadsScopeMetric ? .baseScope : .none
        )
        let snapshot = try await searchQueryOperation(request, articleQueryService)

        return ArticleListLoadResult(
            articles: snapshot.articles,
            emptyContentKind: emptyContentKind(snapshot: snapshot, request: request),
            nextPageCursor: snapshot.nextCursor,
            scopeMetric: snapshot.scopeMetric
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
    let scopeMetric: ArticleScopeMetric?
}

private struct ArticleListNextPageIdentity: Equatable {
    let generation: Int
    let sessionID: UUID
    let context: ArticleListSession.Context
    let cursor: ArticleSearchRequest.Cursor
}

private struct ArticlesScreenLoadPlan {
    let selection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let normalizedSearchText: String
    let refreshesScopeMetric: Bool
    let sortMode: ArticleSortMode
    let sessionContext: ArticleListSession.Context
    let sessionContextChanged: Bool
    let navigationTitle: String
    let loadingSubtitle: String
}
