import Foundation
import Observation

@MainActor
@Observable
final class ArticlesScreenController {
    var screenState: ArticlesScreenState
    private var lastLoadedSourceSelection: SidebarSelection?

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
        dependencies: AppDependencies
    ) async {
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
            lastLoadedSourceSelection = selection
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

            screenState.applyLoadedArticles(
                loadedArticles,
                selection: selection,
                navigationTitle: navigationTitle,
                navigationSubtitle: resolveNavigationSubtitle(
                    for: loadedArticles,
                    sourcesFilter: sourcesFilter
                )
            )
        } catch {
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
            selectedFeedTitle = try? dependencies.feedRepository?.fetchFeed(id: feedID)?.title
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
        guard let appSettingsRepository = dependencies.appSettingsRepository else {
            return .publishedAtDescending
        }

        do {
            return try appSettingsRepository.fetchOrCreate().sortMode
        } catch {
            dependencies.logger.error("Failed to load app settings for article sort mode: \(error)")
            return .publishedAtDescending
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
