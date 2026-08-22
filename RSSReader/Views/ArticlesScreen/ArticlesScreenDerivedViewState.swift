import Foundation

struct ArticlesScreenDerivedViewState {
    let visibleArticles: [ArticleListItemDTO]
    let sections: [ArticlesDaySection]
    let listAnimationState: ArticleListAnimationState
    let navigationChrome: ArticlesScreenNavigationChromeState
    let toolbarActions: ArticlesScreenToolbarActionsState
    let searchPlaceholder: ArticlesScreenPlaceholderState?
    let customRefreshState: ArticlesScreenCustomRefreshState
    let refreshBanner: ArticlesScreenRefreshBannerState?
    let primaryLoadingState: ArticlesScreenPrimaryLoadingState?
}

extension ArticlesScreenState {
    func derivedViewState() -> ArticlesScreenDerivedViewState {
        let visibleArticles = articleListSession.articles

        return ArticlesScreenDerivedViewState(
            visibleArticles: visibleArticles,
            sections: ArticlesDaySectionsBuilder.build(from: visibleArticles),
            listAnimationState: listAnimationState,
            navigationChrome: ArticlesScreenNavigationChromeState(
                sessionContext: articleListSession.context,
                title: navigationTitle,
                subtitle: navigationSubtitle
            ),
            toolbarActions: ArticlesScreenToolbarActionsState(
                selection: selection,
                visibleArticles: visibleArticles,
                phase: phase
            ),
            searchPlaceholder: searchPlaceholder(
                normalizedSearchText: articleListSession.context.normalizedSearchText,
                visibleArticles: visibleArticles
            ),
            customRefreshState: customRefreshState,
            refreshBanner: refreshBannerState,
            primaryLoadingState: primaryLoadingState
        )
    }

    private func searchPlaceholder(
        normalizedSearchText: String,
        visibleArticles: [ArticleListItemDTO]
    ) -> ArticlesScreenPlaceholderState? {
        guard emptyContentKind == .searchResults else {
            return nil
        }

        guard normalizedSearchText.isEmpty == false else {
            return nil
        }

        guard phase == .loaded || phase == .empty else {
            return nil
        }

        guard visibleArticles.isEmpty else {
            return nil
        }

        return ArticlesScreenPlaceholderState(
            title: ReadingLocalization.noSearchResultsTitle,
            systemImage: "magnifyingglass",
            description: ReadingLocalization.noSearchResultsDescription(query: normalizedSearchText)
        )
    }

    private var refreshBannerState: ArticlesScreenRefreshBannerState? {
        guard let refreshFeedback else {
            return nil
        }

        return ArticlesScreenRefreshBannerState(
            style: .failed,
            title: ReadingLocalization.refreshFailedTitle,
            message: refreshFeedback.message
        )
    }

    private var primaryLoadingState: ArticlesScreenPrimaryLoadingState? {
        guard showsPrimaryLoadingIndicator else {
            return nil
        }

        return ArticlesScreenPrimaryLoadingState(title: ReadingLocalization.loadingArticlesTitle)
    }
}
