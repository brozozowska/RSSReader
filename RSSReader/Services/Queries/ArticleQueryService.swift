import Foundation

nonisolated enum ArticleQueryPaginationPolicy {
    static let defaultPageSize = 50
    static let scanBatchSize = 64
}

struct ArticleScopeMetric: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case unread
        case starred
    }

    let kind: Kind
    let count: Int

    init(kind: Kind, count: Int) {
        self.kind = kind
        self.count = max(0, count)
    }

    func applyingMutation(
        from previousArticle: ArticleListItemDTO,
        to updatedArticle: ArticleListItemDTO
    ) -> ArticleScopeMetric {
        let previousMatches = matches(previousArticle)
        let updatedMatches = matches(updatedArticle)
        guard previousMatches != updatedMatches else { return self }

        return ArticleScopeMetric(
            kind: kind,
            count: count + (updatedMatches ? 1 : -1)
        )
    }

    func removing(_ article: ArticleListItemDTO) -> ArticleScopeMetric {
        guard matches(article) else { return self }
        return ArticleScopeMetric(kind: kind, count: count - 1)
    }

    private func matches(_ article: ArticleListItemDTO) -> Bool {
        guard article.isHidden == false else { return false }
        return switch kind {
        case .unread:
            article.isRead == false
        case .starred:
            article.isStarred
        }
    }
}

struct ArticleSearchResultSnapshot: Sendable, Equatable {
    let articles: [ArticleListItemDTO]
    let hasScopeContent: Bool
    let nextCursor: ArticleSearchRequest.Cursor?
    let scopeMetric: ArticleScopeMetric?

    init(
        articles: [ArticleListItemDTO],
        hasScopeContent: Bool,
        nextCursor: ArticleSearchRequest.Cursor? = nil,
        scopeMetric: ArticleScopeMetric? = nil
    ) {
        self.articles = articles
        self.hasScopeContent = hasScopeContent
        self.nextCursor = nextCursor
        self.scopeMetric = scopeMetric
    }
}

struct ArticleSearchScanBatchObservation: Sendable {
    let normalizedQuery: String
    let scannedCandidateCount: Int
    let stateMatchingCandidateCount: Int
    let searchMatchingCandidateCount: Int
}

typealias ArticleSearchScanBatchProbe = @MainActor (ArticleSearchScanBatchObservation) async -> Void

private struct ArticleSearchScanMatch: Sendable {
    let article: ArticleListItemDTO
    let continuationCursor: ArticleQueryCursor
}

private struct ArticleSearchProcessedScanBatch: Sendable {
    let matches: [ArticleSearchScanMatch]
    let hasScopeContent: Bool
    let nextCursor: ArticleQueryCursor?
    let observation: ArticleSearchScanBatchObservation
}

@MainActor
protocol ArticleQueryService {
    func fetchArticleSearchSnapshot(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot
    func fetchReaderArticle(id: UUID) throws -> ReaderArticleDTO?
}

@MainActor
final class DefaultArticleQueryService: ArticleQueryService {
    private let articleRepository: any ArticleRepository
    private let articleStateRepository: any ArticleStateRepository
    private let feedRepository: any FeedRepository
    private let searchScanBatchProbe: ArticleSearchScanBatchProbe?

    init(
        articleRepository: any ArticleRepository,
        articleStateRepository: any ArticleStateRepository,
        feedRepository: any FeedRepository,
        searchScanBatchProbe: ArticleSearchScanBatchProbe? = nil
    ) {
        self.articleRepository = articleRepository
        self.articleStateRepository = articleStateRepository
        self.feedRepository = feedRepository
        self.searchScanBatchProbe = searchScanBatchProbe
    }

