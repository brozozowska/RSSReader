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
    var searchText = ""
    private var searchSelection: SidebarSelection?

    func selectSearchScope(_ selection: SidebarSelection?) {
        guard searchSelection != selection else { return }
        searchSelection = selection
        searchText = ""
    }

    func searchText(for selection: SidebarSelection?) -> String {
        searchSelection == selection ? searchText : ""
    }
    @ObservationIgnored private let searchDebounceOperation: ArticlesScreenSearchDebounceOperation
    @ObservationIgnored private let queryLoader: ArticlesScreenQueryLoader
    @ObservationIgnored let scopeReadMutationOperation: ArticlesScreenScopeReadMutationOperation
    @ObservationIgnored let pageSize: Int
    @ObservationIgnored private let primaryLoad = ArticlesScreenPrimaryLoadLifecycle()
    @ObservationIgnored private let continuationLoad = ArticlesScreenContinuationLifecycle()
    @ObservationIgnored let readerScrollCoordinator = ArticleListReaderScrollCoordinator()
    @ObservationIgnored private var lastAppliedReadOnOpenEventID: UUID?
    @ObservationIgnored private let refreshLifecycle = ArticlesScreenRefreshLifecycle()
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
        self.queryLoader = ArticlesScreenQueryLoader(
            pageSize: pageSize,
            queryOperation: searchQueryOperation ?? { request, articleQueryService in
                try await articleQueryService.fetchArticleSearchSnapshot(request)
            }
        )
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
        selectSearchScope(selection)
        let loadPlan = makeLoadPlan(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            searchText: searchText,
            refreshesScopeMetric: true,
            dependencies: dependencies
        )
        guard loadPlan.sessionContextChanged else { return nil }
        refreshLifecycle.reset()

        return startLoad(plan: loadPlan, policy: .retainSession, feedback: .dismiss, dependencies: dependencies)
    }

    var currentArticleListSessionID: UUID {
        screenState.articleListSession.id
    }

    func endPresentation() {
        primaryLoad.cancel()
        refreshLifecycle.reset()
        cancelActiveNextPageLoad()
        lastLoadedSessionContext = .noSelection
        readerScrollCoordinator.reset()
        screenState.endPresentation()
    }

    @discardableResult
    func suspendLoadsForCoveredArticleList() -> Bool {
        let hadActivePrimaryLoad = primaryLoad.isActive
        primaryLoad.cancel()
        cancelActiveNextPageLoad()
        screenState.cancelSearchTransition()
        return hadActivePrimaryLoad
    }

    func markArticleAsReadInCurrentSession(_ articleID: UUID) {
        screenState.markArticleAsReadInCurrentSession(articleID: articleID)
    }

    @discardableResult
    func applyArticleReadOnOpenEvent(_ event: ArticleReadOnOpenEvent) -> Bool {
        guard event.id != lastAppliedReadOnOpenEventID,
              event.articleListSessionID == currentArticleListSessionID,
              event.sidebarSelection == screenState.articleListSession.context.selection,
              event.sidebarArticleFilter == screenState.articleListSession.context.sidebarArticleFilter,
              let article = screenState.articles.first(where: { $0.id == event.articleID }) else {
            return false
        }

        lastAppliedReadOnOpenEventID = event.id
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

    @discardableResult
    func applyArticleStateMutation(
        articleID: UUID,
        persistedState: ArticleUserStateSnapshot,
        in listSession: ArticleListSessionReference
    ) -> Bool {
        let context = screenState.articleListSession.context
        guard listSession.id == currentArticleListSessionID,
              listSession.sidebarSelection == context.selection,
              listSession.sidebarArticleFilter == context.sidebarArticleFilter,
              let article = screenState.articles.first(where: { $0.id == articleID }),
              article.feedID == persistedState.feedID,
              article.articleExternalID == persistedState.articleExternalID else { return false }

        let updatedArticle = article.updating(
            isRead: persistedState.isRead,
            isStarred: persistedState.isStarred
        )
        let retainsMembership = (context.articleListFilter == .starred && !persistedState.isStarred)
            || (context.articleListFilter == .unread && persistedState.isRead)
        applyArticleRowMutation(
            .update(updatedArticle, membershipStatus: retainsMembership ? .retainedAfterFilterMutation : nil),
            articleID: articleID
        )
        return true
    }

    func load(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        searchText: String = "",
        dependencies: AppDependencies,
        scopeMetric: ArticleSearchRequest.ScopeMetricLoadingPolicy = .none,
        policy: ArticlesScreenLoadPolicy = .replace,
        feedback: ArticlesScreenLoadFeedbackPolicy = .dismiss
    ) async {
        let loadPlan = makeLoadPlan(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            searchText: searchText,
            refreshesScopeMetric: scopeMetric == .baseScope,
            dependencies: dependencies
        )
        if loadPlan.sessionContextChanged {
            refreshLifecycle.reset()
        }
        if policy.retainsSession,
           let task = primaryLoad.activeTask(for: loadPlan.sessionContext) {
            await task.value
            return
        }

        let task = startLoad(plan: loadPlan, policy: policy, feedback: feedback, dependencies: dependencies)
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func startLoad(
        plan: ArticlesScreenLoadPlan,
        policy: ArticlesScreenLoadPolicy,
        feedback: ArticlesScreenLoadFeedbackPolicy,
        dependencies: AppDependencies
    ) -> Task<Void, Never> {
        cancelActiveNextPageLoad()
        prepareScreenStateForLoad(
            plan,
            startsNewSession: plan.sessionContextChanged || policy.retainsSession == false
        )
        let sessionID = screenState.articleListSession.id
        return primaryLoad.start(context: plan.sessionContext) { [weak self] generation in
            guard let self else { return }
            await performLoad(
                plan: plan,
                dependencies: dependencies,
                policy: policy,
                feedback: feedback,
                sessionID: sessionID,
                generation: generation
            )
        }
    }

    private func performLoad(
        plan: ArticlesScreenLoadPlan,
        dependencies: AppDependencies,
        policy: ArticlesScreenLoadPolicy,
        feedback: ArticlesScreenLoadFeedbackPolicy,
        sessionID currentSessionID: UUID,
        generation currentLoadGeneration: Int
    ) async {
        do {
            if plan.selection != nil, plan.isSearchTransition || plan.normalizedSearchText.isEmpty == false {
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
                    retainsContent: plan.isSearchTransition,
                    sessionContext: plan.sessionContext
                )
                lastLoadedSessionContext = screenState.articleListSession.context
                return
            }

            let loadResult = try await queryLoader.load(
                for: plan.selection,
                sidebarArticleFilter: plan.sidebarArticleFilter,
                normalizedSearchText: plan.normalizedSearchText,
                sortMode: plan.sortMode,
                loadsScopeMetric: plan.refreshesScopeMetric,
                articleQueryService: articleQueryService
            )
            try Task.checkCancellation()
            let preservesCurrentMaterializedSnapshot = plan.sessionContextChanged == false
                && plan.isSearchTransition == false && policy.preservesMaterializedSnapshot
            let resolvedEntries = entriesByRetainingSessionItems(
                loadResult.articles,
                selection: plan.selection,
                sidebarArticleFilter: plan.sidebarArticleFilter,
                retainsCurrentContent: plan.sessionContextChanged == false
                    && plan.isSearchTransition == false && policy.retainsSession,
                preservesMaterializedSessionSnapshot: preservesCurrentMaterializedSnapshot,
                retainedMembershipStatus: policy.retainedMembershipStatus,
                sortMode: plan.sortMode
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
                preservesRefreshFeedback: feedback == .preserve,
                emptyContentKind: loadResult.emptyContentKind,
                nextPageCursor: preservesCurrentMaterializedSnapshot
                    ? screenState.articleListSession.nextPageCursor
                    : loadResult.nextPageCursor,
                scopeMetric: resolvedScopeMetric
            )
        } catch is CancellationError {
            if isCurrentLoad(
                generation: currentLoadGeneration,
                sessionID: currentSessionID,
                context: plan.sessionContext
            ) {
                screenState.cancelSearchTransition()
            }
            return
        } catch {
            guard isCurrentLoad(
                generation: currentLoadGeneration,
                sessionID: currentSessionID,
                context: plan.sessionContext
            ) else { return }
            dependencies.logger.error(
                "Failed to load article list for selection \(String(describing: plan.selection)): \(error)"
            )
            screenState.applyLoadingFailure(
                ReadingLocalization.articlesLoadFailedMessage,
                selection: plan.selection,
                navigationTitle: plan.navigationTitle,
                navigationSubtitle: plan.loadingSubtitle,
                retainsContent: plan.isSearchTransition || plan.sessionContextChanged == false,
                sessionContext: plan.sessionContext
            )
            lastLoadedSessionContext = screenState.articleListSession.context
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
        let isSearchTransition = screenState.canPresentSearchTransition(to: sessionContext)
            && (sessionContextChanged || screenState.pendingSearchContext != nil)

        return ArticlesScreenLoadPlan(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            normalizedSearchText: normalizedSearchText,
            refreshesScopeMetric: refreshesScopeMetric,
            sortMode: sortMode,
            sessionContext: sessionContext,
            sessionContextChanged: sessionContextChanged,
            isSearchTransition: isSearchTransition,
            navigationTitle: resolveNavigationTitle(
                selection: selection,
                dependencies: dependencies
            ),
            loadingSubtitle: sessionContextChanged && isSearchTransition == false
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
        if plan.isSearchTransition {
            screenState.beginSearchTransition(to: plan.sessionContext)
            return
        }
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
        generation == primaryLoad.generation
            && sessionID == screenState.articleListSession.id
            && context == (screenState.pendingSearchContext ?? screenState.articleListSession.context)
    }

    private func cancelActiveNextPageLoad() {
        continuationLoad.cancel()
        screenState.endLoadingNextPage()
    }

    private func isCurrentNextPageLoad(
        _ identity: ArticleListNextPageIdentity
    ) -> Bool {
        identity.generation == primaryLoad.generation
            && identity.sessionID == screenState.articleListSession.id
            && identity.context == lastLoadedSessionContext
            && identity.context == screenState.articleListSession.context
            && identity.cursor == screenState.articleListSession.nextPageCursor
    }

    private func currentContinuationSnapshot(
        for identity: ArticleListNextPageIdentity
    ) -> ArticleListContinuationSnapshot? {
        guard identity.generation == primaryLoad.generation,
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
            let loadResult = try await queryLoader.load(
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
        guard screenState.pendingSearchContext == nil,
              sessionContext == lastLoadedSessionContext,
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
            generation: primaryLoad.generation,
            sessionID: screenState.articleListSession.id,
            context: sessionContext,
            cursor: nextPageCursor
        )
        if let task = continuationLoad.activeTask(for: identity) {
            return await task.value
        }

        guard continuationLoad.isActive == false,
              let articleQueryService = dependencies.articleQueryService,
              screenState.beginLoadingNextPage() else {
            return nil
        }

        let nextPageTask = continuationLoad.start(identity: identity) { [weak self] in
            guard let self else { return nil }
            return await performNextPageLoad(
                identity: identity,
                articleQueryService: articleQueryService,
                dependencies: dependencies
            )
        }
        return await nextPageTask.value
    }

    func followReaderArticle(
        _ articleID: UUID,
        direction: ReaderAdjacentArticleNavigationDirection,
        in sessionReference: ArticleListSessionReference?
    ) {
        let session = screenState.articleListSession
        guard let sessionReference,
              sessionReference.id == session.id,
              sessionReference.sidebarSelection == session.context.selection,
              sessionReference.sidebarArticleFilter == session.context.sidebarArticleFilter else { return }
        readerScrollCoordinator.reveal(
            articleID,
            direction: direction,
            sessionID: session.id,
            sections: ArticlesDaySectionsBuilder.build(from: session.articles)
        )
    }

    func hasNextPageContinuation(for sessionID: UUID) -> Bool {
        screenState.pendingSearchContext == nil
            && sessionID == screenState.articleListSession.id
            && screenState.articleListSession.nextPageCursor != nil
    }

    @discardableResult
    func refreshCurrentSelection(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        dependencies: AppDependencies,
        appState: AppState,
        requestsArticleListReload: Bool = true,
        reloadsSnapshotOnSuccess: Bool = false
    ) async -> FeedRefreshBatchResult? {
        let refreshContext = ManualFeedRefreshContext(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
        let currentSessionContext = screenState.articleListSession.context
        guard screenState.pendingSearchContext == nil,
              currentSessionContext.selection == refreshContext.selection,
              currentSessionContext.sidebarArticleFilter == refreshContext.sidebarArticleFilter else {
            dependencies.logger.info("Skipped manual refresh for stale article-list context")
            return nil
        }

        screenState.dismissRefreshFeedback()
        let feedRefreshID = screenState.beginFeedRefresh()
        defer { screenState.endFeedRefresh(ifMatching: feedRefreshID) }
        let identity = refreshLifecycle.begin(
            sessionID: currentArticleListSessionID,
            context: screenState.articleListSession.context
        )
        let result = await refreshLifecycle.refresh(
            context: refreshContext,
            dependencies: dependencies,
            appState: appState,
            requestsArticleListReload: requestsArticleListReload
        )

        guard refreshLifecycle.isCurrent(
            identity,
            sessionID: currentArticleListSessionID,
            context: screenState.articleListSession.context
        ) else { return result }

        refreshLifecycle.accept(result)

        if let result, let refreshFailureMessage = refreshLifecycle.failureMessage(for: result) {
            screenState.presentRefreshFailure(refreshFailureMessage)
            return result
        }

        if result == nil, selection != nil {
            screenState.presentRefreshFailure(ReadingLocalization.refreshCurrentSelectionFailed)
            return nil
        }

        if reloadsSnapshotOnSuccess, result != nil, Task.isCancelled == false {
            await load(
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                searchText: identity.context.normalizedSearchText,
                dependencies: dependencies,
                scopeMetric: .baseScope
            )
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
        preservesMaterializedSessionSnapshot: Bool,
        retainedMembershipStatus: ArticleListEntryMembershipStatus,
        sortMode: ArticleSortMode
    ) -> [ArticleListEntry] {
        if preservesMaterializedSessionSnapshot {
            return ArticleListSessionMergePolicy.mergePreservingMaterializedSnapshot(
                currentEntries: screenState.articleListSession.entries,
                loadedArticles: loadedArticles,
                sortMode: sortMode
            )
        }

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
                retainedMembershipStatus: retainedMembershipStatus,
                sortMode: sortMode
            )
        }

        return ArticleListSessionMergePolicy.merge(
            currentEntries: screenState.articleListSession.entries,
            loadedArticles: loadedArticles,
            retainedArticleIDs: [],
            retainsCurrentContent: true,
            retainedMembershipStatus: retainedMembershipStatus,
            sortMode: sortMode
        )
    }
}

private struct ArticlesScreenLoadPlan {
    let selection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let normalizedSearchText: String
    let refreshesScopeMetric: Bool
    let sortMode: ArticleSortMode
    let sessionContext: ArticleListSession.Context
    let sessionContextChanged: Bool
    let isSearchTransition: Bool
    let navigationTitle: String
    let loadingSubtitle: String
}
