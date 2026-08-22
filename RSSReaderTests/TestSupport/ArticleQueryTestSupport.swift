import Foundation
@testable import RSSReader

func makeArticleSearchCursor(seed: Int) -> ArticleSearchRequest.Cursor {
    ArticleSearchRequest.Cursor(
        repositoryCursor: ArticleQueryCursor(
            sortDate: Date(timeIntervalSince1970: TimeInterval(seed)),
            articleID: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(seed)")!
        )
    )
}

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
