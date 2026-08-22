import Foundation

struct ArticleSearchCandidateDTO: Sendable, Equatable {
    let listItem: ArticleListItemDTO
    let searchableText: String

    init(listItem: ArticleListItemDTO, searchableText: String) {
        self.listItem = listItem
        self.searchableText = searchableText
    }

    init(article: Article, state: ArticleUserStateSnapshot?) {
        self.init(
            listItem: ArticleListItemDTO(article: article, state: state),
            searchableText: article.searchableText
        )
    }
}

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
        self.init(
            normalizedQuery: Self.normalizedSearchText(searchText),
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
    }

    init(
        normalizedQuery: String,
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) {
        self.selection = selection
        self.sidebarArticleFilter = sidebarArticleFilter
        self.normalizedQuery = normalizedQuery
        self.listFilter = Self.listFilter(
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
    }

    var isSearching: Bool {
        normalizedQuery.isEmpty == false
    }

    func contains(_ candidate: ArticleSearchCandidateDTO) -> Bool {
        guard Self.isVisibleInCurrentListScope(candidate.listItem, listFilter: listFilter) else {
            return false
        }

        guard isSearching else {
            return true
        }

        return [candidate.searchableText, candidate.listItem.feedTitle]
            .contains { $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    static func filteredCandidates(
        _ candidates: [ArticleSearchCandidateDTO],
        searchText: String,
        selection: SidebarSelection?,
        sidebarArticleFilter: SidebarArticleFilter
    ) -> [ArticleSearchCandidateDTO] {
        let scope = ArticleSearchScope(
            searchText: searchText,
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
        return candidates.filter { scope.contains($0) }
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
        ArticleSearchQueryNormalizationPolicy.normalize(searchText)
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
