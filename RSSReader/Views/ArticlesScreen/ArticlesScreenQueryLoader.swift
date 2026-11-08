import Foundation

/// Shared request construction keeps primary and continuation queries on the same bounded contract.
@MainActor
struct ArticlesScreenQueryLoader {
    let pageSize: Int
    let queryOperation: ArticlesScreenSearchQueryOperation

    func load(
        for selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        normalizedSearchText: String,
        sortMode: ArticleSortMode,
        loadsScopeMetric: Bool,
        articleQueryService: any ArticleQueryService,
        cursor: ArticleSearchRequest.Cursor? = nil
    ) async throws -> ArticleListLoadResult {
        let request = ArticleSearchRequest(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter,
            query: normalizedSearchText,
            sortMode: sortMode,
            limit: pageSize,
            cursor: cursor,
            scopeMetricLoadingPolicy: loadsScopeMetric ? .baseScope : .none
        )
        let snapshot = try await queryOperation(request, articleQueryService)

        return ArticleListLoadResult(
            articles: snapshot.articles,
            emptyContentKind: emptyContentKind(snapshot: snapshot, request: request),
            nextPageCursor: snapshot.nextCursor,
            scopeMetric: snapshot.scopeMetric
        )
    }

    private func emptyContentKind(
        snapshot: ArticleSearchResultSnapshot,
        request: ArticleSearchRequest
    ) -> ArticlesScreenEmptyContentKind {
        guard snapshot.articles.isEmpty,
              request.normalizedQuery.isEmpty == false else {
            return .selection
        }

        return snapshot.hasScopeContent ? .searchResults : .selection
    }

}

struct ArticleListLoadResult {
    let articles: [ArticleListItemDTO]
    let emptyContentKind: ArticlesScreenEmptyContentKind
    let nextPageCursor: ArticleSearchRequest.Cursor?
    let scopeMetric: ArticleScopeMetric?
}
