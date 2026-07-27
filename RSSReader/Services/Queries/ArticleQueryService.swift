import Foundation

@MainActor
protocol ArticleQueryService {
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchFolderListItems(folderName: String, sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchArticleSearchResults(_ request: ArticleSearchRequest) throws -> [ArticleListItemDTO]
    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO?
}

@MainActor
final class DefaultArticleQueryService: ArticleQueryService {
    private let articleRepository: any ArticleRepository
    private let articleStateRepository: any ArticleStateRepository

    init(
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository
    ) {
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
    }

    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO] {
        try fetchArticleListItems(feedID: feedID, sortMode: sortMode, filter: .all)
    }

    func fetchArticleListItems(
        feedID: UUID,
        sortMode: ArticleSortMode,
        filter: ArticleListFilter
    ) throws -> [ArticleListItemDTO] {
        try fetchListItems(
            scope: .feed(feedID),
            sortMode: sortMode,
            filter: filter
        )
    }

    func fetchFolderListItems(
        folderName: String,
        sortMode: ArticleSortMode,
        filter: ArticleListFilter
    ) throws -> [ArticleListItemDTO] {
        try fetchListItems(
            scope: .folder(folderName),
            sortMode: sortMode,
            filter: filter
        )
    }

    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO] {
        try fetchInboxListItems(sortMode: sortMode, filter: .all)
    }

    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO] {
        try fetchListItems(
            scope: .inbox,
            sortMode: sortMode,
            filter: filter
        )
    }

    func fetchArticleSearchResults(_ request: ArticleSearchRequest) throws -> [ArticleListItemDTO] {
        guard request.shouldReturnEmptyForBlankQuery == false else {
            return []
        }

        guard let scope = queryScope(for: request.selection) else {
            return []
        }

        let listItems = try fetchListItems(
            scope: scope,
            sortMode: request.sortMode,
            filter: request.listFilter
        )
        let searchResults = ArticleSearchScope.filteredArticles(
            listItems,
            searchText: request.normalizedQuery,
            selection: request.selection,
            sidebarArticleFilter: request.sidebarArticleFilter
        )

        guard let limit = request.limit else {
            return searchResults
        }

        guard limit > 0 else {
            return []
        }

        return Array(searchResults.prefix(limit))
    }

    private func makeListItems(from articles: [Article]) throws -> [ArticleListItemDTO] {
        let stateByCompositeKey = try fetchStateByCompositeKey(for: articles)

        return articles.map { article in
            let state = stateByCompositeKey[
                ArticleStateIdentity.lookupKey(
                    feedID: article.feedID,
                    articleExternalID: article.externalID
                )
            ]
            return ArticleListItemDTO(article: article, state: state)
        }
    }

    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO? {
        guard let article = try articleRepository.fetchArticle(id: id) else { return nil }

        let stateByCompositeKey = try fetchStateByCompositeKey(for: [article])
        let state = stateByCompositeKey[
            ArticleStateIdentity.lookupKey(
                feedID: article.feedID,
                articleExternalID: article.externalID
            )
        ]
        return ReaderArticleDTO(article: article, state: state)
    }

    private func fetchStateByCompositeKey(for articles: [Article]) throws -> [String: ArticleUserStateSnapshot] {
        guard articles.isEmpty == false else { return [:] }

        return try articleStateRepository.fetchStateSnapshots(for: articles)
    }

    private func fetchListItems(
        scope: ArticleQueryScope,
        sortMode: ArticleSortMode,
        filter: ArticleListFilter
    ) throws -> [ArticleListItemDTO] {
        let criteria = ArticleQueryCriteria(
            scope: scope,
            hidden: hiddenFilter(for: filter),
            archived: .any,
            read: readFilter(for: filter),
            starred: starredFilter(for: filter),
            sortMode: sortMode
        )
        let articles = try articleRepository.fetchArticles(matching: criteria)
        return try makeListItems(from: articles)
    }

    private func queryScope(for selection: SidebarSelection?) -> ArticleQueryScope? {
        switch selection {
        case .inbox, .unread, .starred:
            .inbox
        case .folder(let folderName):
            .folder(folderName)
        case .feed(let feedID):
            .feed(feedID)
        case .none:
            nil
        }
    }

    private func hiddenFilter(for filter: ArticleListFilter) -> ArticleQueryBooleanFilter {
        filter == .hidden ? .isTrue : .isFalse
    }

    private func readFilter(for filter: ArticleListFilter) -> ArticleQueryBooleanFilter {
        filter == .unread ? .isFalse : .any
    }

    private func starredFilter(for filter: ArticleListFilter) -> ArticleQueryBooleanFilter {
        switch filter {
        case .starred:
            .isTrue
        case .all, .unread, .hidden:
            .any
        }
    }
}
