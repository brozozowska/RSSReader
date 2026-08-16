import Foundation

struct ArticleSearchRequest: Sendable, Equatable {
    struct Cursor: Sendable, Equatable {
        let repositoryCursor: ArticleQueryCursor

        init(repositoryCursor: ArticleQueryCursor) {
            self.repositoryCursor = repositoryCursor
        }
    }

    enum EmptyQueryBehavior: Sendable, Equatable {
        case returnsCurrentScope
        case returnsEmpty
    }

    enum ScopeMetricLoadingPolicy: Sendable, Equatable {
        case none
        case baseScope
    }

    let selection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let normalizedQuery: String
    let sortMode: ArticleSortMode
    let limit: Int
    let cursor: Cursor?
    let emptyQueryBehavior: EmptyQueryBehavior
    let requiresUnread: Bool
    let scopeMetricLoadingPolicy: ScopeMetricLoadingPolicy

    init(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        query: String,
        sortMode: ArticleSortMode,
        limit: Int = ArticleQueryPaginationPolicy.defaultPageSize,
        cursor: Cursor? = nil,
        emptyQueryBehavior: EmptyQueryBehavior = .returnsCurrentScope,
        requiresUnread: Bool = false,
        scopeMetricLoadingPolicy: ScopeMetricLoadingPolicy = .none
    ) {
        self.selection = selection
        self.sidebarArticleFilter = sidebarArticleFilter
        self.normalizedQuery = ArticleSearchScope.normalizedSearchText(query)
        self.sortMode = sortMode
        self.limit = limit
        self.cursor = cursor
        self.emptyQueryBehavior = emptyQueryBehavior
        self.requiresUnread = requiresUnread
        self.scopeMetricLoadingPolicy = scopeMetricLoadingPolicy
    }

    var listFilter: ArticleListFilter {
        ArticleSearchScope.listFilter(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
    }

    var shouldReturnEmptyForBlankQuery: Bool {
        normalizedQuery.isEmpty && emptyQueryBehavior == .returnsEmpty
    }
}
