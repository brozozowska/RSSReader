import Foundation

@MainActor
extension ArticlesScreenController {
    func handleMarkAllAsReadAction(
        searchText: String,
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) async {
        guard shouldAskBeforeMarkingAllAsRead(dependencies: dependencies) else {
            await confirmMarkAllAsRead(
                searchText: searchText,
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter,
                dependencies: dependencies,
                isPreviewMode: isPreviewMode
            )
            return
        }

        screenState.presentMarkAllAsReadConfirmation()
    }

    func visibleArticleIDs() -> [UUID] {
        screenState
            .derivedViewState()
            .visibleArticles
            .map(\.id)
    }

    func confirmMarkAllAsRead(
        searchText: String,
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) async {
        let visibleArticles = screenState
            .derivedViewState()
            .visibleArticles
        let articleListFilter = currentArticleListFilter(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
        let shouldReloadPaginatedUnreadSession = articleListFilter == .unread
            && screenState.articleListSession.nextPageCursor != nil

        let persistedStates: [ArticleUserStateSnapshot]?
        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for mark all as read action")
                screenState.dismissConfirmation()
                return
            }

            do {
                persistedStates = try articleStateService.markAllVisibleAsRead(visibleArticles, at: .now)
            } catch {
                dependencies.logger.error("Failed to mark all visible articles as read: \(error)")
                screenState.dismissConfirmation()
                return
            }
        } else {
            persistedStates = nil
        }

        let updatedArticles = ArticlesScreenMutationReducer.reduceAfterMarkAllAsRead(
            visibleArticles: visibleArticles,
            allArticles: screenState.articles,
            filter: articleListFilter,
            persistedStates: persistedStates
        )
        screenState.applyMarkAllAsRead(
            updatedArticles,
            navigationSubtitle: ArticlesScreenSubtitleResolver.resolve(
                articles: updatedArticles,
                sidebarArticleFilter: sidebarArticleFilter,
                hasMorePages: screenState.articleListSession.nextPageCursor != nil
            ),
            emptyContentKind: ArticleSearchScope.normalizedSearchText(searchText).isEmpty
                ? .selection
                : .searchResults
        )

        guard shouldReloadPaginatedUnreadSession, isPreviewMode == false else {
            return
        }

        await load(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            searchText: searchText,
            dependencies: dependencies
        )
    }

    func toggleArticleReadStatus(
        _ article: ArticleListItemDTO,
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) {
        let requestedIsRead = article.isRead == false
        let currentSessionID = screenState.articleListSession.id
        let currentSessionContext = screenState.articleListSession.context
        guard currentSessionContext.selection == selection,
              currentSessionContext.sidebarArticleFilter == sidebarArticleFilter,
              screenState.articles.contains(where: { $0.id == article.id }) else {
            return
        }

        let resolvedIsRead: Bool

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for read toggle action")
                return
            }

            do {
                let persistedState: ArticleUserStateSnapshot
                if requestedIsRead {
                    persistedState = try articleStateService.markAsRead(
                        feedID: article.feedID,
                        articleExternalID: article.articleExternalID,
                        at: .now
                    )
                } else {
                    persistedState = try articleStateService.markAsUnread(
                        feedID: article.feedID,
                        articleExternalID: article.articleExternalID,
                        at: .now
                    )
                }
                resolvedIsRead = persistedState.isRead
            } catch {
                dependencies.logger.error("Failed to toggle article read status: \(error)")
                return
            }
        } else {
            resolvedIsRead = requestedIsRead
        }

        guard currentSessionID == screenState.articleListSession.id else { return }

        let mutation = ArticlesScreenMutationReducer.mutationAfterSettingReadStatus(
            article: article,
            isRead: resolvedIsRead,
            filter: currentArticleListFilter(
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter
            )
        )
        applyArticleRowMutation(
            mutation,
            articleID: article.id,
            sidebarArticleFilter: sidebarArticleFilter
        )
    }

    func toggleStarredState(
        for article: ArticleListItemDTO,
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        dependencies: AppDependencies,
        isPreviewMode: Bool
    ) {
        let requestedIsStarred = article.isStarred == false
        let resolvedIsStarred: Bool

        if isPreviewMode == false {
            guard let articleStateService = dependencies.articleStateService else {
                dependencies.logger.error("Article state service is unavailable for star action")
                return
            }

            do {
                let persistedState = try articleStateService.toggleStarred(
                    feedID: article.feedID,
                    articleExternalID: article.articleExternalID,
                    at: .now
                )
                resolvedIsStarred = persistedState.isStarred
            } catch {
                dependencies.logger.error("Failed to toggle starred state for article: \(error)")
                return
            }
        } else {
            resolvedIsStarred = requestedIsStarred
        }

        let mutation = ArticlesScreenMutationReducer.mutationAfterSettingStarredStatus(
            article: article,
            isStarred: resolvedIsStarred,
            filter: currentArticleListFilter(
                selection: selection,
                sidebarArticleFilter: sidebarArticleFilter
            )
        )
        applyArticleRowMutation(
            mutation,
            articleID: article.id,
            sidebarArticleFilter: sidebarArticleFilter
        )
    }

    func applyArticleRowMutation(
        _ mutation: ArticleRowMutation,
        articleID: UUID,
        sidebarArticleFilter: SidebarArticleFilter
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
                sidebarArticleFilter: sidebarArticleFilter,
                hasMorePages: screenState.articleListSession.nextPageCursor != nil
            )
        )
    }

    private func currentArticleListFilter(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) -> ArticleListFilter {
        ArticlesScreenMutationReducer.articleListFilter(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
    }

    private func shouldAskBeforeMarkingAllAsRead(dependencies: AppDependencies) -> Bool {
        guard let appSettingsService = dependencies.appSettingsService else {
            return true
        }

        do {
            return try appSettingsService.fetchSettings().askBeforeMarkingAllAsRead
        } catch {
            dependencies.logger.error("Failed to load app settings for mark-all-as-read confirmation policy: \\(error)")
            return true
        }
    }
}
