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

        return Self.searchableValues(for: article)
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

    private static func searchableValues(for article: ArticleListItemDTO) -> [String] {
        [
            article.title,
            article.summary,
            article.contentText,
            plainTextFallback(fromHTML: article.contentHTML),
            article.author,
            article.feedTitle
        ]
        .compactMap { $0?.nilIfBlank }
    }

    private static func plainTextFallback(fromHTML html: String?) -> String? {
        guard let html = html?.nilIfBlank else {
            return nil
        }

        return html
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?i)</?(p|div|section|article|blockquote|ul|ol|li|h[1-6]|pre|figure|figcaption|table|tbody|thead|tr|td|th)\b[^>]*>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .decodingBasicHTMLEntities()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    func decodingBasicHTMLEntities() -> String {
        replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
