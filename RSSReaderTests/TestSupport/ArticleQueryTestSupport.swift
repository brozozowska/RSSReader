import Foundation
@testable import RSSReader

@MainActor
func fetchArticleTestPage(
    from queryService: any ArticleQueryService,
    selection: SidebarSelection,
    filter: ArticleListFilter,
    sortMode: ArticleSortMode = .publishedAtDescending,
    limit: Int = ArticleQueryPaginationPolicy.defaultPageSize
) async throws -> [ArticleListItemDTO] {
    let sidebarArticleFilter: SidebarArticleFilter
    switch filter {
    case .all:
        sidebarArticleFilter = .allItems
    case .unread:
        sidebarArticleFilter = .unread
    case .starred:
        sidebarArticleFilter = .starred
    case .hidden:
        preconditionFailure("Hidden article queries must exercise repository criteria directly")
    }

    return try await queryService.fetchArticleSearchSnapshot(
        ArticleSearchRequest(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            query: "",
            sortMode: sortMode,
            limit: limit
        )
    ).articles
}
