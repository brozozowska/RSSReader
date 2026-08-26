import Foundation
import SwiftData

enum ArticleQueryScope: Equatable, Sendable {
    case inbox
    case folder(String)
    case feed(UUID)
}

enum ArticleQueryBooleanFilter: Equatable, Sendable {
    case any
    case isFalse
    case isTrue

    func matches(_ value: Bool) -> Bool {
        switch self {
        case .any:
            true
        case .isFalse:
            value == false
        case .isTrue:
            value
        }
    }
}

struct ArticleQueryCriteria: Equatable, Sendable {
    let scope: ArticleQueryScope
    let hidden: ArticleQueryBooleanFilter
    let archived: ArticleQueryBooleanFilter
    let read: ArticleQueryBooleanFilter
    let starred: ArticleQueryBooleanFilter
    let sortMode: ArticleSortMode

    init(
        scope: ArticleQueryScope,
        hidden: ArticleQueryBooleanFilter = .any,
        archived: ArticleQueryBooleanFilter = .any,
        read: ArticleQueryBooleanFilter = .any,
        starred: ArticleQueryBooleanFilter = .any,
        sortMode: ArticleSortMode
    ) {
        self.scope = scope
        self.hidden = hidden
        self.archived = archived
        self.read = read
        self.starred = starred
        self.sortMode = sortMode
    }
}

struct ArticleQueryCursor: Equatable, Sendable {
    let sortDate: Date
    let articleID: UUID
}

struct ArticleQueryRecord {
    let article: Article
    let state: ArticleUserStateSnapshot?
    let continuationCursor: ArticleQueryCursor
}

struct ArticleQueryRecordScanBatch {
    let records: [ArticleQueryRecord]
    let nextCursor: ArticleQueryCursor?
    let scannedCandidateCount: Int
}

struct ArticleFeedSnapshotReconciliationResult {
    let projectionUpdateCount: Int
    let reconciledArticleCount: Int
    let upsertedArticleCount: Int
}

enum ArticleFeedSnapshotReconciliationStage: CaseIterable, Hashable, Sendable {
    case incomingIdentityMaterialization
    case snapshotCanonicalization
    case articleStateMaterialization
    case articleStateCanonicalization
    case articleStateDuplicateDeletion
    case projectionAndArchive
    case duplicateDeletion
    case payloadApply
}

struct ArticleFeedSnapshotReconciliationProgress: Sendable {
    let stage: ArticleFeedSnapshotReconciliationStage
    let processedItemCount: Int
    let totalItemCount: Int
}

typealias ArticleFeedSnapshotReconciliationProgressProbe = @MainActor (
    ArticleFeedSnapshotReconciliationProgress
) -> Void
typealias ArticleQueryCancellationCheck = @MainActor () throws -> Void

enum ArticleFeedSnapshotCancellationCheckpoint: Equatable, Sendable {
    case beforeSnapshot
    case during(ArticleFeedSnapshotReconciliationStage)
    case beforeUpsert
    case afterUpsert
}

enum ArticleFeedSnapshotReconciliationPolicy {
    static let cancellationCheckpointInterval = 32
}

@MainActor
protocol ArticleRepository {
    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool) throws -> Int
    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool
    ) throws -> ArticleFeedSnapshotReconciliationResult
    func fetchArticle(id: UUID) throws -> Article?
    func containsArticle(feedID: UUID, externalID: String) throws -> Bool
    func fetchArticles(feedID: UUID) throws -> [Article]
    func fetchArticleQueryRecordScanBatch(
        matching criteria: ArticleQueryCriteria,
        cursor: ArticleQueryCursor?,
        limit: Int
    ) throws -> ArticleQueryRecordScanBatch
    func hasArchivedArticles() throws -> Bool
    func fetchArchivedRetentionBatch(
        feedID: UUID,
        offset: Int,
        limit: Int
    ) throws -> [Article]

    func delete(_ article: Article) throws
    func delete(_ articles: [Article], saveAfterOperation: Bool) throws
}

extension ArticleRepository {
    func refreshFeedProjection(for feed: Feed) throws -> Int {
        try refreshFeedProjection(for: feed, saveAfterOperation: true)
    }

    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        try reconcileFeedSnapshot(
            payloads,
            into: feed,
            fetchedAt: fetchedAt,
            saveAfterOperation: true
        )
    }

    func delete(_ articles: [Article]) throws {
        try delete(articles, saveAfterOperation: true)
    }
}