    func fetchArticleSearchSnapshot(_ request: ArticleSearchRequest) async throws -> ArticleSearchResultSnapshot {
        try Task.checkCancellation()
        guard request.shouldReturnEmptyForBlankQuery == false else {
            return ArticleSearchResultSnapshot(articles: [], hasScopeContent: false)
        }

        guard let scope = queryScope(for: request.selection) else {
            return ArticleSearchResultSnapshot(articles: [], hasScopeContent: false)
        }

        let criteria = ArticleQueryCriteria(
            scope: scope,
            hidden: hiddenFilter(for: request.listFilter),
            archived: .any,
            read: readFilter(for: request.listFilter, requiresUnread: request.requiresUnread),
            starred: starredFilter(for: request.listFilter),
            sortMode: request.sortMode
        )
        let scopeMetric = try fetchScopeMetric(for: request, scope: scope)
        return try await fetchSearchPage(
            request,
            criteria: criteria,
            limit: request.limit,
            scopeMetric: scopeMetric
        )
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

    private func fetchSearchPage(
        _ request: ArticleSearchRequest,
        criteria: ArticleQueryCriteria,
        limit: Int,
        scopeMetric: ArticleScopeMetric?
    ) async throws -> ArticleSearchResultSnapshot {
        var repositoryCursor = request.cursor?.repositoryCursor
        var hasScopeContent = request.cursor != nil

        guard limit > 0 else {
            let batch = try processSearchScanBatch(
                request: request,
                matching: criteria,
                cursor: repositoryCursor,
                limit: 1
            )
            await searchScanBatchProbe?(batch.observation)
            return ArticleSearchResultSnapshot(
                articles: [],
                hasScopeContent: hasScopeContent || batch.hasScopeContent,
                scopeMetric: scopeMetric
            )
        }

        let targetResultCount = limit + 1
        var matchingRecords: [ArticleSearchScanMatch] = []

        while matchingRecords.count < targetResultCount {
            let batch = try processSearchScanBatch(
                request: request,
                matching: criteria,
                cursor: repositoryCursor,
                limit: ArticleQueryPaginationPolicy.scanBatchSize
            )
            hasScopeContent = hasScopeContent || batch.hasScopeContent
            matchingRecords.append(contentsOf: batch.matches.prefix(targetResultCount - matchingRecords.count))
            await searchScanBatchProbe?(batch.observation)

            guard matchingRecords.count < targetResultCount,
                  let nextCursor = batch.nextCursor else {
                break
            }
            repositoryCursor = nextCursor
            try Task.checkCancellation()
            await Task.yield()
            try Task.checkCancellation()
        }

        guard matchingRecords.count > limit else {
            return ArticleSearchResultSnapshot(
                articles: matchingRecords.map(\.article),
                hasScopeContent: hasScopeContent,
                scopeMetric: scopeMetric
            )
        }

        return ArticleSearchResultSnapshot(
            articles: matchingRecords.prefix(limit).map(\.article),
            hasScopeContent: hasScopeContent,
            nextCursor: ArticleSearchRequest.Cursor(
                repositoryCursor: matchingRecords[limit - 1].continuationCursor
            ),
            scopeMetric: scopeMetric
        )
    }

    private func fetchScopeMetric(
        for request: ArticleSearchRequest,
        scope: ArticleQueryScope
    ) throws -> ArticleScopeMetric? {
        guard request.scopeMetricLoadingPolicy == .baseScope else { return nil }
        try Task.checkCancellation()

        let kind: ArticleScopeMetric.Kind
        switch request.listFilter {
        case .all, .unread:
            kind = .unread
        case .starred:
            kind = .starred
        case .hidden:
            return nil
        }

        switch scope {
        case .feed(let feedID):
            return ArticleScopeMetric(
                kind: kind,
                count: try fetchScopeMetricCount(kind: kind, feedIDs: [feedID])
            )
        case .inbox:
            return try fetchScopeMetric(
                kind: kind,
                feedIdentityScope: .inbox
            )
        case .folder(let folderName):
            return try fetchScopeMetric(
                kind: kind,
                feedIdentityScope: .folder(folderName)
            )
        }
    }

    private func fetchScopeMetric(
        kind: ArticleScopeMetric.Kind,
        feedIdentityScope: FeedIdentityQueryScope
    ) throws -> ArticleScopeMetric {
        var offset = 0
        var totalCount = 0

        while true {
            try Task.checkCancellation()
            let feedIDs = try feedRepository.fetchFeedIDBatch(
                matching: feedIdentityScope,
                offset: offset,
                limit: FeedIdentityQueryPolicy.batchSize
            )
            guard feedIDs.isEmpty == false else { break }

            totalCount += try fetchScopeMetricCount(kind: kind, feedIDs: feedIDs)
            guard feedIDs.count == FeedIdentityQueryPolicy.batchSize else { break }
            offset += feedIDs.count
        }
        try Task.checkCancellation()
        return ArticleScopeMetric(kind: kind, count: totalCount)
    }

    private func fetchScopeMetricCount(
        kind: ArticleScopeMetric.Kind,
        feedIDs: [UUID]
    ) throws -> Int {
        let counts: [UUID: Int]
        switch kind {
        case .unread:
            counts = try articleStateRepository.fetchUnreadCounts(feedIDs: feedIDs)
        case .starred:
            counts = try articleStateRepository.fetchStarredCounts(feedIDs: feedIDs)
        }
        try Task.checkCancellation()
        return feedIDs.reduce(0) { $0 + counts[$1, default: 0] }
    }

    private func processSearchScanBatch(
        request: ArticleSearchRequest,
        matching criteria: ArticleQueryCriteria,
        cursor: ArticleQueryCursor?,
        limit: Int
    ) throws -> ArticleSearchProcessedScanBatch {
        let searchScope = ArticleSearchScope(
            normalizedQuery: request.normalizedQuery,
            selection: request.selection,
            sidebarArticleFilter: request.sidebarArticleFilter
        )
        let batch = try articleRepository.fetchArticleQueryRecordScanBatch(
            matching: criteria,
            cursor: cursor,
            limit: limit
        )
        var matches: [ArticleSearchScanMatch] = []
        matches.reserveCapacity(batch.records.count)

        for record in batch.records {
            try Task.checkCancellation()
            let candidate = ArticleSearchCandidateDTO(
                article: record.article,
                state: record.state
            )
            guard matchesSearch(
                candidate,
                request: request,
                searchScope: searchScope
            ) else { continue }
            matches.append(
                ArticleSearchScanMatch(
                    article: candidate.listItem,
                    continuationCursor: record.continuationCursor
                )
            )
        }

        return ArticleSearchProcessedScanBatch(
            matches: matches,
            hasScopeContent: batch.records.isEmpty == false,
            nextCursor: batch.nextCursor,
            observation: ArticleSearchScanBatchObservation(
                normalizedQuery: request.normalizedQuery,
                scannedCandidateCount: batch.scannedCandidateCount,
                stateMatchingCandidateCount: batch.records.count,
                searchMatchingCandidateCount: matches.count
            )
        )
    }

    private func matchesSearch(
        _ candidate: ArticleSearchCandidateDTO,
        request: ArticleSearchRequest,
        searchScope: ArticleSearchScope
    ) -> Bool {
        guard request.requiresUnread == false || candidate.listItem.isRead == false else {
            return false
        }

        return searchScope.contains(candidate)
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

    private func readFilter(
        for filter: ArticleListFilter,
        requiresUnread: Bool
    ) -> ArticleQueryBooleanFilter {
        filter == .unread || requiresUnread ? .isFalse : .any
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
