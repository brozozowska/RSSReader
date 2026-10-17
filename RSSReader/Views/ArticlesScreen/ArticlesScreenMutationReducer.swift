import Foundation

enum ArticleRowMutation: Equatable {
    case update(ArticleListItemDTO, membershipStatus: ArticleListEntryMembershipStatus? = nil)
    case remove
}

enum ArticlesScreenMutationReducer {
    static func articleListFilter(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) -> ArticleListFilter {
        switch selection {
        case .unread:
            .unread
        case .starred:
            .starred
        case .inbox, .folder, .feed, .none:
            SidebarArticleFilterResolver.resolve(for: sidebarArticleFilter)
        }
    }

    static func reduceAfterMarkAllAsRead(
        visibleArticles: [ArticleListItemDTO],
        allArticles: [ArticleListItemDTO],
        filter: ArticleListFilter,
        persistedStates: [ArticleUserStateSnapshot]? = nil
    ) -> [ArticleListItemDTO] {
        let visibleArticleIDs = Set(visibleArticles.map(\.id))
        let persistedReadStates = persistedStates.map { states in
            states.reduce(into: [String: Bool]()) { result, state in
                result[
                    ArticleStateIdentity.lookupKey(
                        feedID: state.feedID,
                        articleExternalID: state.articleExternalID
                    )
                ] = state.isRead
            }
        }

        func resolvedIsRead(for article: ArticleListItemDTO) -> Bool {
            guard let persistedReadStates else { return true }
            return persistedReadStates[
                ArticleStateIdentity.lookupKey(
                    feedID: article.feedID,
                    articleExternalID: article.articleExternalID
                )
            ] ?? article.isRead
        }

        guard filter != .unread else {
            return allArticles.compactMap { article in
                guard visibleArticleIDs.contains(article.id) else { return article }
                guard resolvedIsRead(for: article) else {
                    return article.updating(
                        isRead: false,
                        isStarred: article.isStarred
                    )
                }
                return nil
            }
        }

        return allArticles.map { article in
            guard visibleArticleIDs.contains(article.id) else {
                return article
            }

            return article.updating(
                isRead: resolvedIsRead(for: article),
                isStarred: article.isStarred
            )
        }
    }

    static func mutationAfterToggleReadStatus(
        article: ArticleListItemDTO,
        filter: ArticleListFilter
    ) -> ArticleRowMutation {
        mutationAfterSettingReadStatus(
            article: article,
            isRead: article.isRead == false,
            filter: filter
        )
    }

    static func mutationAfterSettingReadStatus(
        article: ArticleListItemDTO,
        isRead: Bool,
        filter: ArticleListFilter
    ) -> ArticleRowMutation {
        let updatedArticle = article.updating(
            isRead: isRead,
            isStarred: article.isStarred
        )

        if filter == .unread && isRead {
            return .update(
                updatedArticle,
                membershipStatus: .retainedAfterFilterMutation
            )
        }

        return .update(updatedArticle)
    }

    static func mutationAfterToggleStarred(
        article: ArticleListItemDTO,
        filter: ArticleListFilter
    ) -> ArticleRowMutation {
        mutationAfterSettingStarredStatus(
            article: article,
            isStarred: article.isStarred == false,
            filter: filter
        )
    }

    static func mutationAfterSettingStarredStatus(
        article: ArticleListItemDTO,
        isStarred: Bool,
        filter: ArticleListFilter
    ) -> ArticleRowMutation {
        let updatedArticle = article.updating(
            isRead: article.isRead,
            isStarred: isStarred
        )

        if filter == .starred && isStarred == false {
            return .update(
                updatedArticle,
                membershipStatus: .retainedAfterFilterMutation
            )
        }

        return .update(updatedArticle)
    }

    static func apply(
        _ mutation: ArticleRowMutation,
        articleID: UUID,
        allArticles: [ArticleListItemDTO]
    ) -> [ArticleListItemDTO] {
        switch mutation {
        case .update(let updatedArticle, _):
            allArticles.map { article in
                article.id == articleID ? updatedArticle : article
            }
        case .remove:
            allArticles.filter { $0.id != articleID }
        }
    }
}

enum SidebarArticleFilterResolver {
    static func resolve(for sidebarArticleFilter: SidebarArticleFilter) -> ArticleListFilter {
        switch sidebarArticleFilter {
        case .allItems:
            .all
        case .unread:
            .unread
        case .starred:
            .starred
        }
    }
}

extension ArticleListItemDTO {
    func updating(isRead: Bool, isStarred: Bool) -> ArticleListItemDTO {
        ArticleListItemDTO(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            articleExternalID: articleExternalID,
            title: title,
            summary: summary,
            author: author,
            effectiveDate: effectiveDate,
            archivedAt: archivedAt,
            isRead: isRead,
            isStarred: isStarred,
            isHidden: isHidden
        )
    }
}
