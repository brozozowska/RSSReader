import Foundation

struct ArticleSearchScope: Sendable, Equatable {
    let selection: SidebarSelection?
    let sidebarArticleFilter: SidebarArticleFilter
    let normalizedQuery: String
    let listFilter: ArticleListFilter

    init(
        searchText: String,
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) {
        self.selection = selection
        self.sidebarArticleFilter = sidebarArticleFilter
        self.normalizedQuery = Self.normalizedSearchText(searchText)
        self.listFilter = Self.listFilter(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
    }

    var isSearching: Bool {
        normalizedQuery.isEmpty == false
    }

    func contains(_ article: ArticleListItemDTO) -> Bool {
        guard Self.isVisibleInCurrentListScope(article, listFilter: listFilter) else {
            return false
        }

        guard isSearching else {
            return true
        }

        return [article.searchableText, article.feedTitle]
            .contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    static func filteredArticles(
        _ articles: [ArticleListItemDTO],
        searchText: String,
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) -> [ArticleListItemDTO] {
        let scope = ArticleSearchScope(
            searchText: searchText,
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
        return articles.filter { scope.contains($0) }
    }

    static func listFilter(
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) -> ArticleListFilter {
        switch selection {
        case .unread:
            .unread
        case .starred:
            .starred
        case .inbox, .folder, .feed, .none:
            listFilter(sidebarArticleFilter: sidebarArticleFilter)
        }
    }

    static func normalizedSearchText(_ searchText: String) -> String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func listFilter(sidebarArticleFilter: SidebarArticleFilter) -> ArticleListFilter {
        switch sidebarArticleFilter {
        case .allItems:
            .all
        case .unread:
            .unread
        case .starred:
            .starred
        }
    }

    private static func isVisibleInCurrentListScope(
        _ article: ArticleListItemDTO,
        listFilter: ArticleListFilter
    ) -> Bool {
        switch listFilter {
        case .all:
            return article.isHidden == false
        case .unread:
            return article.isHidden == false && article.isRead == false
        case .starred:
            return article.isHidden == false && article.isStarred
        case .hidden:
            return article.isHidden
        }
    }

}