@MainActor
final class SwiftDataArticleRepository: ArticleRepository, SwiftDataRepositoryContext {
    let modelContext: ModelContext
    let persistenceOperationRecorder: SwiftDataRepositoryOperationRecorder
    private let cancellationCheckpoint: (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void
    private let reconciliationProgressProbe: ArticleFeedSnapshotReconciliationProgressProbe?
    private let articleStateIdentityRepairer: SwiftDataArticleStateIdentityRepairer
    private let articleStateSnapshotFetcher: SwiftDataArticleStateSnapshotFetcher
    private let queryCancellationCheck: ArticleQueryCancellationCheck

    init(
        modelContext: ModelContext,
        persistenceOperationRecorder: @escaping SwiftDataRepositoryOperationRecorder = { _ in },
        cancellationCheckpoint: @escaping (ArticleFeedSnapshotCancellationCheckpoint) throws -> Void = { _ in
            try Task.checkCancellation()
        },
        reconciliationProgressProbe: ArticleFeedSnapshotReconciliationProgressProbe? = nil,
        queryBatchSize: Int = ArticleStateQueryPolicy.batchSize,
        articleStateQueryBatchProbe: ArticleStateQueryBatchProbe? = nil,
        queryCancellationCheck: @escaping ArticleQueryCancellationCheck = {
            try Task.checkCancellation()
        }
    ) {
        precondition(queryBatchSize > 0)
        self.modelContext = modelContext
        self.persistenceOperationRecorder = persistenceOperationRecorder
        self.cancellationCheckpoint = cancellationCheckpoint
        self.reconciliationProgressProbe = reconciliationProgressProbe
        self.queryCancellationCheck = queryCancellationCheck
        self.articleStateIdentityRepairer = SwiftDataArticleStateIdentityRepairer(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder
        )
        self.articleStateSnapshotFetcher = SwiftDataArticleStateSnapshotFetcher(
            modelContext: modelContext,
            persistenceOperationRecorder: persistenceOperationRecorder,
            batchSize: queryBatchSize,
            batchProbe: articleStateQueryBatchProbe
        )
    }

    func refreshFeedProjection(for feed: Feed, saveAfterOperation: Bool = true) throws -> Int {
        let articles = try fetchArticles(feedID: feed.id)
        let updatedCount = articles.reduce(into: 0) { updatedCount, article in
            updatedCount += updateFeedProjection(of: article, from: feed)
        }

        if updatedCount > 0, saveAfterOperation {
            try saveIfNeeded()
        }
        return updatedCount
    }

    func reconcileFeedSnapshot(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        fetchedAt: Date,
        saveAfterOperation: Bool = true
    ) throws -> ArticleFeedSnapshotReconciliationResult {
        try cancellationCheckpoint(.beforeSnapshot)
        let incomingIdentities = try incomingIdentitySet(from: payloads)
        let existingArticles = try fetchArticles(feedID: feed.id)
        let canonicalSnapshot = try canonicalArticleSnapshot(
            from: existingArticles
        )
        try articleStateIdentityRepairer.stageRepairs(
            feedID: feed.id,
            normalizedIdentities: canonicalSnapshot.duplicateIdentities,
            cancellationCheckpoint: cancellationCheckpoint,
            progressProbe: reconciliationProgressProbe
        )
        var articlesByIdentity = canonicalSnapshot.articlesByIdentity
        var projectionUpdateCount = 0
        var reconciledArticleCount = 0

        recordReconciliationProgress(
            stage: .projectionAndArchive,
            processedItemCount: 0,
            totalItemCount: articlesByIdentity.count
        )
        for (index, element) in articlesByIdentity.enumerated() {
            try checkReconciliationCancellation(
                stage: .projectionAndArchive,
                beforeItemAt: index
            )
            let (identity, article) = element
            if canonicalSnapshot.duplicateIdentities.contains(identity),
               article.externalID != identity {
                article.externalID = identity
                article.updatedAt = .now
            }

            projectionUpdateCount += updateFeedProjection(of: article, from: feed)
            if reconcileArchiveState(
                of: article,
                keepingIdentities: incomingIdentities,
                fetchedAt: fetchedAt
            ) {
                reconciledArticleCount += 1
            }
            recordReconciliationProgress(
                stage: .projectionAndArchive,
                processedItemCount: index + 1,
                totalItemCount: articlesByIdentity.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .projectionAndArchive
        )

        recordReconciliationProgress(
            stage: .duplicateDeletion,
            processedItemCount: 0,
            totalItemCount: canonicalSnapshot.duplicateArticles.count
        )
        for (index, duplicateArticle) in canonicalSnapshot.duplicateArticles.enumerated() {
            try checkReconciliationCancellation(
                stage: .duplicateDeletion,
                beforeItemAt: index
            )
            modelContext.delete(duplicateArticle)
            recordReconciliationProgress(
                stage: .duplicateDeletion,
                processedItemCount: index + 1,
                totalItemCount: canonicalSnapshot.duplicateArticles.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .duplicateDeletion
        )

        try cancellationCheckpoint(.beforeUpsert)
        let upsertedArticles = try applyPayloads(
            payloads,
            into: feed,
            articlesByIdentity: &articlesByIdentity
        )
        try cancellationCheckpoint(.afterUpsert)

        if saveAfterOperation {
            try saveIfNeeded()
        }

        return ArticleFeedSnapshotReconciliationResult(
            projectionUpdateCount: projectionUpdateCount,
            reconciledArticleCount: reconciledArticleCount,
            upsertedArticleCount: upsertedArticles.count
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

    func delete(_ article: Article) throws {
        modelContext.delete(article)
        try saveIfNeeded()
    }

    func delete(_ articles: [Article], saveAfterOperation: Bool = true) throws {
        guard articles.isEmpty == false else { return }

        for article in articles {
            modelContext.delete(article)
        }

        if saveAfterOperation {
            try saveIfNeeded()
        }
    }

    private func updateFeedProjection(of article: Article, from feed: Feed) -> Int {
        var updatedCount = 0

        if article.feedTitle != feed.displayTitle {
            article.feedTitle = feed.displayTitle
            updatedCount += 1
        }

        if article.feedSiteURL != feed.siteURL {
            article.feedSiteURL = feed.siteURL
            updatedCount += 1
        }

        let folderName = feed.folder?.name
        if article.feedFolderName != folderName {
            article.feedFolderName = folderName
            updatedCount += 1
        }

        return updatedCount
    }

    private func reconcileArchiveState(
        of article: Article,
        keepingIdentities: Set<String>,
        fetchedAt: Date
    ) -> Bool {
        let identity = normalizedArticleIdentity(article.externalID)
        let shouldKeep = keepingIdentities.contains(identity)
        let newArchivedAt = shouldKeep ? nil : (article.archivedAt ?? fetchedAt)

        guard article.archivedAt != newArchivedAt else { return false }

        article.archivedAt = newArchivedAt
        article.fetchedAt = fetchedAt
        article.querySortDate = article.publishedAt ?? fetchedAt
        article.updatedAt = .now
        return true
    }

    private func applyPayloads(
        _ payloads: [ArticleUpsertPayload],
        into feed: Feed,
        articlesByIdentity: inout [String: Article]
    ) throws -> [Article] {
        var upsertedArticles: [Article] = []
        var upsertedIdentities: Set<String> = []

        recordReconciliationProgress(
            stage: .payloadApply,
            processedItemCount: 0,
            totalItemCount: payloads.count
        )
        for (index, payload) in payloads.enumerated() {
            try checkReconciliationCancellation(
                stage: .payloadApply,
                beforeItemAt: index
            )
            let identity = normalizedArticleIdentity(payload.externalID)
            let article: Article

            if let existingArticle = articlesByIdentity[identity] {
                apply(payload, to: existingArticle)
                article = existingArticle
            } else {
                article = makeArticle(from: payload, feed: feed)
                modelContext.insert(article)
                articlesByIdentity[identity] = article
            }

            if upsertedIdentities.insert(identity).inserted {
                upsertedArticles.append(article)
            }
            recordReconciliationProgress(
                stage: .payloadApply,
                processedItemCount: index + 1,
                totalItemCount: payloads.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .payloadApply
        )

        return upsertedArticles
    }

    private func apply(_ payload: ArticleUpsertPayload, to article: Article) {
        let updatedAt = Date.now
        article.guid = payload.guid
        article.url = payload.url
        article.canonicalURL = payload.canonicalURL
        article.title = payload.title
        article.summary = payload.summary
        article.contentHTML = payload.contentHTML
        article.contentText = payload.contentText
        article.searchableText = payload.searchableText
        article.author = payload.author
        article.publishedAt = payload.publishedAt
        article.updatedAtSource = payload.updatedAtSource
        article.imageURL = payload.imageURL
        article.fetchedAt = payload.fetchedAt
        article.querySortDate = payload.publishedAt ?? payload.fetchedAt
        article.updatedAt = updatedAt
    }

    private func makeArticle(from payload: ArticleUpsertPayload, feed: Feed) -> Article {
        Article(
            feedID: feed.id,
            feedTitle: feed.displayTitle,
            feedSiteURL: feed.siteURL,
            feedFolderName: feed.folder?.name,
            externalID: payload.externalID,
            guid: payload.guid,
            url: payload.url,
            canonicalURL: payload.canonicalURL,
            title: payload.title,
            summary: payload.summary,
            contentHTML: payload.contentHTML,
            contentText: payload.contentText,
            searchableText: payload.searchableText,
            author: payload.author,
            publishedAt: payload.publishedAt,
            updatedAtSource: payload.updatedAtSource,
            imageURL: payload.imageURL,
            fetchedAt: payload.fetchedAt
        )
    }

    private func normalizedArticleIdentity(_ externalID: String) -> String {
        normalizedIdentifier(externalID) ?? externalID
    }

    private func matchesStateCriteria(
        _ state: ArticleUserStateSnapshot?,
        criteria: ArticleQueryCriteria
    ) -> Bool {
        criteria.hidden.matches(state?.isHidden ?? false)
            && criteria.read.matches(state?.isRead ?? false)
            && criteria.starred.matches(state?.isStarred ?? false)
    }

    private func incomingIdentitySet(
        from payloads: [ArticleUpsertPayload]
    ) throws -> Set<String> {
        var identities: Set<String> = []
        identities.reserveCapacity(payloads.count)
        recordReconciliationProgress(
            stage: .incomingIdentityMaterialization,
            processedItemCount: 0,
            totalItemCount: payloads.count
        )

        for (index, payload) in payloads.enumerated() {
            try checkReconciliationCancellation(
                stage: .incomingIdentityMaterialization,
                beforeItemAt: index
            )
            identities.insert(normalizedArticleIdentity(payload.externalID))
            recordReconciliationProgress(
                stage: .incomingIdentityMaterialization,
                processedItemCount: index + 1,
                totalItemCount: payloads.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .incomingIdentityMaterialization
        )
        return identities
    }

    private func canonicalArticleSnapshot(
        from articles: [Article]
    ) throws -> (
        articlesByIdentity: [String: Article],
        duplicateArticles: [Article],
        duplicateIdentities: Set<String>
    ) {
        var articlesByIdentity: [String: Article] = [:]
        var duplicateArticles: [Article] = []
        var duplicateIdentities: Set<String> = []

        articlesByIdentity.reserveCapacity(articles.count)
        recordReconciliationProgress(
            stage: .snapshotCanonicalization,
            processedItemCount: 0,
            totalItemCount: articles.count
        )
        for (index, article) in articles.enumerated() {
            try checkReconciliationCancellation(
                stage: .snapshotCanonicalization,
                beforeItemAt: index
            )
            let identity = normalizedArticleIdentity(article.externalID)
            guard let existingCanonicalArticle = articlesByIdentity[identity] else {
                articlesByIdentity[identity] = article
                recordReconciliationProgress(
                    stage: .snapshotCanonicalization,
                    processedItemCount: index + 1,
                    totalItemCount: articles.count
                )
                continue
            }

            duplicateIdentities.insert(identity)
            if articleCanonicalOrder(article, existingCanonicalArticle) {
                articlesByIdentity[identity] = article
                duplicateArticles.append(existingCanonicalArticle)
            } else {
                duplicateArticles.append(article)
            }
            recordReconciliationProgress(
                stage: .snapshotCanonicalization,
                processedItemCount: index + 1,
                totalItemCount: articles.count
            )
        }
        try checkReconciliationCancellationAfterStage(
            .snapshotCanonicalization
        )

        return (articlesByIdentity, duplicateArticles, duplicateIdentities)
    }

    private func checkReconciliationCancellation(
        stage: ArticleFeedSnapshotReconciliationStage,
        beforeItemAt index: Int
    ) throws {
        guard index.isMultiple(
            of: ArticleFeedSnapshotReconciliationPolicy.cancellationCheckpointInterval
        ) else {
            return
        }
        try cancellationCheckpoint(.during(stage))
    }

    private func checkReconciliationCancellationAfterStage(
        _ stage: ArticleFeedSnapshotReconciliationStage
    ) throws {
        try cancellationCheckpoint(.during(stage))
    }

    private func recordReconciliationProgress(
        stage: ArticleFeedSnapshotReconciliationStage,
        processedItemCount: Int,
        totalItemCount: Int
    ) {
        reconciliationProgressProbe?(
            ArticleFeedSnapshotReconciliationProgress(
                stage: stage,
                processedItemCount: processedItemCount,
                totalItemCount: totalItemCount
            )
        )
    }

    private func articleCanonicalOrder(_ lhs: Article, _ rhs: Article) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.id.uuidString > rhs.id.uuidString
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
