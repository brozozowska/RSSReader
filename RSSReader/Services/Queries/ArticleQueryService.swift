import Foundation

nonisolated enum ArticleQueryPaginationPolicy {
    static let scanBatchSize = 64
}

struct ArticleSearchResultSnapshot: Sendable, Equatable {
    let articles: [ArticleListItemDTO]
    let hasScopeContent: Bool
    let nextCursor: ArticleSearchRequest.Cursor?

    init(
        articles: [ArticleListItemDTO],
        hasScopeContent: Bool,
        nextCursor: ArticleSearchRequest.Cursor? = nil
    ) {
        self.articles = articles
        self.hasScopeContent = hasScopeContent
        self.nextCursor = nextCursor
    }
}

@MainActor
protocol ArticleQueryService {
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchArticleListItems(feedID: UUID, sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchFolderListItems(folderName: String, sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode) throws -> [ArticleListItemDTO]
    func fetchInboxListItems(sortMode: ArticleSortMode, filter: ArticleListFilter) throws -> [ArticleListItemDTO]
    func fetchArticleSearchSnapshot(_ request: ArticleSearchRequest) throws -> ArticleSearchResultSnapshot
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
        try fetchArticleSearchSnapshot(request).articles
    }

    func fetchArticleSearchSnapshot(_ request: ArticleSearchRequest) throws -> ArticleSearchResultSnapshot {
        guard request.shouldReturnEmptyForBlankQuery == false else {
            return ArticleSearchResultSnapshot(articles: [], hasScopeContent: false)
        }

        guard let scope = queryScope(for: request.selection) else {
            return ArticleSearchResultSnapshot(articles: [], hasScopeContent: false)
        }

        guard let limit = request.limit else {
            let listItems = try fetchListItems(
                scope: scope,
                sortMode: request.sortMode,
                filter: request.listFilter,
                requiresSearchableText: request.normalizedQuery.isEmpty == false
            )
            let searchResults = ArticleSearchScope.filteredArticles(
                listItems,
                searchText: request.normalizedQuery,
                selection: request.selection,
                sidebarArticleFilter: request.sidebarArticleFilter
            )
            return ArticleSearchResultSnapshot(
                articles: searchResults,
                hasScopeContent: listItems.isEmpty == false
            )
        }

        let criteria = ArticleQueryCriteria(
            scope: scope,
            hidden: hiddenFilter(for: request.listFilter),
            archived: .any,
            read: readFilter(for: request.listFilter),
            starred: starredFilter(for: request.listFilter),
            sortMode: request.sortMode,
            requiresSearchableText: request.normalizedQuery.isEmpty == false
        )
        return try fetchSearchPage(request, criteria: criteria, limit: limit)
    }

    private func makeListItems(from records: [ArticleQueryRecord]) -> [ArticleListItemDTO] {
        records.map { record in
            ArticleListItemDTO(article: record.article, state: record.state)
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
        filter: ArticleListFilter,
        requiresSearchableText: Bool = false
    ) throws -> [ArticleListItemDTO] {
        let criteria = ArticleQueryCriteria(
            scope: scope,
            hidden: hiddenFilter(for: filter),
            archived: .any,
            read: readFilter(for: filter),
            starred: starredFilter(for: filter),
            sortMode: sortMode,
            requiresSearchableText: requiresSearchableText
        )
        let records = try articleRepository.fetchArticleQueryRecords(matching: criteria)
        return makeListItems(from: records)
    }

    private func fetchSearchPage(
        _ request: ArticleSearchRequest,
        criteria: ArticleQueryCriteria,
        limit: Int
    ) throws -> ArticleSearchResultSnapshot {
        var repositoryOffset = request.cursor?.repositoryOffset ?? 0
        var hasScopeContent = request.cursor != nil

        guard limit > 0 else {
            let page = try articleRepository.fetchArticleQueryRecordPage(
                matching: criteria,
                offset: repositoryOffset,
                limit: 1
            )
            return ArticleSearchResultSnapshot(
                articles: [],
                hasScopeContent: hasScopeContent || page.records.isEmpty == false
            )
        }

        let targetResultCount = limit + 1
        var matchingRecords: [(article: ArticleListItemDTO, continuationOffset: Int)] = []

        while matchingRecords.count < targetResultCount {
            let page = try articleRepository.fetchArticleQueryRecordPage(
                matching: criteria,
                offset: repositoryOffset,
                limit: ArticleQueryPaginationPolicy.scanBatchSize
            )
            hasScopeContent = hasScopeContent || page.records.isEmpty == false

            for record in page.records {
                try Task.checkCancellation()
                let article = ArticleListItemDTO(article: record.article, state: record.state)
                guard matchesSearch(article, request: request) else { continue }
                matchingRecords.append((article, record.continuationOffset))
                if matchingRecords.count == targetResultCount {
                    break
                }
            }

            guard matchingRecords.count < targetResultCount,
                  let nextOffset = page.nextOffset else {
                break
            }
            repositoryOffset = nextOffset
        }

        guard matchingRecords.count > limit else {
            return ArticleSearchResultSnapshot(
                articles: matchingRecords.map(\.article),
                hasScopeContent: hasScopeContent
            )
        }

        return ArticleSearchResultSnapshot(
            articles: matchingRecords.prefix(limit).map(\.article),
            hasScopeContent: hasScopeContent,
            nextCursor: ArticleSearchRequest.Cursor(
                repositoryOffset: matchingRecords[limit - 1].continuationOffset
            )
        )
    }

    private func matchesSearch(
        _ article: ArticleListItemDTO,
        request: ArticleSearchRequest
    ) -> Bool {
        ArticleSearchScope.filteredArticles(
            [article],
            searchText: request.normalizedQuery,
            selection: request.selection,
            sidebarArticleFilter: request.sidebarArticleFilter
        ).isEmpty == false
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
