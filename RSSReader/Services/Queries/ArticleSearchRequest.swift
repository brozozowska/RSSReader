import Foundation

struct ArticleSearchRequest: Sendable, Equatable {
    enum EmptyQueryBehavior: Sendable, Equatable {
        case returnsCurrentScope
        case returnsEmpty
    }

    let selection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let normalizedQuery: String
    let sortMode: ArticleSortMode
    let limit: Int?
    let emptyQueryBehavior: EmptyQueryBehavior

    init(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter,
        query: String,
        sortMode: ArticleSortMode,
        limit: Int? = nil,
        emptyQueryBehavior: EmptyQueryBehavior = .returnsCurrentScope
    ) {
        self.selection = selection
        self.sidebarArticleFilter = sidebarArticleFilter
        self.normalizedQuery = ArticleSearchScope.normalizedSearchText(query)
        self.sortMode = sortMode
        self.limit = limit
        self.emptyQueryBehavior = emptyQueryBehavior
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
