import Foundation
import Observation

@MainActor
@Observable
final class ArticlesScreenController {
    var screenState: ArticlesScreenState
    private var lastLoadedSourceSelection: SidebarSelection?
    private var loadGeneration = 0

    init(previewScreenState: ArticlesScreenState? = nil) {
        self.screenState = previewScreenState ?? ArticlesScreenState()
        self.lastLoadedSourceSelection = previewScreenState?.selection
    }

    func shouldResetArticleSelection(for selection: SidebarSelection?) -> Bool {
        lastLoadedSourceSelection != selection
    }

    func load(
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        dependencies: AppDependencies,
        sessionReadArticleIDs: Set<UUID> = []
    ) async {
        loadGeneration += 1
        let currentLoadGeneration = loadGeneration
        let sourceSelectionChanged = shouldResetArticleSelection(for: selection)
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
            resetsContent: sourceSelectionChanged
        )

        defer {
            if currentLoadGeneration == loadGeneration {
                lastLoadedSourceSelection = selection
            }
        }

        guard let articleQueryService = dependencies.articleQueryService else {
            screenState.applyLoadingFailure(
                "Article query service is unavailable.",
                selection: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: loadingSubtitle,
                retainsContent: false
            )
            return
        }

        let sortMode = loadSortMode(dependencies: dependencies)

        do {
            let loadedArticles = try loadArticles(
                for: selection,
                sourcesFilter: sourcesFilter,
                sortMode: sortMode,
                articleQueryService: articleQueryService
            )
            let resolvedArticles = articlesByRetainingSessionReadItems(
                loadedArticles,
                selection: selection,
                sourcesFilter: sourcesFilter,
                sessionReadArticleIDs: sessionReadArticleIDs,
                retainsCurrentContent: sourceSelectionChanged == false
            )

            guard currentLoadGeneration == loadGeneration else { return }
            screenState.applyLoadedArticles(
                resolvedArticles,
                selection: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: resolveNavigationSubtitle(
                    for: resolvedArticles,
                    sourcesFilter: sourcesFilter
                )
            )
        } catch {
            guard currentLoadGeneration == loadGeneration else { return }
            dependencies.logger.error("Failed to load article list for selection \(String(describing: selection)): \(error)")
            screenState.applyLoadingFailure(
                error.localizedDescription,
                selection: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: loadingSubtitle,
                retainsContent: sourceSelectionChanged == false
            )
        }
    }

    func applySessionReadArticleIDs(
        _ articleIDs: Set<UUID>,
        sourcesFilter: SourcesFilter
    ) {
        guard articleIDs.isEmpty == false else { return }

        let updatedArticles = screenState.articles.map { article in
            articleIDs.contains(article.id)
                ? article.updating(isRead: true, isStarred: article.isStarred)
                : article
        }

        guard updatedArticles != screenState.articles else { return }

        screenState.applySessionArticleUpdates(
            updatedArticles,
            navigationSubtitle: resolveNavigationSubtitle(
                for: updatedArticles,
                sourcesFilter: sourcesFilter
            )
        )
    }

    func refreshCurrentSelection(
        selection: SidebarSelection?,
        dependencies: AppDependencies,
        appState: AppState
    ) async {
        screenState.dismissRefreshFeedback()
        let result = await dependencies.refreshCurrentSelection(using: appState)

        if let result, let refreshFailureMessage = refreshFailureMessage(for: result) {
            screenState.presentRefreshFailure(refreshFailureMessage)
            return
        }

        if result == nil, selection != nil {
            screenState.presentRefreshFailure("Unable to refresh the current selection right now.")
        }
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

    private func loadSortMode(dependencies: AppDependencies) -> ArticleSortMode {
        guard let appSettingsService = dependencies.appSettingsService else {
            return .publishedAtAscending
        }

        do {
            return try appSettingsService.fetchSettings().sortMode
        } catch {
            dependencies.logger.error("Failed to load app settings for article sort mode: \(error)")
            return .publishedAtAscending
        }
    }

    private func loadArticles(
        for selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        sortMode: ArticleSortMode,
        articleQueryService: any ArticleQueryService
    ) throws -> [ArticleListItemDTO] {
        switch selection {
        case .inbox:
            try articleQueryService.fetchInboxListItems(
                sortMode: sortMode,
                filter: SourcesFilterArticleListFilterResolver.resolve(for: sourcesFilter)
            )
        case .unread:
            try articleQueryService.fetchInboxListItems(
                sortMode: sortMode,
                filter: .unread
            )
        case .starred:
            try articleQueryService.fetchInboxListItems(
                sortMode: sortMode,
                filter: .starred
            )
        case .folder(let folderName):
            try articleQueryService.fetchFolderListItems(
                folderName: folderName,
                sortMode: sortMode,
                filter: SourcesFilterArticleListFilterResolver.resolve(for: sourcesFilter)
            )
        case .feed(let selectedFeedID):
            try articleQueryService.fetchArticleListItems(
                feedID: selectedFeedID,
                sortMode: sortMode,
                filter: SourcesFilterArticleListFilterResolver.resolve(for: sourcesFilter)
            )
        case .none:
            []
        }
    }

    private func articlesByRetainingSessionReadItems(
        _ loadedArticles: [ArticleListItemDTO],
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        sessionReadArticleIDs: Set<UUID>,
        retainsCurrentContent: Bool
    ) -> [ArticleListItemDTO] {
        guard retainsCurrentContent,
              sessionReadArticleIDs.isEmpty == false,
              ArticlesScreenMutationReducer.articleListFilter(
                selection: selection,
                sourcesFilter: sourcesFilter
              ) == .unread else {
            return loadedArticles
        }

        var loadedArticlesByID: [UUID: ArticleListItemDTO] = [:]
        for loadedArticle in loadedArticles where loadedArticlesByID[loadedArticle.id] == nil {
            loadedArticlesByID[loadedArticle.id] = loadedArticle
        }
        var emittedArticleIDs = Set<UUID>()
        var resolvedArticles: [ArticleListItemDTO] = []

        for currentArticle in screenState.articles {
            if let loadedArticle = loadedArticlesByID[currentArticle.id] {
                resolvedArticles.append(loadedArticle)
                emittedArticleIDs.insert(loadedArticle.id)
            } else if sessionReadArticleIDs.contains(currentArticle.id) {
                resolvedArticles.append(
                    currentArticle.updating(
                        isRead: true,
                        isStarred: currentArticle.isStarred
                    )
                )
                emittedArticleIDs.insert(currentArticle.id)
            }
        }

        for loadedArticle in loadedArticles where emittedArticleIDs.contains(loadedArticle.id) == false {
            resolvedArticles.append(loadedArticle)
        }

        return resolvedArticles
    }

    private func refreshFailureMessage(for result: FeedRefreshBatchResult) -> String? {
        guard result.summary.failedCount > 0 else {
            return nil
        }

        if let firstError = result.failureDescriptions.first {
            if result.summary.failedCount == 1 {
                return firstError
            }
            return "\(result.summary.failedCount) sources failed to refresh. First error: \(firstError)"
        }

        if result.summary.failedCount == 1 {
            return "The current source failed to refresh."
        }

        return "\(result.summary.failedCount) sources failed to refresh."
    }
}
