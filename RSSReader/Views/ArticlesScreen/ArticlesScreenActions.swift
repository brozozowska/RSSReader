import Foundation

@MainActor
extension ArticlesScreenController {
    func visibleArticleIDs(searchText: String) -> [UUID] {
        screenState
            .derivedViewState(searchText: searchText)
            .visibleArticles
            .map(\.id)
    }

    func confirmMarkAllAsRead(
        searchText: String,
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) {
        let visibleArticles = screenState
            .derivedViewState(searchText: searchText)
            .visibleArticles

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for mark all as read action")
                screenState.dismissConfirmation()
                return
            }

            do {
                _ = try articleStateService.markAllVisibleAsRead(visibleArticles, at: .now)
            } catch {
                dependencies.logger.error("Failed to mark all visible articles as read: \(error)")
                screenState.dismissConfirmation()
                return
            }
        }

        let updatedArticles = ArticlesScreenMutationReducer.reduceAfterMarkAllAsRead(
            visibleArticles: visibleArticles,
            allArticles: screenState.articles,
            filter: currentArticleListFilter(
                selection: selection,
                sourcesFilter: sourcesFilter
            )
        )
        screenState.applyMarkAllAsRead(
            updatedArticles,
            navigationSubtitle: ArticlesScreenSubtitleResolver.resolve(
                articles: updatedArticles,
                sourcesFilter: sourcesFilter
            )
        )
    }

    func toggleArticleReadStatus(
        _ article: ArticleListItemDTO,
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) {
        let newIsRead = article.isRead == false

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for read toggle action")
                return
            }

            do {
                if newIsRead {
                    _ = try articleStateService.markAsRead(
                        feedID: article.feedID,
                        articleExternalID: article.articleExternalID,
                        at: .now
                    )
                } else {
                    _ = try articleStateService.markAsUnread(
                        feedID: article.feedID,
                        articleExternalID: article.articleExternalID,
                        at: .now
                    )
                }
            } catch {
                dependencies.logger.error("Failed to toggle article read status: \(error)")
                return
            }
        }

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleReadStatus(
            article: article,
            filter: currentArticleListFilter(
                selection: selection,
                sourcesFilter: sourcesFilter
            )
        )
        applyArticleRowMutation(mutation, articleID: article.id, sourcesFilter: sourcesFilter)
    }

    func toggleStarredState(
        for article: ArticleListItemDTO,
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter,
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) {
        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for star action")
                return
            }

            do {
                _ = try articleStateService.toggleStarred(
                    feedID: article.feedID,
                    articleExternalID: article.articleExternalID,
                    at: .now
                )
            } catch {
                dependencies.logger.error("Failed to toggle starred state for article: \(error)")
                return
            }
        }

        let mutation = ArticlesScreenMutationReducer.mutationAfterToggleStarred(
            article: article,
            filter: currentArticleListFilter(
                selection: selection,
                sourcesFilter: sourcesFilter
            )
        )
        applyArticleRowMutation(mutation, articleID: article.id, sourcesFilter: sourcesFilter)
    }

    private func applyArticleRowMutation(
        _ mutation: ArticleRowMutation,
        articleID: UUID,
        sourcesFilter: SourcesFilter
    ) {
        let updatedArticles = ArticlesScreenMutationReducer.apply(
            mutation,
            articleID: articleID,
            allArticles: screenState.articles
        )
        screenState.applyArticleRowMutation(
            articleID: articleID,
            mutation: mutation,
            navigationSubtitle: ArticlesScreenSubtitleResolver.resolve(
                articles: updatedArticles,
                sourcesFilter: sourcesFilter
            )
        )
    }

    private func currentArticleListFilter(
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter
    ) -> ArticleListFilter {
        ArticlesScreenMutationReducer.articleListFilter(
            selection: selection,
            sourcesFilter: sourcesFilter
        )
    }
}
