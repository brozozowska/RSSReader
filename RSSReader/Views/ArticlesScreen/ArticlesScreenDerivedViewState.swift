import Foundation

struct ArticlesScreenDerivedViewState {
    let visibleArticles: [ArticleListItemDTO]
    let sections: [ArticlesDaySection]
    let toolbarActions: ArticlesScreenToolbarActionsState
    let searchPlaceholder: ArticlesScreenPlaceholderState?
    let refreshBanner: ArticlesScreenRefreshBannerState?
    let primaryLoadingState: ArticlesScreenPrimaryLoadingState?
}

extension ArticlesScreenState {
    func derivedViewState(searchText: String) -> ArticlesScreenDerivedViewState {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleArticles = filteredArticles(matching: normalizedSearchText)

        return ArticlesScreenDerivedViewState(
            visibleArticles: visibleArticles,
            sections: ArticlesDaySectionsBuilder.build(from: visibleArticles),
            toolbarActions: ArticlesScreenToolbarActionsState(
                selection: selection,
                visibleArticles: visibleArticles,
                phase: phase
            ),
            searchPlaceholder: searchPlaceholder(
                normalizedSearchText: normalizedSearchText,
                visibleArticles: visibleArticles
            ),
            refreshBanner: refreshBannerState,
            primaryLoadingState: primaryLoadingState
        )
    }

    private func filteredArticles(matching normalizedSearchText: String) -> [ArticleListItemDTO] {
        guard normalizedSearchText.isEmpty == false else {
            return articles
        }

        return articles.filter { article in
            [article.feedTitle, article.title, article.summary, article.author]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(normalizedSearchText) }
        }
    }

    private func searchPlaceholder(
        normalizedSearchText: String,
        visibleArticles: [ArticleListItemDTO]
    ) -> ArticlesScreenPlaceholderState? {
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
            title: "No Search Results",
            systemImage: "magnifyingglass",
            description: "No visible articles match \"\(normalizedSearchText)\"."
        )
    }

    private var refreshBannerState: ArticlesScreenRefreshBannerState? {
        if refreshState == .refreshing && articles.isEmpty == false {
            return ArticlesScreenRefreshBannerState(
                style: .refreshing,
                title: "Refreshing Articles",
                message: "Updating the current selection."
            )
        }

        guard let refreshFeedback else {
            return nil
        }

        return ArticlesScreenRefreshBannerState(
            style: .failed,
            title: "Refresh Failed",
            message: refreshFeedback.message
        )
    }

    private var primaryLoadingState: ArticlesScreenPrimaryLoadingState? {
        guard showsPrimaryLoadingIndicator else {
            return nil
        }

        return ArticlesScreenPrimaryLoadingState(title: "Loading Articles")
    }
}
