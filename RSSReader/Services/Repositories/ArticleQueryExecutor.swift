import Foundation
import SwiftData

// Read-only execution; predicates and bounded overlay materialization stay together.
@MainActor
struct SwiftDataArticleQueryExecutor: SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder
    private let articleStateSnapshotFetcher: SwiftDataArticleStateSnapshotFetcher
    private let queryCancellationCheck: ArticleQueryCancellationCheck

    init(
        modelContext: ModelContext,
        persistenceOperationRecorder: @escaping SwiftDataRepositoryOperationRecorder,
        queryBatchSize: Int,
        articleStateQueryBatchProbe: ArticleStateQueryBatchProbe?,
        queryCancellationCheck: @escaping ArticleQueryCancellationCheck
    ) {
        precondition(queryBatchSize > 0)
        self.modelContext = modelContext
        self.persistenceOperationRecorder = persistenceOperationRecorder
        self.queryCancellationCheck = queryCancellationCheck
        self.articleStateSnapshotFetcher = SwiftDataArticleStateSnapshotFetcher(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder,
            batchSize: queryBatchSize,
            batchProbe: articleStateQueryBatchProbe
        )
    }

    func fetchArticle(id: UUID) throws -> Article? {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.id == id
            }
        )
        return try fetchFirst(descriptor)
    }

    func fetchArticles(ids: [UUID]) throws -> [Article] {
        guard ids.isEmpty == false else { return [] }
        let uniqueIDs = Array(Set(ids))
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                uniqueIDs.contains(article.id)
            }
        )
        return try performFetch(descriptor)
    }

    func containsArticle(feedID: UUID, externalID: String) throws -> Bool {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID && article.externalID == externalID
            }
        )
        return try performFetchCount(descriptor) > 0
    }

    func fetchArticles(feedID: UUID) throws -> [Article] {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID
            }
        )
        return try performFetch(descriptor)
    }

    func fetchArticleQueryRecordScanBatch(
        matching criteria: ArticleQueryCriteria,
        cursor: ArticleQueryCursor?,
        limit: Int
    ) throws -> ArticleQueryRecordScanBatch {
        precondition(limit > 0)

        let articles = try fetchArticleQueryCandidates(
            matching: criteria,
            cursor: cursor,
            limit: limit
        )
        guard articles.isEmpty == false else {
            return ArticleQueryRecordScanBatch(
                records: [],
                nextCursor: nil,
                scannedCandidateCount: 0
            )
        }

        let materialization = try materializeArticleQueryRecords(
            from: articles,
            matching: criteria
        )
        return ArticleQueryRecordScanBatch(
            records: materialization.records,
            nextCursor: articles.count == limit ? materialization.nextCursor : nil,
            scannedCandidateCount: articles.count
        )
    }

    private func fetchArticleQueryCandidates(
        matching criteria: ArticleQueryCriteria,
        cursor: ArticleQueryCursor?,
        limit: Int
    ) throws -> [Article] {
        let matchesInbox: Bool
        let matchesFolder: Bool
        let matchesFeed: Bool
        let folderName: String
        let feedID: UUID
        switch criteria.scope {
        case .inbox:
            matchesInbox = true
            matchesFolder = false
            matchesFeed = false
            folderName = ""
            feedID = UUID()
        case .folder(let scopedFolderName):
            matchesInbox = false
            matchesFolder = true
            matchesFeed = false
            folderName = scopedFolderName
            feedID = UUID()
        case .feed(let scopedFeedID):
            matchesInbox = false
            matchesFolder = false
            matchesFeed = true
            folderName = ""
            feedID = scopedFeedID
        }

        let includesCurrent = criteria.archived != .isTrue
        let includesArchived = criteria.archived != .isFalse
        var fetchDescriptor: FetchDescriptor<Article>
        if let cursor {
            let cursorSortDate = cursor.sortDate
            let cursorArticleID = cursor.articleID
            switch (criteria.scope, criteria.sortMode) {
            case (.inbox, .publishedAtDescending):
                let predicate = #Predicate<Article> { article in
                    (
                        (includesCurrent && article.archivedAt == nil)
                            || (includesArchived && article.archivedAt != nil)
                    )
                        && (
                            article.querySortDate < cursorSortDate
                                || (
                                    article.querySortDate == cursorSortDate
                                        && article.id < cursorArticleID
                                )
                        )
                }
                fetchDescriptor = FetchDescriptor(
                    predicate: predicate,
                    sortBy: sortDescriptors(for: criteria.sortMode)
                )
            case (.inbox, .publishedAtAscending):
                let predicate = #Predicate<Article> { article in
                    (
                        (includesCurrent && article.archivedAt == nil)
                            || (includesArchived && article.archivedAt != nil)
                    )
                        && (
                            article.querySortDate > cursorSortDate
                                || (
                                    article.querySortDate == cursorSortDate
                                        && article.id > cursorArticleID
                                )
                        )
                }
                fetchDescriptor = FetchDescriptor(
                    predicate: predicate,
                    sortBy: sortDescriptors(for: criteria.sortMode)
                )
            case (.folder(let scopedFolderName), .publishedAtDescending):
                let predicate = #Predicate<Article> { article in
                    article.feedFolderName == scopedFolderName
                        && (
                            (includesCurrent && article.archivedAt == nil)
                                || (includesArchived && article.archivedAt != nil)
                        )
                        && (
                            article.querySortDate < cursorSortDate
                                || (
                                    article.querySortDate == cursorSortDate
                                        && article.id < cursorArticleID
                                )
                        )
                }
                fetchDescriptor = FetchDescriptor(
                    predicate: predicate,
                    sortBy: sortDescriptors(for: criteria.sortMode)
                )
            case (.folder(let scopedFolderName), .publishedAtAscending):
                let predicate = #Predicate<Article> { article in
                    article.feedFolderName == scopedFolderName
                        && (
                            (includesCurrent && article.archivedAt == nil)
                                || (includesArchived && article.archivedAt != nil)
                        )
                        && (
                            article.querySortDate > cursorSortDate
                                || (
                                    article.querySortDate == cursorSortDate
                                        && article.id > cursorArticleID
                                )
                        )
                }
                fetchDescriptor = FetchDescriptor(
                    predicate: predicate,
                    sortBy: sortDescriptors(for: criteria.sortMode)
                )
            case (.feed(let scopedFeedID), .publishedAtDescending):
                let predicate = #Predicate<Article> { article in
                    article.feedID == scopedFeedID
                        && (
                            (includesCurrent && article.archivedAt == nil)
                                || (includesArchived && article.archivedAt != nil)
                        )
                        && (
                            article.querySortDate < cursorSortDate
                                || (
                                    article.querySortDate == cursorSortDate
                                        && article.id < cursorArticleID
                                )
                        )
                }
                fetchDescriptor = FetchDescriptor(
                    predicate: predicate,
                    sortBy: sortDescriptors(for: criteria.sortMode)
                )
            case (.feed(let scopedFeedID), .publishedAtAscending):
                let predicate = #Predicate<Article> { article in
                    article.feedID == scopedFeedID
                        && (
                            (includesCurrent && article.archivedAt == nil)
                                || (includesArchived && article.archivedAt != nil)
                        )
                        && (
                            article.querySortDate > cursorSortDate
                                || (
                                    article.querySortDate == cursorSortDate
                                        && article.id > cursorArticleID
                                )
                        )
                }
                fetchDescriptor = FetchDescriptor(
                    predicate: predicate,
                    sortBy: sortDescriptors(for: criteria.sortMode)
                )
            }
        } else {
            let predicate = #Predicate<Article> { article in
                (
                    matchesInbox
                        || (matchesFolder && article.feedFolderName == folderName)
                        || (matchesFeed && article.feedID == feedID)
                )
                    && (
                        (includesCurrent && article.archivedAt == nil)
                            || (includesArchived && article.archivedAt != nil)
                    )
            }
            fetchDescriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: sortDescriptors(for: criteria.sortMode)
            )
        }
        fetchDescriptor.fetchLimit = limit
        return try performFetch(fetchDescriptor)
    }

    private func materializeArticleQueryRecords(
        from articles: [Article],
        matching criteria: ArticleQueryCriteria
    ) throws -> (
        records: [ArticleQueryRecord],
        nextCursor: ArticleQueryCursor?
    ) {
        let statesByCompositeKey = try articleStateSnapshotFetcher.fetchSnapshots(for: articles)
        var records: [ArticleQueryRecord] = []
        records.reserveCapacity(articles.count)

        for article in articles {
            try queryCancellationCheck()
            let state = statesByCompositeKey[articleCompositeKey(
                feedID: article.feedID,
                articleExternalID: article.externalID
            )]
            guard matchesStateCriteria(state, criteria: criteria) else { continue }
            records.append(
                ArticleQueryRecord(
                    article: article,
                    state: state,
                    continuationCursor: queryCursor(for: article)
                )
            )
        }

        return (records, articles.last.map { queryCursor(for: $0) })
    }

    func hasArchivedArticles() throws -> Bool {
        let descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.archivedAt != nil
            }
        )
        return try performFetchCount(descriptor) > 0
    }

    func fetchArchivedRetentionBatch(
        feedID: UUID,
        offset: Int,
        limit: Int
    ) throws -> [Article] {
        precondition(offset >= 0)
        precondition(limit > 0)

        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate<Article> { article in
                article.feedID == feedID && article.archivedAt != nil
            },
            sortBy: retentionBatchSortDescriptors
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try performFetch(descriptor)
    }

    private func matchesStateCriteria(
        _ state: ArticleUserStateSnapshot?,
        criteria: ArticleQueryCriteria
    ) -> Bool {
        criteria.hidden.matches(state?.isHidden ?? false)
            && criteria.read.matches(state?.isRead ?? false)
            && criteria.starred.matches(state?.isStarred ?? false)
    }

    private func sortDescriptors(for sortMode: ArticleSortMode) -> [SortDescriptor<Article>] {
        switch sortMode {
        case .publishedAtDescending:
            [
                SortDescriptor(\Article.querySortDate, order: .reverse),
                SortDescriptor(\Article.id, order: .reverse)
            ]
        case .publishedAtAscending:
            [
                SortDescriptor(\Article.querySortDate, order: .forward),
                SortDescriptor(\Article.id, order: .forward)
            ]
        }
    }

    private func queryCursor(for article: Article) -> ArticleQueryCursor {
        ArticleQueryCursor(
            sortDate: article.querySortDate,
            articleID: article.id
        )
    }

    private var retentionBatchSortDescriptors: [SortDescriptor<Article>] {
        [
            SortDescriptor(\Article.createdAt, order: .forward),
            SortDescriptor(\Article.id, order: .forward)
        ]
    }
}
