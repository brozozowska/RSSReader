import Foundation

enum ArticleRowMutation: Equatable {
    case update(ArticleListItemDTO)
    case remove
}

enum ArticlesScreenMutationReducer {
    static func articleListFilter(
        selection: SidebarSelection?,
        sourcesFilter: SourcesFilter
    ) -> ArticleListFilter {
        switch selection {
        case .unread:
            .unread
        case .starred:
            .starred
        case .inbox, .folder, .feed, .none:
            SourcesFilterArticleListFilterResolver.resolve(for: sourcesFilter)
        }
    }

    static func reduceAfterMarkAllAsRead(
        visibleArticles: [ArticleListItemDTO],
        allArticles: [ArticleListItemDTO],
        filter: ArticleListFilter
    ) -> [ArticleListItemDTO] {
        let visibleArticleIDs = Set(visibleArticles.map(\.id))

        guard filter != .unread else {
            return allArticles.filter { visibleArticleIDs.contains($0.id) == false }
        }

        return allArticles.map { article in
            guard visibleArticleIDs.contains(article.id) else {
                return article
            }

            return article.updating(
                isRead: true,
                isStarred: article.isStarred
            )
        }
    }

    static func mutationAfterToggleReadStatus(
        article: ArticleListItemDTO,
        filter: ArticleListFilter
    ) -> ArticleRowMutation {
        let updatedIsRead = article.isRead == false

        if filter == .unread && updatedIsRead {
            return .remove
        }

        return .update(
            article.updating(
                isRead: updatedIsRead,
                isStarred: article.isStarred
            )
        )
    }

    static func mutationAfterToggleStarred(
        article: ArticleListItemDTO,
        filter: ArticleListFilter
    ) -> ArticleRowMutation {
        let updatedIsStarred = article.isStarred == false

        if filter == .starred && updatedIsStarred == false {
            return .remove
        }

        return .update(
            article.updating(
                isRead: article.isRead,
                isStarred: updatedIsStarred
            )
        )
    }

    static func apply(
        _ mutation: ArticleRowMutation,
        articleID: UUID,
        allArticles: [ArticleListItemDTO]
    ) -> [ArticleListItemDTO] {
        switch mutation {
        case .update(let updatedArticle):
            allArticles.map { article in
                article.id == articleID ? updatedArticle : article
            }
        case .remove:
            allArticles.filter { $0.id != articleID }
        }
    }
}

enum SourcesFilterArticleListFilterResolver {
    static func resolve(for sourcesFilter: SourcesFilter) -> ArticleListFilter {
        switch sourcesFilter {
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
            publishedAt: publishedAt,
            fetchedAt: fetchedAt,
            isRead: isRead,
            isStarred: isStarred,
            isHidden: isHidden
        )
    }
}
